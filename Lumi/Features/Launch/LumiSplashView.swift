import SwiftUI

struct LumiLaunchPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    @State private var isShowing = true
    @State private var presentationID = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing { LumiSplashView().id(presentationID).transition(.opacity).zIndex(10) }
            }
            .task(id: presentationID) {
                do {
                    try await Task.sleep(for: .milliseconds(reduceMotion || !animations ? 500 : 900))
                    withAnimation(animations && !reduceMotion ? .easeOut(duration: 0.25) : nil) { isShowing = false }
                } catch { }
            }

    }
}

struct LumiSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    @State private var appeared = false
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                LumiBrandIcon(size: 144)
                Text("Lumi").font(.system(.largeTitle, design: .rounded).weight(.medium))
            }
            .opacity(appeared || reduceMotion || !animations ? 1 : 0)
            .offset(y: appeared || reduceMotion || !animations ? 0 : 8)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("Lumi")
        .accessibilityIdentifier("launch.splash")
        .onAppear { withAnimation(reduceMotion || !animations ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.35)) { appeared = true } }
    }
}

#Preview("Launch") { LumiSplashView() }
