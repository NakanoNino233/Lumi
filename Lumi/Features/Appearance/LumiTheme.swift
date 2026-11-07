import SwiftUI
import UIKit

struct ThemeColor: Equatable, Sendable {
    let rgb: UInt32
    init(rgb: UInt32) { self.rgb = rgb & 0xFFFFFF }
    init(hex: String, fallback: UInt32) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        rgb = clean.count == 6 ? (UInt32(clean, radix: 16) ?? fallback) : fallback
    }
    var hex: String { String(format: "%06X", rgb) }
    var red: Double { Double((rgb >> 16) & 255) / 255 }
    var green: Double { Double((rgb >> 8) & 255) / 255 }
    var blue: Double { Double(rgb & 255) / 255 }
    var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    var color: Color { Color(red: red, green: green, blue: blue) }
    var foreground: Color { luminance > 0.179 ? .black : .white }
    func accentColor(dark: Bool) -> Self {
        for step in 0...20 {
            let mix = Double(step) / 20
            let target: Double = dark ? 1 : 0
            let r = red * (1 - mix) + target * mix
            let g = green * (1 - mix) + target * mix
            let b = blue * (1 - mix) + target * mix
            let color = Self(rgb: UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded()))
            if dark ? color.luminance >= 0.32 : color.luminance <= 0.16 { return color }
        }
        return Self(rgb: dark ? 0xFFFFFF : 0)
    }
    @MainActor static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "287563" }
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

struct LumiTheme: Equatable, Sendable {
    var accentHex = "287563"
    var bubbleHex = "297563"
    var backgroundHex = ""
    var fontDesign = "system"
    var bubbleStyle = "rounded"
    var textSize = 17
    var textDesign: Font.Design { switch fontDesign { case "rounded": .rounded; case "serif": .serif; case "monospaced": .monospaced; default: .default } }
    var bubbleRadius: CGFloat { switch bubbleStyle { case "soft": 26; case "square": 6; default: 19 } }
    var accent: Color {
        let value = ThemeColor(hex: accentHex, fallback: 0x287563)
        // Keep accent labels readable in either appearance, even for very pale or dark choices.
        return Color(uiColor: UIColor { traits in
            let color = value.accentColor(dark: traits.userInterfaceStyle == .dark)
            return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        })
    }
    var bubble: Color { ThemeColor(hex: bubbleHex, fallback: 0x297563).color }
    var accentForeground: Color {
        let color = ThemeColor(hex: accentHex, fallback: 0x287563)
        return Color(uiColor: UIColor { traits in
            color.accentColor(dark: traits.userInterfaceStyle == .dark).luminance > 0.179 ? .black : .white
        })
    }
    var bubbleForeground: Color { ThemeColor(hex: bubbleHex, fallback: 0x297563).foreground }
    var background: Color {
        guard !backgroundHex.isEmpty else { return Color(uiColor: .systemGroupedBackground) }
        let value = ThemeColor(hex: backgroundHex, fallback: 0xF2F2F7)
        return Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let mix: Double = dark ? 0.86 : 0.88
            let target: Double = dark ? 0 : 1
            return UIColor(red: value.red * (1 - mix) + target * mix, green: value.green * (1 - mix) + target * mix, blue: value.blue * (1 - mix) + target * mix, alpha: 1)
        })
    }
}
private struct LumiThemeKey: EnvironmentKey { static let defaultValue = LumiTheme() }
extension EnvironmentValues {
    var lumiTheme: LumiTheme {
        get { self[LumiThemeKey.self] }
        set { self[LumiThemeKey.self] = newValue }
    }
}
private struct LumiProminentButton: ViewModifier {
    @Environment(\.lumiTheme) private var theme
    func body(content: Content) -> some View { content.buttonStyle(.borderedProminent).foregroundStyle(theme.accentForeground) }
}
extension View {
    func lumiProminentButton() -> some View { modifier(LumiProminentButton()) }
}

