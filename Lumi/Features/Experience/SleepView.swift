import SwiftUI
import Observation
import AVFoundation
import CoreHaptics

@MainActor @Observable final class SleepSession {
    private(set) var running = false
    private(set) var remaining = 0
    var error: String?
    private var player: AVAudioPlayer?
    private var timer: Task<Void, Never>?
    private var haptics: CHHapticEngine?
    private var hapticPlayer: (any CHHapticPatternPlayer)?
    func start(minutes: Int) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: Self.ambience())
            player.numberOfLoops = -1; player.volume = 0.16; player.prepareToPlay()
            guard player.play() else { throw VoiceError.unavailable }
            self.player = player; running = true
            remaining = min(60, max(1, minutes)) * 60
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    self.remaining -= 1
                    if self.remaining <= 30 { self.player?.volume = 0.16 * Float(max(0, self.remaining)) / 30 }
                    if self.remaining <= 0 { self.stop(); return }
                }
            }
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() {
        timer?.cancel(); timer = nil; player?.stop(); player = nil; running = false; remaining = 0
        SystemCharacterSpeech.shared.stop()
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate); haptics?.stop()
        hapticPlayer = nil; haptics = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func touch(hug: Bool) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            error = String(localized: "此设备不支持精细触感，可继续使用声音陪伴。", locale: AppLocale.current); return
        }
        do {
            let engine = try haptics ?? CHHapticEngine(); haptics = engine; try engine.start()
            let events: [CHHapticEvent] = hug
                ? [CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0.25), .init(parameterID: .hapticSharpness, value: 0.1)], relativeTime: 0, duration: 1.2)]
                : [0.0, 0.18, 0.9, 1.08].map { CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: 0.4), .init(parameterID: .hapticSharpness, value: 0.15)], relativeTime: $0) }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            hapticPlayer = player; try player.start(atTime: CHHapticTimeImmediate)
        } catch { self.error = error.localizedDescription }
    }
    nonisolated static func ambience() -> Data {
        // Original locally generated soft brown noise, no network/audio asset dependency.
        let rate = 22_050; let count = rate * 6; var samples = Data(); var value: Double = 0
        var seed: UInt32 = 0x4C554D49
        for i in 0..<count {
            seed = 1664525 &* seed &+ 1013904223
            let white = Double(seed) / Double(UInt32.max) * 2 - 1
            value = (value + 0.025 * white) / 1.025
            let envelope = min(1, Double(min(i, count - 1 - i)) / 500)
            var sample = Int16(max(-1, min(1, value * 3 * envelope)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var output = Data("RIFF".utf8)
        func integer<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { output.append(contentsOf: $0) } }
        integer(UInt32(36 + samples.count)); output.append(Data("WAVEfmt ".utf8)); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16))
        output.append(Data("data".utf8)); integer(UInt32(samples.count)); output.append(samples)
        return output
    }
}
struct SleepView: View {
    var narration: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lumiTheme) private var theme
    @State private var session = SleepSession()
    @State private var minutes = 15
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(theme.accent).padding(.top, 30)
                Text("让今天慢慢安静下来").font(.title2.bold())
                Text("柔和环境音由本机生成。结束前 30 秒渐弱，离开页面或进入后台会停止。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Stepper("定时 \(minutes) 分钟", value: $minutes, in: 1...60).disabled(session.running)
                if session.running {
                    Text(Duration.seconds(session.remaining).formatted(.time(pattern: .minuteSecond))).font(.largeTitle.monospacedDigit())
                    Button("停止陪伴", systemImage: "stop.circle") { session.stop() }.buttonStyle(.bordered)
                } else { Button("开始环境音", systemImage: "waveform") { session.start(minutes: minutes) }.lumiProminentButton().controlSize(.large) }
                Button("轻声读给我听", systemImage: "speaker.wave.1") {
                    SystemCharacterSpeech.shared.speak(narration.isEmpty ? String(localized: "今天已经辛苦了。慢慢放松肩膀，感受平稳的呼吸。此刻不必急着解决所有事情，给自己一点休息的时间。", locale: AppLocale.current) : narration, softly: true)
                }.buttonStyle(.bordered)
                HStack(spacing: 24) {
                    Button("心跳", systemImage: "heart") { session.touch(hug: false) }
                    Button("拥抱", systemImage: "hands.sparkles") { session.touch(hug: true) }
                }.buttonStyle(.bordered)
                if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Text("声音和触感是放松体验，不替代专业帮助。你也可以放下手机休息。").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(theme.background).navigationTitle("哄睡与触感").navigationBarTitleDisplayMode(.inline)
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in session.stop() }
    }
}
#Preview { NavigationStack { SleepView() } }
