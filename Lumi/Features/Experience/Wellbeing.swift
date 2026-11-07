import SwiftUI

struct WellbeingSettingsView: View {
    @AppStorage("wellbeing.enabled", store: AppPreferences.defaults) private var enabled = false
    @AppStorage("wellbeing.minutes", store: AppPreferences.defaults) private var minutes = 30
    var body: some View {
        Form {
            Section {
                Toggle("健康使用提醒", isOn: $enabled)
                Stepper("连续使用 \(minutes) 分钟后提醒", value: $minutes, in: 5...180, step: 5).disabled(!enabled)
            } footer: { Text("仅在前台连续使用时计时。提醒你休息、喝水，给现实中的亲友留些时间。进入后台后重新计时，不发送额外通知。") }
        }.navigationTitle("健康使用提醒").navigationBarTitleDisplayMode(.inline)
    }
}
struct WellbeingReminder: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("wellbeing.enabled", store: AppPreferences.defaults) private var enabled = false
    @AppStorage("wellbeing.minutes", store: AppPreferences.defaults) private var minutes = 30
    @State private var show = false
    private var timerKey: String { "\(scenePhase == .active)-\(enabled)-\(minutes)" }
    func body(content: Content) -> some View {
        content.task(id: timerKey) {
            guard enabled, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(max(5, min(180, minutes)) * 60)) } catch { return }
                guard !Task.isCancelled else { return }; show = true
            }
        }.alert("给自己一点休息时间", isPresented: $show) {
            Button("好，休息一下", role: .cancel) { }
        } message: { Text("喝点水，看看远处，或和身边的人聊聊天。Lumi 会在这里，等你方便时再回来。") }
    }
}
