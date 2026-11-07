import SwiftUI

struct VoiceView: View {
    let model: ChatModel
    let call: Bool
    var onDictation: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lumiTheme) private var theme
    @State private var input = VoiceInput()
    @State private var holding = false
    @State private var softly = false
    @State private var spokenIDs: Set<UUID> = []
    @State private var sentIDs: Set<UUID> = []
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                CharacterAvatar(data: model.character?.avatarData, size: 112)
                Text(model.character?.name ?? "Lumi").font(.largeTitle.bold())
                Text(call ? "按住说话，松开后发送；文字记录保存在聊天中。" : "按住说话，松开后填入输入框，确认后再发送。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.isGenerating { Label("正在认真想你的话…", systemImage: "sparkles") }
                if !input.transcript.isEmpty { Text(input.transcript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if call, let reply = model.messages.last(where: { $0.role == "assistant" && $0.status == .complete }) {
                    Text(reply.content).font(.title3).textSelection(.enabled)
                }
                if let error = input.error ?? model.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                if input.authorized {
                    Text(input.recording ? "松开发送" : "按住说话")
                        .font(.headline).foregroundStyle(theme.accentForeground)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(input.recording ? theme.accent.opacity(0.7) : theme.accent, in: Capsule())
                        .contentShape(Capsule())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in
                            guard !holding, !model.isGenerating, !input.finishing else { return }
                            holding = true; input.start()
                        }.onEnded { _ in holding = false; finish() })
                        .accessibilityAddTraits(.isButton).accessibilityLabel("按住说话")
                        .accessibilityAction(named: "开始录音") { input.start() }
                        .accessibilityAction(named: "结束录音") { finish() }
                        .opacity(model.isGenerating || input.finishing ? 0.4 : 1)
                } else { Button("启用语音") { Task { await input.authorize() } }.lumiProminentButton().controlSize(.large) }
                if call {
                    Toggle("轻声朗读", isOn: $softly)
                    Button("停止朗读", systemImage: "speaker.slash") { SystemCharacterSpeech.shared.stop() }
                    Button("停止生成", systemImage: "stop.circle") { model.stop() }.disabled(!model.isGenerating)
                }
                Text("录音仅用于本机识别，不保留音频；发送后的文字交给你配置的模型。需要设备支持当前语言的本机识别。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(theme.background)
        .navigationTitle(call ? "语音通话" : "语音输入").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("结束") { dismiss() } } }
        .onChange(of: model.isGenerating) { _, generating in
            guard call, !generating, let reply = model.messages.last(where: { $0.role == "assistant" && $0.status == .complete }),
                  let replyTo = reply.replyToID, sentIDs.contains(replyTo), spokenIDs.insert(reply.id).inserted else { return }
            SystemCharacterSpeech.shared.speak(reply.content, softly: softly)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { input.cancel(); holding = false; SystemCharacterSpeech.shared.stop() } }
        .onDisappear { input.cancel(); SystemCharacterSpeech.shared.stop() }
    }
    private func finish() {
        Task {
            let text = await input.finish()
            guard !text.isEmpty else { return }
            if call {
                if model.send(text), let id = model.messages.last(where: { $0.role == "user" })?.id { sentIDs.insert(id) }
            } else { onDictation(text); dismiss() }
        }
    }
}
