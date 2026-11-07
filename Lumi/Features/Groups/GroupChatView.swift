import SwiftUI
import SwiftData

struct GroupChatView: View {
    let group: GroupChat
    let provider: ProviderConfig
    var onPrivateChat: (LumiCharacter) -> Void
    var onDelete: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.lumiTheme) private var theme
    @Environment(\.scenePhase) private var phase
    @Query private var friends: [LumiCharacter]
    @State private var model: GroupChatModel
    init(group: GroupChat, provider: ProviderConfig, onPrivateChat: @escaping (LumiCharacter) -> Void, onDelete: @escaping () -> Void) {
        self.group = group; self.provider = provider; self.onPrivateChat = onPrivateChat; self.onDelete = onDelete
        _model = State(initialValue: ChatSessions.shared.group(for: group.id))
    }
    @State private var draft = ""
    @State private var sent = 0
    @State private var editing = false
    @State private var deleted = false
    @FocusState private var focused: Bool
    private var members: [LumiCharacter] { friends.filter { group.memberIDs.contains($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            if !group.announcement.isEmpty {
                Label(group.announcement, systemImage: "megaphone").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.bar)
            }
            FollowingTranscript(count: model.messages.count, revision: model.typingName.hashValue, sent: sent) {
                    LazyVStack(spacing: 16) {
                        Text("\(members.count) 位 AI 好友 · \(group.scene)").font(.caption2).foregroundStyle(.secondary).padding(.top)
                        ForEach(model.messages) { message in
                            GroupMessageRow(message: message, friend: friends.first { $0.id == message.speakerID }, colorIndex: group.memberIDs.firstIndex(of: message.speakerID ?? UUID.zero) ?? 0, onPrivateChat: onPrivateChat)
                                .id(message.id).modifier(MessageArrival(date: message.createdAt))
                        }
                        if let name = model.typingName { Text("\(name) 正在输入…").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            if let error = model.errorMessage {
                HStack { Text(error).font(.caption); Spacer(); Button("重试") { model.retry() } }
                    .padding(12).background(theme.accent.opacity(0.08)).accessibilityIdentifier("group.error")
            }
            if model.waitingForAutomatic || model.isGenerating {
                HStack {
                    Text(model.isGenerating ? "好友正在回复…" : "稍后开始自动闲聊…").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("停止") { model.stop() }.accessibilityIdentifier("group.stop")
                }.padding(.horizontal).padding(.vertical, 8).background(.bar)
            }
            GroupComposer(text: $draft, members: members, generating: model.isGenerating, focused: $focused) {
                if model.send(draft) { draft = ""; focused = false; sent += 1 }
            }
        }
        .background(theme.background)
        .modifier(LumiFeedback(trigger: sent))
        .navigationTitle(model.typingName.map { String(localized: "\($0) 输入中…", locale: AppLocale.current) } ?? group.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("群设置", systemImage: "person.3.sequence") { model.stop(); editing = true }.accessibilityIdentifier("group.settings") } }
        .sheet(isPresented: $editing, onDismiss: { if deleted { onDelete() } else { configure() } }) {
            NavigationStack { GroupEditorView(group: group, onSave: { _ in }, onDelete: { deleted = true; editing = false }) }
        }
        .task { configure(); ChatReadState.shared.enter(group.id) }
        .onReceive(NotificationCenter.default.publisher(for: .lumiWillRestore)) { _ in model.stop(notice: false) }
        .onDisappear { ChatReadState.shared.leave(group.id) }
        .onChange(of: phase) { _, value in
            if value == .active { ChatReadState.shared.enter(group.id) } else { ChatReadState.shared.leave(group.id) }
        }
    }
    private func configure() { model.configure(group: group, provider: provider, context: context) }
}

private extension UUID { static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) }

private struct GroupComposer: View {
    @Environment(\.lumiTheme) private var theme
    @Binding var text: String
    let members: [LumiCharacter]
    let generating: Bool
    var focused: FocusState<Bool>.Binding
    var send: () -> Void
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generating }
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                ForEach(members) { friend in
                    Button(friend.name) { text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + "@\(friend.name) "; focused.wrappedValue = true }
                        .accessibilityIdentifier("group.mention.\(friend.name)")
                }
            } label: { Image(systemName: "at").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .foregroundStyle(.secondary)
                .accessibilityLabel("提及好友").accessibilityIdentifier("group.mentions")
            TextField("在群里说点什么…", text: $text, axis: .vertical).lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .focused(focused).accessibilityIdentifier("group.input")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                    .foregroundStyle(canSend ? theme.accentForeground : .secondary)
                    .background(canSend ? theme.accent : Color(uiColor: .secondarySystemFill), in: Circle())
            }.buttonStyle(LumiPressStyle()).disabled(!canSend)
                .accessibilityLabel("发送").accessibilityIdentifier("group.send")
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.bar)
    }
}

struct GroupMessageRow: View {
    let message: GroupMessage
    let friend: LumiCharacter?
    var colorIndex = 0
    var onPrivateChat: (LumiCharacter) -> Void
    @Environment(\.lumiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    private var own: Bool { message.role == "user" }
    private var memberColor: Color {
        [Color.teal, .blue, .purple, .orange, .pink, .indigo][abs(colorIndex % 6)].opacity(0.14)
    }
    var body: some View {
        VStack {
            if message.role == "system" {
                Text(message.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if own { Spacer(minLength: 44) }
                    if !own {
                        Button { if let friend { onPrivateChat(friend) } } label: { CharacterAvatar(data: friend?.avatarData, size: 38) }
                            .buttonStyle(.plain).disabled(friend == nil).accessibilityLabel("与\(message.speakerName)私聊")
                    }
                    VStack(alignment: own ? .trailing : .leading, spacing: 4) {
                        if !own { Text(message.speakerName).font(.caption).foregroundStyle(.secondary) }
                        Text(message.text).font(.system(size: bodySize * CGFloat(max(12, min(28, theme.textSize))) / 17, design: theme.textDesign)).textSelection(.enabled).padding(.horizontal, 16).padding(.vertical, 12)
                            .foregroundStyle(own ? theme.bubbleForeground : .primary)
                            .background(own ? theme.bubble : memberColor, in: RoundedRectangle(cornerRadius: theme.bubbleRadius))
                    }
                    if own { PersonalAvatar(size: 38) }
                    else { Spacer(minLength: 44) }
                }
            }
        }
    }
}

struct GroupConversationRow: View {
    let group: GroupChat
    let latest: GroupMessage?
    var unreadCount = 0
    @Environment(\.lumiTheme) private var theme
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.3").font(.system(size: 24, weight: .regular)).foregroundStyle(.secondary)
                .frame(width: 56, height: 56).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topTrailing) { UnreadBadge(count: unreadCount).offset(x: 4, y: -4) }
            VStack(alignment: .leading, spacing: 4) {
                ConversationRowTitle(name: group.name, date: group.lastMessageAt, pinned: group.pinnedAt != nil)
                Text(latest.map { $0.role == "system" ? $0.text : "\($0.speakerName)：\($0.text)" } ?? "\(group.memberIDs.count) 位好友 · \(group.scene)")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
}
