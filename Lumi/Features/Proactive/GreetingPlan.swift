import Foundation
import SwiftData

@Model final class ScheduledGreeting {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var fireDate: Date
    var text: String
    var scenario: String
    var stateRaw: String = "pending"
    var isClosure: Bool = false
    var createdAt: Date
    var importedAt: Date?
    var replyNoticeID: UUID?
    init(id: UUID = UUID(), characterID: UUID, fireDate: Date, text: String, scenario: String, isClosure: Bool = false) {
        self.id = id; self.characterID = characterID; self.fireDate = fireDate
        self.text = text; self.scenario = scenario; self.isClosure = isClosure; createdAt = .now
    }
    var requestID: String { "lumi.greeting." + id.uuidString }
}

struct CompanionPreferences: Sendable, Equatable {
    var enabled = false
    var dailyLimit = 1
    var quietStart = 22
    var quietEnd = 8
    var weather = false
    var calendar = false
    var battery = false
    var characterID = ""
    @MainActor static var current: Self {
        let d = AppPreferences.defaults
        return Self(enabled: d.bool(forKey: "proactive.enabled"),
                    dailyLimit: min(2, max(1, d.object(forKey: "proactive.limit") as? Int ?? 1)),
                    quietStart: min(23, max(0, d.object(forKey: "proactive.quietStart") as? Int ?? 22)),
                    quietEnd: min(23, max(0, d.object(forKey: "proactive.quietEnd") as? Int ?? 8)),
                    weather: d.bool(forKey: "context.weather"), calendar: d.bool(forKey: "context.calendar"),
                    battery: d.bool(forKey: "context.battery"), characterID: d.string(forKey: "proactive.character") ?? "")
    }
    func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if quietStart == quietEnd { return false }
        return quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
    }
}

struct GreetingCandidate: Sendable, Identifiable {
    var id: UUID
    var date: Date
    var text: String
    var scenario: String
    var isClosure = false
}

enum GreetingPlanner {
    static func jitter(_ date: Date, seconds: Int) -> Date { date.addingTimeInterval(Double(min(900, max(-900, seconds)))) }
    static func interval(lastReply: Date, now: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastReply), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= 7 ? 7 : days >= 3 ? 3 : 1
    }
    // Past notifications consume today's quota. Future candidates consume it only once selected.
    static func select(_ candidates: [GreetingCandidate], preferences: CompanionPreferences, now: Date,
                       lastReply: Date, sentDates: [Date] = [], occupiedSlots: Int = 0, calendar: Calendar = .current) -> [GreetingCandidate] {
        guard preferences.enabled else { return [] }
        var counts: [Date: Int] = [:]
        for date in sentDates { counts[calendar.startOfDay(for: date), default: 0] += 1 }
        var result: [GreetingCandidate] = []
        var seen = Set<UUID>()
        for candidate in candidates.sorted(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) {
            guard result.count < max(0, 64 - occupiedSlots), seen.insert(candidate.id).inserted,
                  candidate.date > now, !preferences.isQuiet(candidate.date, calendar: calendar) else { continue }
            let day = calendar.startOfDay(for: candidate.date)
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastReply), to: day).day ?? 0
            let frequency = interval(lastReply: lastReply, now: candidate.date, calendar: calendar)
            guard candidate.isClosure || days % frequency == 0 else { continue }
            guard counts[day, default: 0] < preferences.dailyLimit else { continue }
            result.append(candidate); counts[day, default: 0] += 1
        }
        return result
    }
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

struct GreetingJSON: Decodable, Sendable {
    let date: String
    let slot: String
    let scenario: String
    let text: String
    static func parse(_ raw: String, now: Date, days: Int = 7, calendar: Calendar = .current, offset: () -> Int = { Int.random(in: -900...900) }) throws -> [GreetingCandidate] {
        guard raw.utf8.count < 40_000, (3...7).contains(days), let data = raw.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              array.count <= days * 2, !array.isEmpty,
              array.allSatisfy({ Set($0.keys) == Set(["date", "slot", "scenario", "text"]) }) else { throw LLMError.invalidResponse }
        let entries = try JSONDecoder().decode([Self].self, from: data)
        guard Set(entries.map(\.date)).count >= 3 else { throw LLMError.invalidResponse }
        let hours = ["morning": 9, "noon": 12, "evening": 18, "night": 21]
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { throw LLMError.invalidResponse }
        var result: [GreetingCandidate] = []
        var seen = Set<String>()
        for entry in entries {
            let components = entry.date.split(separator: "-").compactMap { Int($0) }
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard components.count == 3, let hour = hours[entry.slot],
                  let day = calendar.date(from: DateComponents(year: components[0], month: components[1], day: components[2])),
                  GreetingPlanner.dayString(day, calendar: calendar) == entry.date, day >= start, day < end,
                  !text.isEmpty, text.count <= 40, !text.contains("<"), !text.contains("\n"), !SafetyGuard.isCrisis(text),
                  ["早安", "晚安", "想你", "纪念日", "关心", "其他"].contains(entry.scenario),
                  seen.insert(entry.date + entry.slot).inserted,
                  let base = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { throw LLMError.invalidResponse }
            let date = GreetingPlanner.jitter(base, seconds: offset())
            if date > now { result.append(GreetingCandidate(id: UUID(), date: date, text: text, scenario: entry.scenario)) }
        }
        guard !result.isEmpty else { throw LLMError.invalidResponse }
        return result
    }
}
