import SwiftUI

struct HoldToTalkComposer: View {
    var onSend: (RecordedVoice) -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.lumiTheme) private var theme
    @State private var input = VoiceInput()
    @State private var holding = false
    @State private var cancelling = false
    var body: some View {
        VStack(spacing: 4) {
            if input.authorized {
                Text(input.finishing ? "正在发送…" : input.recording ? (cancelling ? "松开取消" : "松开发送 · 上滑取消") : "按住说话")
                    .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                    .background(input.recording ? theme.accent.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard !input.finishing else { return }
                        if !holding { holding = true; input.start() }
                        cancelling = value.translation.height < -65
                    }.onEnded { _ in
                        guard holding else { return }; holding = false
                        if cancelling { input.cancel(); cancelling = false } else { finish() }
                    })
                    .accessibilityAddTraits(.isButton).accessibilityIdentifier("chat.holdToTalk")
                    .accessibilityAction(named: "开始录音") { input.start() }
                    .accessibilityAction(named: "结束录音并发送") { finish() }
            } else {
                Button("启用麦克风") { Task { await input.authorize() } }.frame(maxWidth: .infinity, minHeight: 44)
            }
            if let error = input.error { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
        .task { await input.authorize() }
        .onChange(of: input.recording) { wasRecording, recording in
            if wasRecording && !recording && holding { holding = false; finish() }
        }
        .onChange(of: phase) { _, value in if value != .active { holding = false; input.cancel() } }
        .onDisappear { holding = false; input.cancel() }
    }
    private func finish() {
        Task { if let voice = await input.finishVoice() { onSend(voice) } }
    }
}

struct VoiceMessageBubble: View {
    let data: Data
    let duration: TimeInterval
    @Environment(\.scenePhase) private var phase
    @State private var playback = VoicePlayback()
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { playback.toggle(data) } label: {
                Label("\(Int(max(1, duration.rounded()))) 秒", systemImage: playback.playing ? "stop.fill" : "waveform")
                    .font(.body.weight(.medium)).padding(.vertical, 6).frame(minWidth: 80, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel(playback.playing ? "停止语音" : "播放语音")
            if let error = playback.error { Text(error).font(.caption2).foregroundStyle(.orange) }
        }
        .onChange(of: phase) { _, value in if value != .active { playback.stop() } }
        .onDisappear { playback.stop() }
    }
}
