import SwiftUI
import UserNotifications

enum SigningExpiry {
    static func expiration(profile: Data) -> Date? {
        guard profile.count <= 2_000_000,
              let start = profile.range(of: Data("<?xml".utf8)) ?? profile.range(of: Data("<plist".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound], format: nil) as? [String: Any] else { return nil }
        return plist["ExpirationDate"] as? Date
    }
    static var embeddedExpiration: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url) else { return nil }
        return expiration(profile: data)
    }
    static func estimatedExpiration(installed: Date) -> Date { installed.addingTimeInterval(7 * 86400) }
    static func reminderDate(expiration: Date, now: Date) -> Date? {
        guard expiration > now else { return nil }
        return max(now.addingTimeInterval(5), expiration.addingTimeInterval(-2 * 86400))
    }
}
@MainActor enum SigningReminder {
    static let identifier = "lumi.signing.expiry"
    static func schedule(expiration: Date, requestPermission: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        if requestPermission {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw VoiceError.permission }
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { throw VoiceError.permission }
        guard let date = SigningExpiry.reminderDate(expiration: expiration, now: .now) else { throw BackupError.invalid }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "记得续签 Lumi", locale: AppLocale.current)
        content.body = String(localized: "Lumi 即将到期，请打开 AltStore 或 SideStore 刷新签名。续签前建议保存一份备份。", locale: AppLocale.current)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        AppPreferences.defaults.set(expiration.timeIntervalSince1970, forKey: "signing.scheduledExpiry")
    }
    static func refresh() async {
        let d = AppPreferences.defaults
        guard d.bool(forKey: "signing.remind"), let expiry = SigningExpiry.embeddedExpiration,
              d.double(forKey: "signing.scheduledExpiry") != expiry.timeIntervalSince1970 else { return }
        try? await schedule(expiration: expiry, requestPermission: false)
    }
}
struct InstallationView: View {
    @AppStorage("signing.installed", store: AppPreferences.defaults) private var installed = Date().timeIntervalSince1970
    @AppStorage("signing.remind", store: AppPreferences.defaults) private var remind = false
    @State private var notice: String?
    private var expiry: Date { SigningExpiry.embeddedExpiration ?? SigningExpiry.estimatedExpiration(installed: Date(timeIntervalSince1970: installed)) }
    var body: some View {
        Form {
            Section("签名到期") {
                if SigningExpiry.embeddedExpiration == nil {
                    Text("当前构建无法读取签名到期时间。填写实际安装或最近续签日期，按免费签名的 7 天估算。")
                    DatePicker("安装或续签日期", selection: Binding(get: { Date(timeIntervalSince1970: installed) }, set: { installed = $0.timeIntervalSince1970; clearReminder() }), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                LabeledContent(SigningExpiry.embeddedExpiration == nil ? "预计到期" : "描述文件到期") { Text(expiry, format: .dateTime.year().month().day().hour().minute()) }
                Button(remind ? "更新续签提醒" : "开启续签提醒") {
                    Task {
                        do {
                            try await SigningReminder.schedule(expiration: expiry, requestPermission: true)
                            remind = true; notice = String(localized: "已设置：到期前 2 天提醒；若不足 2 天，将尽快提醒。", locale: AppLocale.current)
                        } catch { notice = error.localizedDescription }
                    }
                }
                if remind { Button("关闭续签提醒") { clearReminder() } }
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            Section("安装与续签教程") {
                Link("AltStore Classic 官方教程", destination: URL(string: "https://faq.altstore.io/altstore-classic/your-altstore")!)
                Link("SideStore 官方安装教程", destination: URL(string: "https://docs.sidestore.io/docs/installation/install")!)
                Text("免费 Apple 账号安装的 App 通常 7 天到期，同一设备最多同时激活 3 个侧载 App，包含侧载工具本身。请以所用工具显示的期限为准。").font(.caption).foregroundStyle(.secondary)
                Text("Lumi 不收集 Apple 账号，也不会自动替你续签。到期后请在原侧载工具中刷新，避免删除 App 导致本机数据丢失。").font(.caption).foregroundStyle(.secondary)
            }

        }.navigationTitle("安装与续签").navigationBarTitleDisplayMode(.inline)
        .onAppear { if AppPreferences.defaults.object(forKey: "signing.installed") == nil { installed = Date().timeIntervalSince1970 } }
    }
    private func clearReminder() {
        remind = false; AppPreferences.defaults.removeObject(forKey: "signing.scheduledExpiry")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [SigningReminder.identifier])
    }
}
#Preview { NavigationStack { InstallationView() } }
