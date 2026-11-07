import SwiftUI

#if DEBUG
private struct ToolPreviewScreen: View {
    @State private var approval = ToolActivity(name: "set_reminder", title: "设置提醒", arguments: "{\"title\":\"起床啦\",\"date\":\"2026-11-03T07:00:00+08:00\"}", reason: "你希望明早 7 点叫你起床。", destination: "api.deepseek.com / deepseek-flash")
    let dark: Bool
    private var theme: LumiTheme { LumiTheme(accentHex: dark ? "7654A5" : "287563", bubbleHex: dark ? "DCCDF5" : "297563") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ThemeChatPreview(theme: theme)
                    ToolActivityView(activity: approval, approve: { _, choice in approval.status = choice == .deny ? "denied" : "cancelled"; approval.result = "这是界面预览，没有设置实际通知。" }, send: { _ in })
                    Text("需要你点头的事，会认真问你。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Lumi").navigationBarTitleDisplayMode(.inline)
        }.environment(\.lumiTheme, theme).tint(theme.accent).preferredColorScheme(dark ? .dark : .light)
    }
}
#Preview("工具审批 · 浅色") { ToolPreviewScreen(dark: false).environment(\.locale, Locale(identifier: "zh-Hans")) }
#Preview("工具审批 · 深色") { ToolPreviewScreen(dark: true).environment(\.locale, Locale(identifier: "zh-Hans")) }
#endif
