import Foundation
import Observation
import CoreLocation
import EventKit
import UIKit

struct ContextSnapshot: Sendable, Equatable {
    var weather: String?
    var calendar: String?
    var battery: String?
    func filtered(using preferences: CompanionPreferences) -> Self {
        Self(weather: preferences.weather ? weather : nil, calendar: preferences.calendar ? calendar : nil, battery: preferences.battery ? battery : nil)
    }
    func prompt(using preferences: CompanionPreferences) -> String {
        let value = filtered(using: preferences)
        var data: [String: String] = [:]
        if let weather = value.weather { data["weather"] = weather }
        if let calendar = value.calendar { data["calendar"] = calendar }
        if let battery = value.battery { data["battery"] = battery }
        return data.isEmpty ? "" : PromptBuilder.dataBlock(data)
    }
}

private final class WeatherRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable final class ContextService: NSObject, CLLocationManagerDelegate {
    static let shared = ContextService()
    var permissionNotice: String?
    private let location = CLLocationManager()
    private let events = EKEventStore()
    private var locationWaiter: CheckedContinuation<CLLocation?, Never>?
    private var locationTimeout: Task<Void, Never>?
    override init() { super.init(); location.delegate = self; location.desiredAccuracy = kCLLocationAccuracyThreeKilometers }
    func enableWeather() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: AppPreferences.defaults.set(true, forKey: "context.weather")
        default: denyLocation()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            // The callback never enables a feature unless the person requested it in this session.
            if requestingWeather { AppPreferences.defaults.set(true, forKey: "context.weather"); requestingWeather = false }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { denyLocation() }
    }
    private var requestingWeather = false
    func requestWeather() { requestingWeather = true; enableWeather() }
    func disableWeather() {
        requestingWeather = false; location.stopUpdatingLocation(); finishLocation(nil)
        AppPreferences.defaults.set(false, forKey: "context.weather")
    }
    private func denyLocation() {
        requestingWeather = false; AppPreferences.defaults.set(false, forKey: "context.weather")
        permissionNotice = String(localized: "未获得定位权限，天气保持关闭。可在系统设置中授权。", locale: AppLocale.current)
    }
    func enableCalendar() async {
        do {
            let granted = try await events.requestFullAccessToEvents()
            AppPreferences.defaults.set(granted, forKey: "context.calendar")
            if !granted { permissionNotice = String(localized: "未获得日历权限，日历情境保持关闭。", locale: AppLocale.current) }
        } catch { AppPreferences.defaults.set(false, forKey: "context.calendar") }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finishLocation(locations.last) }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) { finishLocation(nil) }
    private func finishLocation(_ result: CLLocation?) {
        locationTimeout?.cancel(); locationTimeout = nil
        locationWaiter?.resume(returning: result); locationWaiter = nil
    }
    private func coordinates(foreground: Bool) async -> CLLocation? {
        guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways else { return nil }
        // Never prompt or acquire a new location during background work.
        if !foreground { return location.location.flatMap { abs($0.timestamp.timeIntervalSinceNow) < 3600 ? $0 : nil } }
        guard locationWaiter == nil else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiter = continuation
            location.requestLocation()
            locationTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { self?.finishLocation(nil) }
            }
        }
    }
    func toolCalendar() async throws -> String {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            guard try await events.requestFullAccessToEvents() else { throw ToolError.unavailable }
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw ToolError.unavailable }
        try Task.checkCancellation()
        let result = await snapshot(preferences: CompanionPreferences(calendar: true), foreground: true, oneShot: true)
        return result.calendar?.isEmpty == false ? result.calendar! : "未来两天没有日历事件。"
    }
    func toolWeather() async throws -> String {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
            for _ in 0..<150 where location.authorizationStatus == .notDetermined {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        guard location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways else { throw ToolError.unavailable }
        let result = await snapshot(preferences: CompanionPreferences(weather: true), foreground: true, oneShot: true)
        guard let weather = result.weather else { throw ToolError.unavailable }; return weather
    }
    func snapshot(preferences: CompanionPreferences, foreground: Bool, now: Date = .now, oneShot: Bool = false) async -> ContextSnapshot {
        var result = ContextSnapshot()
        if preferences.calendar, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let start = Calendar.current.startOfDay(for: now)
            if let end = Calendar.current.date(byAdding: .day, value: 2, to: start) {
                let predicate = events.predicateForEvents(withStart: start, end: end, calendars: nil)
                result.calendar = events.events(matching: predicate).prefix(12).map {
                    "\(($0.title ?? "").prefix(100)) · \($0.startDate.formatted(date: .abbreviated, time: .shortened))"
                }.joined(separator: "\n")
            }
        }
        if preferences.battery {
            UIDevice.current.isBatteryMonitoringEnabled = true
            defer { UIDevice.current.isBatteryMonitoringEnabled = false }
            let level = UIDevice.current.batteryLevel
            if level >= 0 { result.battery = "\(Int(level * 100))%, state=\(UIDevice.current.batteryState.rawValue) (1=unplugged,2=charging,3=full)" }
        }
        if preferences.weather, let point = await coordinates(foreground: foreground), (oneShot || AppPreferences.defaults.bool(forKey: "context.weather")), !Task.isCancelled {
            // Round to roughly a kilometre; no coordinate is written to disk or sent to the language model.
            let lat = (point.coordinate.latitude * 100).rounded() / 100
            let lon = (point.coordinate.longitude * 100).rounded() / 100
            var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            url.queryItems = [URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
                             URLQueryItem(name: "current", value: "temperature_2m,weather_code"), URLQueryItem(name: "timezone", value: "auto")]
            if let endpoint = url.url {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 6; config.timeoutIntervalForResource = 7
                let session = URLSession(configuration: config, delegate: WeatherRedirectGuard(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                if let (data, response) = try? await session.data(from: endpoint), (response as? HTTPURLResponse)?.statusCode == 200,
                   data.count <= 50_000, let decoded = try? JSONDecoder().decode(Weather.self, from: data) {
                    result.weather = "\(decoded.current.temperature_2m)°C, WMO weather_code=\(decoded.current.weather_code), observed=\(decoded.current.time). Current conditions only; do not infer future weather."
                }
            }
        }
        return result.filtered(using: oneShot ? preferences : .current)
    }
    private struct Weather: Decodable { let current: Current
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let time: String }
    }
}