struct ThemeSettingsView: View {
    @AppStorage("theme.accent", store: AppPreferences.defaults) private var accent = "287563"
    @AppStorage("theme.bubble", store: AppPreferences.defaults) private var bubble = "297563"
    @AppStorage("theme.background", store: AppPreferences.defaults) private var background = ""
    @AppStorage("theme.font", store: AppPreferences.defaults) private var fontDesign = "system"
    @AppStorage("theme.bubbleStyle", store: AppPreferences.defaults) private var bubbleStyle = "rounded"
    @AppStorage("theme.textSize", store: AppPreferences.defaults) private var textSize = 17
    private var current: LumiTheme { LumiTheme(accentHex: accent, bubbleHex: bubble, backgroundHex: background, fontDesign: fontDesign, bubbleStyle: bubbleStyle, textSize: textSize) }
    var body: some View {
        Form {
            Section("聊天预览") { ThemeChatPreview(theme: current) }
            Section("自定义颜色") {
                ColorPicker("界面强调色", selection: colorBinding($accent, fallback: 0x287563), supportsOpacity: false).accessibilityIdentifier("theme.accent")
                ColorPicker("我的聊天气泡", selection: colorBinding($bubble, fallback: 0x297563), supportsOpacity: false).accessibilityIdentifier("theme.bubble")
                Toggle("自定义聊天背景", isOn: Binding(get: { !background.isEmpty }, set: { background = $0 ? "F2F2F7" : "" }))
                if !background.isEmpty { ColorPicker("聊天背景", selection: colorBinding($background, fallback: 0xF2F2F7), supportsOpacity: false) }
                Text("修改会立即保存，并应用到整个 App。气泡文字自动选择清晰颜色，背景随深浅模式适配。").font(.caption).foregroundStyle(.secondary)
            }
            Section("聊天样式") {
                Stepper("聊天字号 \(textSize)", value: $textSize, in: 12...28)
                Text("同时跟随系统文字大小缩放。").font(.caption).foregroundStyle(.secondary)
                Picker("字体", selection: $fontDesign) { Text("系统").tag("system"); Text("圆体").tag("rounded"); Text("衬线").tag("serif"); Text("等宽").tag("monospaced") }
                Picker("气泡样式", selection: $bubbleStyle) { Text("圆角").tag("rounded"); Text("柔和").tag("soft"); Text("方角").tag("square") }
            }
            Section { NavigationLink("桌面图标") { AlternateIconView() } }
            Section("配色方案") {
                ThemePresetButton(name: "森林绿", accent: "287563", bubble: "297563") { apply("287563", "297563") }.accessibilityIdentifier("theme.green")
                ThemePresetButton(name: "鸢尾紫", accent: "7654A5", bubble: "DCCDF5") { apply("7654A5", "DCCDF5") }.accessibilityIdentifier("theme.purple")
                ThemePresetButton(name: "晴空蓝", accent: "286DB6", bubble: "C9E7FF") { apply("286DB6", "C9E7FF") }.accessibilityIdentifier("theme.blue")
                ThemePresetButton(name: "玫瑰粉", accent: "A83D70", bubble: "F8CFE2") { apply("A83D70", "F8CFE2") }.accessibilityIdentifier("theme.rose")
                Button("恢复默认颜色") { accent = "287563"; bubble = "297563"; background = "" }.accessibilityIdentifier("theme.reset")
            }
        }.navigationTitle("界面颜色").navigationBarTitleDisplayMode(.inline)
    }
    private func apply(_ a: String, _ b: String) { accent = a; bubble = b }
    private func colorBinding(_ value: Binding<String>, fallback: UInt32) -> Binding<Color> {
        Binding(get: { ThemeColor(hex: value.wrappedValue, fallback: fallback).color }, set: { value.wrappedValue = ThemeColor.hex($0) })
    }
}
struct ThemePresetButton: View {
    let name: LocalizedStringKey
    let accent: String
    let bubble: String
    var apply: () -> Void
    var body: some View {
        Button(action: apply) {
            HStack { Circle().fill(ThemeColor(hex: accent, fallback: 0).color).frame(width: 22, height: 22); Text(name); Spacer(); Capsule().fill(ThemeColor(hex: bubble, fallback: 0).color).frame(width: 45, height: 24) }
        }.foregroundStyle(.primary)
    }
}
struct ThemeChatPreview: View {
    let theme: LumiTheme
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumi").font(.body.weight(.medium))
            Text("今天过得怎么样？").padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: theme.bubbleRadius))
            HStack { Spacer(); Text("有你陪着，心情很好。").padding(12).foregroundStyle(theme.bubbleForeground).background(theme.bubble, in: RoundedRectangle(cornerRadius: theme.bubbleRadius)) }
        }.font(.system(size: bodySize * CGFloat(max(12, min(28, theme.textSize))) / 17, design: theme.textDesign)).padding().background(theme.background, in: RoundedRectangle(cornerRadius: 20))
    }
}
