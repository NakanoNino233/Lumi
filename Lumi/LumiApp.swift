import SwiftUI
import SwiftData

@main struct LumiApp: App {
    @UIApplicationDelegateAdaptor(LumiAppDelegate.self) private var appDelegate
    private let container: ModelContainer?
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @AppStorage("language", store: AppPreferences.defaults) private var language = "zh-Hans"
    @AppStorage("theme.accent", store: AppPreferences.defaults) private var accent = "287563"
    @AppStorage("theme.bubble", store: AppPreferences.defaults) private var bubble = "297563"
    @AppStorage("theme.background", store: AppPreferences.defaults) private var background = ""
    @AppStorage("theme.font", store: AppPreferences.defaults) private var fontDesign = "system"
    @AppStorage("theme.bubbleStyle", store: AppPreferences.defaults) private var bubbleStyle = "rounded"
    @AppStorage("theme.textSize", store: AppPreferences.defaults) private var textSize = 17
    private var theme: LumiTheme { LumiTheme(accentHex: accent, bubbleHex: bubble, backgroundHex: background, fontDesign: fontDesign, bubbleStyle: bubbleStyle, textSize: textSize) }
    init() {
        if AppPreferences.isUITesting {
            AppPreferences.defaults.removePersistentDomain(forName: "app.lumi.ui-tests")
            if !CommandLine.arguments.contains("-lumiUITestsProfileSetup") {
                AppPreferences.defaults.set(true, forKey: PersonalProfile.completedKey)
            }
            if CommandLine.arguments.contains("-lumiUITestsReady") { AppPreferences.defaults.set(3, forKey: "onboardingStep") }
        }
        container = CompanionRuntime.container
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    .modelContainer(container)
                    .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.lumiTheme, theme)
                    .tint(theme.accent)
            } else {
                ContentUnavailableView("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark", description: Text("请检查设备空间并重新启动。已有数据不会被自动清除。"))
            }
        }
    }
}

extension Color {
    static let lumiAccent = Color("AccentColor")
    static let lumiBubble = Color(red: 0.16, green: 0.46, blue: 0.39)
}
