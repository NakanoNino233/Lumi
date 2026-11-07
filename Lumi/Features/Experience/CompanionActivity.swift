import SwiftUI
import SwiftData
import ActivityKit

@MainActor enum CompanionActivity {
    static func state(character: LumiCharacter, context: ModelContext, showMessage: Bool) throws -> LumiActivityAttributes.ContentState {
        let id = character.id
        let anniversaries = try context.fetch(FetchDescriptor<Anniversary>(predicate: #Predicate { $0.characterID == id }))
        let calendar = Calendar.current; let now = Date()
        let upcoming = anniversaries.compactMap { anniversary -> (String, Date)? in
            if !anniversary.repeatsYearly { return anniversary.date > now ? (anniversary.title, anniversary.date) : nil }
            let parts = calendar.dateComponents([.month, .day], from: anniversary.date)
            guard let next = calendar.nextDate(after: calendar.startOfDay(for: now).addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime) else { return nil }
            return (anniversary.title, next)
        }.sorted { $0.1 < $1.1 }.first
        let conversationIDs = Set(try context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == id })).map(\.id))
        let latest = showMessage ? try context.fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            .first { conversationIDs.contains($0.conversationID) && $0.role == "assistant" && $0.status == .complete }?.content ?? "" : ""
        return .init(stage: RelationshipEngine.stageText(character.stageIndex), affection: character.affection,
                     latest: String(latest.prefix(80)), anniversaryTitle: upcoming?.0 ?? "", anniversaryDate: upcoming?.1)
    }
    static func start(character: LumiCharacter, context: ModelContext, showMessage: Bool) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ActivityError.disabled }
        await end()
        _ = try Activity.request(attributes: LumiActivityAttributes(friend: character.name, characterID: character.id),
                                 content: ActivityContent(state: state(character: character, context: context, showMessage: showMessage), staleDate: Date().addingTimeInterval(3600)), pushType: nil)
    }
    static func update(character: LumiCharacter, context: ModelContext) async {
        guard let state = try? state(character: character, context: context, showMessage: AppPreferences.defaults.bool(forKey: "activity.showMessage")) else { return }
        for activity in Activity<LumiActivityAttributes>.activities where activity.attributes.characterID == character.id {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600)))
        }
    }
    static func end() async {
        for activity in Activity<LumiActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
enum ActivityError: LocalizedError {
    case disabled
    var errorDescription: String? { String(localized: "系统未允许实时活动，请在系统设置中检查，或继续在 App 内查看好友状态。", locale: AppLocale.current) }
}
struct CompanionActivityView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LumiCharacter.createdAt) private var characters: [LumiCharacter]
    @AppStorage("activity.showMessage", store: AppPreferences.defaults) private var showMessage = false
    @State private var selected: UUID?
    @State private var notice: String?
    @State private var busy = false
    var body: some View {
        Form {
            Section {
                Picker("好友", selection: $selected) { Text("选择好友").tag(Optional<UUID>.none); ForEach(characters) { Text($0.name).tag(Optional($0.id)) } }
                Toggle("在锁屏显示最近一句回复", isOn: $showMessage)
                    .onChange(of: showMessage) { _, _ in
                        Task { for character in characters { await CompanionActivity.update(character: character, context: context) } }
                    }
                Button("显示或刷新锁屏陪伴") {
                    guard let character = characters.first(where: { $0.id == selected }) else { return }
                    busy = true
                    Task {
                        do { try await CompanionActivity.start(character: character, context: context, showMessage: showMessage); notice = String(localized: "已请求显示锁屏陪伴。展示方式与持续时间由系统决定。", locale: AppLocale.current) }
                        catch { notice = error.localizedDescription }
                        busy = false
                    }
                }.disabled(busy || selected == nil)
                Button("结束锁屏陪伴") { Task { await CompanionActivity.end(); notice = String(localized: "锁屏陪伴已结束。", locale: AppLocale.current) } }
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("锁屏陪伴") } footer: { Text("显示所选好友的关系、好感度和下一个纪念日。最近回复默认隐藏。仅在 App 活跃时更新，无推送服务；离线时可能显示旧状态。") }
            Section("桌面小组件") {
                Text("长按主屏幕 → 添加小组件 → Lumi。此版本提供静态陪伴卡片，点击可打开 App。")
                Text("当前未配置共享容器，小组件不读取聊天或好友资料。实时好友小组件需在真机签名及共享能力验证后启用。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("锁屏与小组件").navigationBarTitleDisplayMode(.inline)
        .onAppear { if selected == nil { selected = characters.first?.id } }
    }
}
#Preview { NavigationStack { CompanionActivityView() }.modelContainer(for: LumiSchema.models, inMemory: true) }
