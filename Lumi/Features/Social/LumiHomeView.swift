import SwiftUI
import SwiftData

enum HomeRoute: Hashable { case friend(UUID), group(UUID) }

struct CharacterHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    let provider: ProviderConfig
    @Environment(\.modelContext) private var context
    @Query(sort: \LumiCharacter.createdAt) private var characters: [LumiCharacter]
    @Query private var groups: [GroupChat]
    @AppStorage("selectedCharacter", store: AppPreferences.defaults) private var selectedID = ""
    @State private var tab = 0
    @State private var path: [HomeRoute] = []
    @State private var adding = false
    @State private var creatingGroup = false
    @State private var error: String?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                ConversationListView(onOpen: open, onOpenGroup: openGroup)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("发起群聊", systemImage: "person.2.badge.plus") { creatingGroup = true }.accessibilityIdentifier("home.group")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                        Button("添加好友", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("home.add")
                    } }
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .friend(let id):
                        if let friend = characters.first(where: { $0.id == id }) {
                            ChatView(provider: provider, character: friend)
                                .toolbar(.hidden, for: .tabBar)
                        } else { ContentUnavailableView("好友已移除", systemImage: "person.crop.circle.badge.xmark") }
                        case .group(let id):
                            if let group = groups.first(where: { $0.id == id }) {
                                GroupChatView(group: group, provider: provider, onPrivateChat: open, onDelete: { path = [] }).toolbar(.hidden, for: .tabBar)
                            } else { ContentUnavailableView("群聊已移除", systemImage: "person.3") }
                        }
                    }
            }.tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            NavigationStack {
                CharacterLibraryView(provider: provider, showsDone: false, onSelect: open)
            }.tabItem { Label("列表", systemImage: "person.2") }.tag(1)
            NavigationStack { MomentsView() }
                .tabItem { Label("朋友圈", systemImage: "camera.aperture") }.tag(2)
            NavigationStack { MyProfileView(provider: provider) }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(3)
        }
        .modifier(LumiFeedback(trigger: tab))
        .sheet(isPresented: $adding) { NavigationStack { AddFriendView(provider: provider) { friend in adding = false; open(friend) } } }
        .sheet(isPresented: $creatingGroup) { NavigationStack { GroupEditorView { group in creatingGroup = false; openGroup(group) } } }
        .task {
            do {
                try CharacterLibrary.seed(in: context); try MemeStore.seed(in: context); try SkillLibrary.seed(in: context)
                if AppPreferences.isUITesting, CommandLine.arguments.contains("-lumiUITestsMoments"),
                   try context.fetchCount(FetchDescriptor<MomentPost>()) == 0,
                   let friend = try context.fetch(FetchDescriptor<LumiCharacter>()).first(where: { $0.name == "大肥鱼" }) {
                    let post = MomentPost(content: "摸鱼回来了", authorID: friend.id, authorName: friend.name)
                    post.comments = [MomentComment(text: "欢迎回来", authorName: "我")]
                    context.insert(post); try context.save()
                    AppPreferences.defaults.set(friend.avatarData, forKey: MomentsPreferences.coverKey)
                }
            }
            catch { self.error = LLMError.storage.localizedDescription }
            consumeRoute()
            ProactiveService.shared?.launchRefresh(foreground: true)
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await MomentsService.shared?.run() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lumiWillRestore)) { _ in MomentsService.shared?.pause(); ChatSessions.shared.reset(); path = [] }
        .onChange(of: groups.map(\.id)) { _, ids in
            path.removeAll { route in
                if case .group(let id) = route { return !ids.contains(id) }
                return false
            }
        }
        .onChange(of: ConversationRouter.shared.revision) { _, _ in consumeRoute() }
        .onChange(of: selectedID) { _, _ in
            if CompanionPreferences.current.characterID.isEmpty { Task { await ProactiveService.shared?.settingsChanged() } }
        }
        .alert("无法完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("重试") { Task { do { try CharacterLibrary.seed(in: context); try MemeStore.seed(in: context) } catch { self.error = LLMError.storage.localizedDescription } } }
        } message: { Text(error ?? "") }
    }
    private func open(_ friend: LumiCharacter) {
        selectedID = friend.id.uuidString; tab = 0; path = [.friend(friend.id)]
    }
    private func openGroup(_ group: GroupChat) { tab = 0; path = [.group(group.id)] }
    private func consumeRoute() {
        if let id = ConversationRouter.shared.pendingGroupID {
            ConversationRouter.shared.pendingGroupID = nil; tab = 0; path = [.group(id)]; return
        }
        guard let id = ConversationRouter.shared.pendingCharacterID else { return }
        ConversationRouter.shared.pendingCharacterID = nil
        selectedID = id.uuidString; tab = 0; path = [.friend(id)]
    }
}

