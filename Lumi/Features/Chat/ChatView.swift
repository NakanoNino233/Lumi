import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    let provider: ProviderConfig
    var character: LumiCharacter? = nil
    var onChooseCharacter: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lumiTheme) private var theme
    @State private var model: ChatModel
    init(provider: ProviderConfig, character: LumiCharacter? = nil, onChooseCharacter: @escaping () -> Void = {}) {
        self.provider = provider; self.character = character; self.onChooseCharacter = onChooseCharacter
        _model = State(initialValue: ChatSessions.shared.chat(for: character?.id))
    }
    @State private var draft = ""
    @State private var sent = 0
    @State private var showSettings = false
    @State private var showMemories = false
    @State private var showProvider = false
    @State private var attachments: [ChatAttachment] = []
    @State private var photo: PhotosPickerItem?
    @State private var photoPicker = false
    @State private var filePicker = false
    @State private var loadingAttachment = false
    @State private var showMemes = false
    @State private var showSkills = false
    @State private var showCall = false
    @State private var showShare = false
    @State private var showSleep = false
    @State private var mountedSkills: Set<UUID> = []
    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(character: character ?? model.character, isGenerating: model.isGenerating)
            ChatTranscript(model: model, sent: sent, onCardSend: { draft = $0; send() })
            if let error = model.errorMessage { ChatErrorBanner(text: error) { model.dismissError() } }
            if !attachments.isEmpty { PendingAttachments(items: $attachments) }
            if loadingAttachment { ProgressView().padding(6) }
            if !mountedSkills.isEmpty { MountedSkillsBar(selection: $mountedSkills) }
            ChatComposer(draft: $draft, hasAttachments: !attachments.isEmpty, isLoading: loadingAttachment, onPhoto: { photoPicker = true }, onFile: { filePicker = true }, onMeme: { showMemes = true }, onSkill: { showSkills = true }, onVoiceSend: sendVoice, onCall: { showCall = true }, onSleep: { showSleep = true }, isGenerating: model.isGenerating, hasQueue: !model.queuedIDs.isEmpty, onSend: send, onStop: { model.stop() }, onResume: { model.resumeQueue() })
        }
        .background(theme.background)
        .modifier(LumiFeedback(trigger: sent))
        .navigationTitle(model.isGenerating ? String(localized: "对方输入中…", locale: AppLocale.current) : (character?.name ?? "Lumi")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("分享对话").accessibilityIdentifier("chat.share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMemories = true } label: { Image(systemName: "book.closed") }.accessibilityLabel("回忆").accessibilityIdentifier("chat.memories")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("设置").accessibilityIdentifier("chat.settings")
            }
        }
        .photosPicker(isPresented: $photoPicker, selection: $photo, matching: .images)
        .task(id: photo) {
            guard let photo else { return }; loadingAttachment = true; defer { loadingAttachment = false; self.photo = nil }
            do { guard let data = try await photo.loadTransferable(type: Data.self) else { throw AttachmentError.unreadable }; try Task.checkCancellation(); try appendAttachment(ChatAttachment.image(data)) }
            catch is CancellationError { } catch { model.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: ChatAttachment.fileTypes) { result in
            do { try appendAttachment(ChatAttachment.read(result.get())) } catch { model.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showCall) { NavigationStack { VoiceView(model: model, call: true) } }
        .sheet(isPresented: $showSleep) { NavigationStack { SleepView(narration: model.messages.last(where: { $0.role == "assistant" && $0.status == .complete })?.content ?? "") } }
        .sheet(isPresented: $showShare) { NavigationStack { ConversationShareView(messages: model.messages, friend: model.character?.name ?? "Lumi") } }
        .sheet(isPresented: $showSettings) { NavigationStack { AppSettingsView(provider: provider) } }
        .sheet(isPresented: $showMemes) { NavigationStack { MemePicker(onSelect: sendMeme) } }
        .sheet(isPresented: $showSkills) { NavigationStack { SkillMountView(selection: $mountedSkills) } }
        .sheet(isPresented: $showProvider) { NavigationStack { ProviderSettingsView(config: provider).toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showProvider = false } } } } }
        .sheet(isPresented: $showMemories) { if let character = character ?? model.character { NavigationStack { MemoriesView(character: character, provider: provider) } } }
        .task { model.configure(context: context, provider: provider, character: character); model.maintain(force: true); if let id = model.character?.id { ChatReadState.shared.enter(id) } }
        .onChange(of: scenePhase) { _, phase in
            guard let id = model.character?.id else { return }
            if phase == .active { ChatReadState.shared.enter(id) } else { ChatReadState.shared.leave(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumiWillRestore)) { _ in model.pauseForRestore() }
        .onDisappear { if let id = model.character?.id { ChatReadState.shared.leave(id) }; model.endSession() }
        .onChange(of: model.messages.count) { _, _ in if let id = model.character?.id { ChatReadState.shared.received(in: id) } }
        .onChange(of: ConversationRouter.shared.revision) { _, _ in model.reloadExternalMessages() }
    }
    private func appendAttachment(_ item: ChatAttachment) throws {
        let result = attachments + [item]
        try ChatAttachment.validate(result, supportsVision: true)
        attachments = result
    }
    private func send() {
        if !SafetyGuard.isCrisis(draft), !SafetyGuard.needsAssessment(draft), ((try? KeychainStore().read(for: provider.id)) ?? "").isEmpty {
            showProvider = true; return
        }
        do { try ChatAttachment.validate(attachments, supportsVision: provider.supportsVision) }
        catch { model.errorMessage = error.localizedDescription; return }
        if model.send(draft, attachments: attachments, mountedSkills: mountedSkills) { draft = ""; attachments = []; photo = nil; mountedSkills = []; sent += 1 }
    }
    private func sendVoice(_ voice: RecordedVoice) {
        let hasText = !voice.transcript.isEmpty
        let hasKey = !((try? KeychainStore().read(for: provider.id)) ?? "").isEmpty
        if model.send(hasText ? voice.transcript : "[语音消息，未能转写]", requestReply: hasText && hasKey, voice: voice) { sent += 1 }
        if !hasText { model.errorMessage = String(localized: "语音已发送，但未能识别文字。", locale: AppLocale.current) }
        else if !hasKey { showProvider = true }
    }
    private func sendMeme(_ meme: Meme) {
        do {
            let snapshot = try MemeStore.snapshot(meme)
            let hasKey = !((try? KeychainStore().read(for: provider.id)) ?? "").isEmpty
            if model.send("", memes: [snapshot], requestReply: hasKey) { sent += 1; meme.usageCount += 1; try context.save() }
        } catch { model.errorMessage = MemeError.image.localizedDescription }
    }
}

