import Foundation

enum AppPreferences {
    static var isUITesting: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-lumiUITests")
        #else
        false
        #endif
    }
    // UserDefaults synchronizes its own access; share one instance so AppStorage observes cross-view edits.
    nonisolated(unsafe) private static let uiTestDefaults = UserDefaults(suiteName: "app.lumi.ui-tests") ?? .standard
    static var defaults: UserDefaults { isUITesting ? uiTestDefaults : .standard }
}

enum AppLocale {
    static var current: Locale { Locale(identifier: AppPreferences.defaults.string(forKey: "language") ?? "zh-Hans") }
}