struct ConversationListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.lumiTheme) private var theme
    @State private var pinError = false
    var onOpen: (LumiCharacter) -> Void
    var onOpenGroup: (GroupChat) -> Void
    @Query(sort: \LumiCharacter.createdAt) private var friends: [LumiCharacter]
    @Query(sort: \Conversation.lastMessageAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Message.createdAt, order: .reverse) private var messages: [Message]
    @Query private var groups: [GroupChat]
    @Query(sort: \GroupMessage.createdAt, order: .reverse) private var groupMessages: [GroupMessage]
    @State private var search = ""
    private var rows: [ConversationSummary] {
        let latest = Dictionary(messages.map { ($0.conversationID, $0) }, uniquingKeysWith: { first, _ in first })
        let byFriend = Dictionary(conversations.map { ($0.characterID, $0) }, uniquingKeysWith: { first, _ in first })
        return friends.filter { search.isEmpty || $0.name.localizedStandardContains(search) }.map { friend in
            let conversation = byFriend[friend.id]
            return ConversationSummary(friend: friend, last: conversation.flatMap { latest[$0.id] }, date: conversation?.lastMessageAt ?? friend.createdAt, unreadCount: messages.filter { $0.conversationID == conversation?.id && $0.role == "assistant" && $0.status == .complete && $0.createdAt > ChatReadState.shared.lastRead(friend.id) }.count)
        }.sorted(by: ConversationSummary.precedes)
    }
    private var entries: [HomeConversation] {
        let last = Dictionary(groupMessages.map { ($0.groupID, $0) }, uniquingKeysWith: { first, _ in first })
        let groupRows = groups.filter { search.isEmpty || $0.name.localizedStandardContains(search) }.map { HomeConversation(group: $0, latest: last[$0.id], unreadCount: unreadCount(for: $0)) }
        return (rows.map { HomeConversation(friend: $0) } + groupRows).sorted(by: HomeConversation.precedes)
    }
    var body: some View {
        List {
            ForEach(entries) { entry in
                HomeConversationRow(entry: entry, onOpen: onOpen, onOpenGroup: onOpenGroup)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.visible).listRowBackground(entry.pinnedAt == nil ? Color(uiColor: .systemBackground) : Color(uiColor: .secondarySystemBackground))
                    .swipeActions(edge: .leading) {
                        Button { togglePin(entry) } label: { Label(entry.pinnedAt == nil ? "置顶" : "取消置顶", systemImage: entry.pinnedAt == nil ? "pin" : "pin.slash") }.tint(theme.accent)
                    }
                    .contextMenu {
                        Button { togglePin(entry) } label: { Label(entry.pinnedAt == nil ? "置顶聊天" : "取消置顶", systemImage: entry.pinnedAt == nil ? "pin" : "pin.slash") }
                    }
            }
            if entries.isEmpty { ContentUnavailableView("还没有聊天", systemImage: "bubble.left", description: Text("添加一位好友，开始你们的故事。")) }
        }
        .listStyle(.plain).searchable(text: $search, prompt: "搜索好友或群聊")
        .navigationTitle("聊天").navigationBarTitleDisplayMode(.inline)
        .alert("置顶保存失败", isPresented: $pinError) { Button("好", role: .cancel) {} } message: { Text("请检查设备空间后重试。") }
        .safeAreaInset(edge: .bottom) {
            Text("聊天记录保存在本机").font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(12).frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemBackground))
        }
    }
    private func unreadCount(for group: GroupChat) -> Int {
        let read = ChatReadState.shared.lastRead(group.id)
        return groupMessages.filter { $0.groupID == group.id && $0.role == "assistant" && $0.createdAt > read }.count
    }
    private func togglePin(_ entry: HomeConversation) {
        let old = entry.pinnedAt
        entry.setPin(old == nil ? .now : nil)
        do { try context.save() } catch { entry.setPin(old); pinError = true }
    }
}