struct ChatHeader: View {
    let character: LumiCharacter?
    let isGenerating: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 12) {
            CharacterAvatar(data: character?.avatarData, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(isGenerating ? String(localized: "对方输入中…", locale: AppLocale.current) : (character?.name ?? "Lumi")).font(.body.weight(.medium)).lineLimit(1)
                if !typeSize.isAccessibilitySize {
                    Text(isGenerating ? LocalizedStringKey("正在认真想你的话…") : LocalizedStringKey("一句你好，就是故事的开始")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "heart").font(.system(size: 20, weight: .regular)).foregroundStyle(.secondary)
                Text(RelationshipEngine.stageName(character?.stageIndex ?? 0)).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.background)
    }
}

struct CharacterAvatar: View {
    var data: Data? = nil
    var size: CGFloat = 34
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        ZStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "sun.max.fill").font(.system(size: size * 0.48)).foregroundStyle(theme.accent)
            }
        }.frame(width: size, height: size).background(theme.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.34)).accessibilityHidden(true)
    }
}

struct ChatTranscript: View {
    let model: ChatModel
    var sent = 0
    var onCardSend: (String) -> Void = { _ in }
    var body: some View {
        FollowingTranscript(count: model.messages.count, revision: (model.messages.last?.content.hashValue ?? 0) ^ (model.messages.last?.toolActivityData?.hashValue ?? 0), sent: sent) {
            LazyVStack(spacing: 16) {
                ForEach(model.messages) { message in
                    MessageRow(message: message, avatar: model.character?.avatarData, isGenerating: model.isGenerating,
                               onDelete: { model.delete(message) }, onRegenerate: { model.regenerate(message) }, onSendNow: { model.sendImmediately(message.id) }, onApprove: { model.approveTool($0, choice: $1) }, onCardSend: onCardSend)
                        .modifier(MessageArrival(date: message.createdAt))
                }
            }.padding(.horizontal, 16).padding(.vertical, 24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
    }
}

struct MessageRow: View {
    let message: Message
    var avatar: Data? = nil
    let isGenerating: Bool
    var onDelete: () -> Void
    var onRegenerate: () -> Void
    var onSendNow: () -> Void
    var onApprove: (UUID, ToolApprovalChoice) -> Void = { _, _ in }
    var onCardSend: (String) -> Void = { _ in }
    @Environment(\.lumiTheme) private var theme
    @State private var copied = false
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    var body: some View {
        VStack(spacing: 8) {
            Text(message.createdAt, format: .dateTime.hour().minute()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            if message.role == "system" {
                Text(message.content).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8).background(.quaternary, in: Capsule())
            } else {
            HStack(alignment: .top, spacing: 8) {
                if message.role == "user" { Spacer(minLength: 42) } else { CharacterAvatar(data: avatar) }
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty && message.status == .generating {
                        TypingIndicator()
                    } else if !message.content.isEmpty && !(message.role == "user" && !message.memes.isEmpty && message.content.hasPrefix("[表情] ")) {
                        Text(message.content).textSelection(.enabled).font(.system(size: bodySize * CGFloat(max(12, min(28, theme.textSize))) / 17, design: theme.textDesign)).foregroundStyle(message.role == "user" ? theme.bubbleForeground : Color.primary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let data = message.voiceData { VoiceMessageBubble(data: data, duration: message.voiceDuration) }
                    ForEach(message.attachments) { item in AttachmentBubble(item: item) }
                    ForEach(message.memes) { meme in MemeBubble(meme: meme) }
                    if !message.recalledMemoryTexts.isEmpty {
                        ForEach(message.memoryCitations) { item in
                            Label("想起了…\(item.text)", systemImage: "book.closed").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if message.status == .queued {
                        HStack { Text("等待发送").font(.caption); Button("立即发送", action: onSendNow).font(.caption.bold()).accessibilityIdentifier("chat.sendNow") }
                    } else if message.status == .interrupted { Text("已停止").font(.caption2).foregroundStyle(.secondary) }
                    else if message.status == .failed { Text("发送失败，可重新生成").font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(message.role == "user" ? theme.bubbleForeground : Color.primary)
                .background(message.role == "user" ? theme.bubble : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: theme.bubbleRadius))
                .contextMenu {
                    Button("朗读", systemImage: "speaker.wave.2") { SystemCharacterSpeech.shared.speak(message.content) }
                    Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content; copied = true }
                    Button("重新生成", systemImage: "arrow.clockwise", action: onRegenerate).disabled(isGenerating || message.status == .queued)
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                }
                if message.role == "user" {
                    PersonalAvatar(size: 34)
                } else { Spacer(minLength: 42) }
            }
            }
            if copied { Label("已复制", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("chat.copied") }
            ForEach(message.toolActivities) { activity in ToolActivityView(activity: activity, approve: onApprove, send: onCardSend) }
        }.modifier(LumiFeedback(trigger: copied, enabled: copied))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }; copied = false
        }
    }
}

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lumiTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("interaction.animations", store: AppPreferences.defaults) private var animations = true
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduceMotion || !animations || scenePhase != .active)) { timeline in
            HStack(spacing: 5) {
                ForEach(0..<3) { dot in
                    Circle().fill(theme.accent.opacity(reduceMotion || !animations || Int(timeline.date.timeIntervalSinceReferenceDate * 3) % 3 == dot ? 0.85 : 0.25)).frame(width: 6, height: 6)
                }
            }.frame(height: 20)
        }.accessibilityLabel("正在输入")
    }
}

