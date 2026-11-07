import SwiftUI

struct LumiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && animations && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(animations && !reduceMotion ? .timingCurve(0.22, 1, 0.36, 1, duration: 0.16) : nil, value: configuration.isPressed)
    }
}

struct LumiFeedback<Value: Equatable>: ViewModifier {
    let trigger: Value
    var enabled = true
    @AppStorage("interaction.haptics", store: AppPreferences.defaults) private var haptics = true
    func body(content: Content) -> some View {
        content.sensoryFeedback(.selection, trigger: trigger) { _, _ in haptics && enabled }
    }
}

struct InteractionSettingsView: View {
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    @AppStorage("interaction.haptics", store: AppPreferences.defaults) private var haptics = true
    @State private var sample = 0
    var body: some View {
        Form {
            Section {
                Toggle("轻盈动画", isOn: $animations).accessibilityIdentifier("interaction.animations")
                Toggle("轻触反馈", isOn: $haptics).accessibilityIdentifier("interaction.haptics")
            } footer: { Text("动画用于新消息和按钮反馈。开启系统“减少动态效果”时，会自动减少动画。触感仅在支持的设备上生效。") }
            Section("试一试") {
                Button { sample += 1 } label: {
                    Label("轻点感受一下", systemImage: "hand.tap")
                        .padding(12)
                }.buttonStyle(LumiPressStyle()).modifier(LumiFeedback(trigger: sample))
            }
            Section { Text("翻看旧消息时会暂停跟随回复；轻点“回到最新消息”即可继续跟随。").font(.subheadline).foregroundStyle(.secondary) }
        }.navigationTitle("动画与触感").navigationBarTitleDisplayMode(.inline)
    }
}

/// Follow the bottom until the reader scrolls away; resume automatically on returning to it.
struct FollowingTranscript<Content: View>: View {
    let count: Int
    let revision: Int
    var sent: Int = 0
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    @State private var following = true
    @State private var bottomY: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var readerScrolling = false
    private var animation: Animation? { animations && !reduceMotion ? .easeOut(duration: 0.22) : nil }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
                Color.clear.frame(height: 1).id("transcript.latest")
                    .background(GeometryReader { geometry in
                        if #unavailable(iOS 18) {
                            Color.clear.preference(key: TranscriptBottomKey.self, value: geometry.frame(in: .global).maxY)
                        }
                    })
            }
            .modifier(TranscriptScrollTracking { bottom, viewport in
                bottomY = bottom; viewportHeight = viewport
                if readerScrolling { following = TranscriptPosition.isAtBottom(bottom: bottom, viewport: viewport) }
            })
            .onPreferenceChange(TranscriptBottomKey.self) { value in
                bottomY = value
                if viewportHeight > 0 && readerScrolling { following = TranscriptPosition.isAtBottom(bottom: value, viewport: viewportHeight) }
            }
            .onPreferenceChange(TranscriptViewportKey.self) { value in
                viewportHeight = value
                if value > 0 && readerScrolling { following = TranscriptPosition.isAtBottom(bottom: bottomY, viewport: value) }
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
                readerScrolling = true
                following = TranscriptPosition.isAtBottom(bottom: bottomY, viewport: viewportHeight)
            })
            .onChange(of: count) { _, _ in
                if following { readerScrolling = false; withAnimation(animation) { proxy.scrollTo("transcript.latest", anchor: .bottom) } }
            }
            .onChange(of: revision) { _, _ in
                if following { readerScrolling = false; proxy.scrollTo("transcript.latest", anchor: .bottom) }
            }
            .onChange(of: sent) { _, _ in
                following = true; readerScrolling = false
                withAnimation(animation) { proxy.scrollTo("transcript.latest", anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !following {
                    Button {
                        following = true; readerScrolling = false
                        withAnimation(animation) { proxy.scrollTo("transcript.latest", anchor: .bottom) }
                    } label: {
                        Label("回到最新消息", systemImage: "arrow.down")
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                    }.buttonStyle(LumiPressStyle()).padding(12).accessibilityIdentifier("chat.latest")
                }
            }
        }
    }
}

enum TranscriptPosition {
    static func isAtBottom(bottom: CGFloat, viewport: CGFloat) -> Bool { bottom <= viewport + 60 }
}
private struct TranscriptBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct TranscriptViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TranscriptMetrics: Equatable {
    let bottom: CGFloat
    let viewport: CGFloat
}

private struct TranscriptScrollTracking: ViewModifier {
    var update: (CGFloat, CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: TranscriptMetrics.self) { geometry in
                TranscriptMetrics(bottom: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y,
                                  viewport: geometry.containerSize.height)
            } action: { _, metrics in update(metrics.bottom, metrics.viewport) }
        } else {
            content.background(GeometryReader { geometry in
                Color.clear.preference(key: TranscriptViewportKey.self, value: geometry.frame(in: .global).maxY)
            })
        }
    }
}

struct MessageArrival: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    let date: Date
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion || !animations ? 0 : 8)
            .onAppear {
                // Historical rows appear immediately, including those recycled while scrolling.
                withAnimation(animations && !reduceMotion && abs(date.timeIntervalSinceNow) < 2 ? .easeOut(duration: 0.22) : nil) { appeared = true }
            }
    }
}

#Preview { NavigationStack { InteractionSettingsView() } }