struct ConversationSummary: Identifiable {
    var id: UUID { friend.id }
    let friend: LumiCharacter
    let last: Message?
    let date: Date
    var unreadCount = 0
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if let left = lhs.friend.pinnedAt, let right = rhs.friend.pinnedAt, left != right { return left > right }
        if (lhs.friend.pinnedAt != nil) != (rhs.friend.pinnedAt != nil) { return lhs.friend.pinnedAt != nil }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct ConversationSummaryRow: View {
    let row: ConversationSummary
    var body: some View {
        HStack(spacing: 16) {
            CharacterAvatar(data: row.friend.avatarData, size: 56).overlay(alignment: .topTrailing) { UnreadBadge(count: row.unreadCount).offset(x: 4, y: -4) }
            VStack(alignment: .leading, spacing: 4) {
                ConversationRowTitle(name: row.friend.name, date: row.date, pinned: row.friend.pinnedAt != nil)
                Text(row.last?.content.isEmpty == false ? row.last!.content : (row.last?.attachments.isEmpty == false ? String(localized: "[附件]", locale: AppLocale.current) : row.friend.firstGreeting))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 12).contentShape(Rectangle())
    }
}

struct ConversationRowTitle: View {
    let name: String
    let date: Date
    let pinned: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            HStack(spacing: 8) {
                Text(name).font(.body.weight(.medium)).lineLimit(1)
                if pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("已置顶") }
            }.layoutPriority(1)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(date, format: calendar.isDateInToday(date) ? .dateTime.hour().minute() : .dateTime.month().day())
                .font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                .accessibilityLabel(Text(date, format: .dateTime.year().month().day().hour().minute()))
        }
    }
}

struct MyProfileView: View {
    let provider: ProviderConfig
    @AppStorage(PersonalProfile.storageKey, store: AppPreferences.defaults) private var profileData = Data()
    @State private var profile = PersonalProfile()
    var body: some View {
        List {
            Section {
                NavigationLink { PersonalProfileEditor(profile: profile) } label: {
                    HStack(spacing: 16) {
                        PersonalAvatar(size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.displayName).font(.system(.title2, design: .rounded).weight(.medium)).foregroundStyle(.primary)
                            Text("编辑个人资料").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 16)
                }.accessibilityIdentifier("profile.edit")
                if let birthday = profile.birthday?.date {
                    LabeledContent("生日") { Text(birthday, format: .dateTime.year().month().day()) }
                }
                if let zodiac = profile.zodiac {
                    LabeledContent("星座") { Text(zodiac.title) }.accessibilityIdentifier("profile.summary.zodiac")
                }
            }
            Section {
                NavigationLink { ProactiveSettingsView() } label: { Label("主动问候与情境", systemImage: "bell.badge") }
                NavigationLink { MemeLibraryView() } label: { Label("表情图库", systemImage: "face.smiling") }.accessibilityIdentifier("profile.memes")
                NavigationLink { AppSettingsView(provider: provider, showsDone: false) } label: { Label("设置", systemImage: "gearshape") }.accessibilityIdentifier("profile.settings")
                NavigationLink { PrivacyView() } label: { Label("隐私说明", systemImage: "lock.shield") }
            }
        }.labelStyle(ProfileLabelStyle()).navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
            .task(id: profileData) { profile = PersonalProfile.decode(profileData) }
    }
}

private struct ProfileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.font(.system(size: 20, weight: .regular)).foregroundStyle(.secondary).frame(width: 24)
            configuration.title
        }.padding(.vertical, 4)
    }
}

#Preview("Home") {
    CharacterHomeView(provider: ProviderConfig())
        .modelContainer(for: LumiSchema.models, inMemory: true).tint(.lumiAccent)
}