struct ChatErrorBanner: View {
    let text: String
    var onDismiss: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.circle")
            Text(text).font(.caption)
            Spacer()
            Button(action: onDismiss) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("关闭提示")
        }.foregroundStyle(.primary).padding(.leading, 16).padding(.trailing, 4).padding(.vertical, 4).background(.background)
    }
}

struct ChatComposer: View {
    @Binding var draft: String
    var hasAttachments = false
    var isLoading = false
    var onPhoto: () -> Void = {}
    var onFile: () -> Void = {}
    var onMeme: () -> Void = {}
    var onSkill: () -> Void = {}
    var onVoiceSend: (RecordedVoice) -> Void = { _ in }
    var onCall: () -> Void = {}
    var onSleep: () -> Void = {}
    @State private var voiceMode = false
    @FocusState private var textFocused: Bool
    let isGenerating: Bool
    let hasQueue: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onResume: () -> Void
    @Environment(\.lumiTheme) private var theme
    private var canSend: Bool { !isLoading && (hasAttachments || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var body: some View {
        VStack(spacing: 8) {
            if isGenerating {
                HStack {
                    Text("可以继续说，消息会排队发送").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("停止生成", systemImage: "stop.circle", action: onStop).font(.caption).accessibilityIdentifier("chat.stop")
                }
            } else if hasQueue {
                Button("继续发送排队消息", action: onResume).font(.caption)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(voiceMode ? "文字输入" : "语音输入", systemImage: voiceMode ? "keyboard" : "mic") { voiceMode.toggle(); textFocused = !voiceMode }
                    Button("语音通话", systemImage: "phone", action: onCall)
                    Button("哄睡与触感", systemImage: "moon.stars", action: onSleep)
                    Button("图片", systemImage: "photo", action: onPhoto)
                    Button("文件", systemImage: "doc", action: onFile)
                    Button("技能", systemImage: "square.stack", action: onSkill).accessibilityIdentifier("chat.skills")
                } label: { Image(systemName: "plus").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .foregroundStyle(.secondary)
                .disabled(isLoading).accessibilityLabel("添加附件").accessibilityIdentifier("chat.attach")
                if voiceMode {
                    HoldToTalkComposer(onSend: onVoiceSend)
                    Button { voiceMode = false; textFocused = true } label: { Image(systemName: "keyboard").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }.foregroundStyle(.secondary).accessibilityLabel("切换文字输入")
                } else {
                    TextField("说点什么…", text: $draft, axis: .vertical).lineLimit(1...5).padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)).focused($textFocused).accessibilityIdentifier("chat.input")
                }
                Button(action: onMeme) { Image(systemName: "face.smiling").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }.foregroundStyle(.secondary).accessibilityLabel("表情").accessibilityIdentifier("chat.memes")
                Button(action: onSend) {
                    Image(systemName: "arrow.up").font(.system(size: 20, weight: .medium)).foregroundStyle(canSend ? theme.accentForeground : .secondary).frame(width: 44, height: 44).background(canSend ? theme.accent : Color(uiColor: .secondarySystemFill), in: Circle())
                }.buttonStyle(LumiPressStyle()).disabled(!canSend).accessibilityLabel("发送").accessibilityIdentifier("chat.send")
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.bar)
    }
}

struct AppSettingsView: View {
    let provider: ProviderConfig
    var showsDone = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @AppStorage("language", store: AppPreferences.defaults) private var language = "zh-Hans"
    @AppStorage("automaticMemory", store: AppPreferences.defaults) private var automaticMemory = true
    @AppStorage("automaticDiary", store: AppPreferences.defaults) private var automaticDiary = true
    @AppStorage("memoryInterval", store: AppPreferences.defaults) private var memoryInterval = 8
    var body: some View {
        Form {
            Section("内容") { NavigationLink("内容市场") { MarketView() }.accessibilityIdentifier("settings.market") }
            Section("连接") { NavigationLink("API 配置") { ProviderSettingsView(config: provider) }.accessibilityIdentifier("settings.provider") }
            Section("用量") {
                NavigationLink("Token 用量与排行") { TokenUsageView() }.accessibilityIdentifier("settings.tokens")
            }
            Section("陪伴") { NavigationLink("主动问候与情境") { ProactiveSettingsView() }.accessibilityIdentifier("settings.proactive") }
            Section("表情") { NavigationLink("表情图库") { MemeLibraryView() } }
            Section("技能与工具") {
                NavigationLink("技能管理") { SkillLibraryView() }.accessibilityIdentifier("settings.skills")
                NavigationLink("工具授权") { ToolPermissionsView(provider: provider) }.accessibilityIdentifier("settings.tools")
            }
            Section("外观") {
                NavigationLink("动画与触感") { InteractionSettingsView() }.accessibilityIdentifier("settings.interaction")
                NavigationLink("界面颜色") { ThemeSettingsView() }.accessibilityIdentifier("settings.colors")
                Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                Picker("语言", selection: $language) { Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
            }
            Section("数据与体验") {
                NavigationLink("备份与恢复") { BackupView() }.accessibilityIdentifier("settings.backup")
                NavigationLink("哄睡与触感") { SleepView() }
                NavigationLink("安装与续签") { InstallationView() }
                NavigationLink("锁屏与小组件") { CompanionActivityView() }
                NavigationLink("健康使用提醒") { WellbeingSettingsView() }
            }
            Section {
                Toggle("自动整理记忆", isOn: $automaticMemory)
                Stepper("每 \(memoryInterval) 轮整理", value: $memoryInterval, in: 2...20).disabled(!automaticMemory)
                Toggle("自动日记", isOn: $automaticDiary)
            } header: { Text("记忆与日记") } footer: { Text("自动整理在达到轮数或离开聊天时运行；自动日记会整理已结束的一天，21 点后可整理当天。需要使用你配置的模型，系统可能中断后台处理。") }
            Section("关于 Lumi") {
                NavigationLink("隐私说明") { PrivacyView() }
            }
        }.navigationTitle("设置").toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
    }
}

#Preview("Chat") {
    NavigationStack { ChatView(provider: ProviderConfig()) }
        .modelContainer(for: LumiSchema.models, inMemory: true)
        .tint(.lumiAccent)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}
