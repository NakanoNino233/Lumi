import AppIntents
import Foundation
import SwiftData

struct CompanionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "角色"
    static let defaultQuery = CompanionQuery()
    var id: UUID
    @Property(title: "名字") var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(id: UUID, name: String) { self.id = id; self.name = name }
}
struct CompanionQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [CompanionEntity] {
        try await MainActor.run { try Self.load().filter { identifiers.contains($0.id) } }
    }
    func suggestedEntities() async throws -> [CompanionEntity] { try await MainActor.run { Array(try Self.load().prefix(30)) } }
    func entities(matching string: String) async throws -> [CompanionEntity] {
        try await MainActor.run { try Self.load().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    }
    @MainActor private static func load() throws -> [CompanionEntity] {
        guard let context = CompanionRuntime.container?.mainContext else { throw CompanionIntentError.unavailable }
        return try context.fetch(FetchDescriptor<LumiCharacter>(sortBy: [SortDescriptor(\.createdAt)])).map { CompanionEntity(id: $0.id, name: $0.name) }
    }
}

enum CompanionScenario: String, AppEnum {
    case home = "home", charging = "charging", waking = "waking", goodnight = "goodnight", custom = "custom"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "场景"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .home: "到家", .charging: "充电", .waking: "起床", .goodnight: "晚安", .custom: "自定义"
    ]
    var prompt: String {
        switch self {
        case .home: "The user has arrived home. Give a warm welcome."
        case .charging: "The user connected their phone to a charger. Give a gentle greeting."
        case .waking: "The user is waking up. Give a morning greeting."
        case .goodnight: "The user is preparing for bed. Say goodnight."
        case .custom: "Use the custom scenario supplied by the user."
        }
    }
}
enum CompanionIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable, configure, failed, customScenario
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "请先打开 Lumi 并创建角色。"
        case .configure: "请先打开 Lumi，在设置中保存 API Key。"
        case .failed: "暂时无法获取回复。消息已保存在 Lumi，请稍后重试。"
        case .customScenario: "请填写自定义场景描述。"
        }
    }
}
private enum IntentBridge {
    @MainActor static func run(character: CompanionEntity, text: String, scenario: String?, notify: Bool, operationID: UUID) async throws -> String {
        guard let service = ProactiveService.shared else { throw CompanionIntentError.unavailable }
        do { return try await service.respond(characterID: character.id, text: text, scenario: scenario, token: "intent:" + operationID.uuidString, notify: notify) }
        catch LLMError.missingKey { throw CompanionIntentError.configure }
        catch { throw CompanionIntentError.failed }
    }
}
struct CharacterSpeakIntent: AppIntent {
    static let title: LocalizedStringResource = "让角色说话"
    static let description = IntentDescription("根据到家、充电、起床、晚安或自定义情境生成一句问候，并发出本地通知。")
    @Parameter(title: "角色") var character: CompanionEntity
    @Parameter(title: "场景") var scenario: CompanionScenario
    @Parameter(title: "自定义场景", default: "") var custom: String
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("让 \(\.$character) 在 \(\.$scenario) 时说话") { \.$custom } }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let detail = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if scenario == .custom && detail.isEmpty { throw CompanionIntentError.customScenario }
        let prompt = scenario.prompt + (scenario == .custom ? "\n" + String(detail.prefix(1000)) : "")
        let output = try await IntentBridge.run(character: character, text: prompt, scenario: prompt, notify: true, operationID: operationID)
        return .result(value: output)
    }
}
struct SayToCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "对角色说一句话"
    static let description = IntentDescription("将一句话保存到角色聊天，并通过本地通知收到回复。")
    @Parameter(title: "角色") var character: CompanionEntity
    @Parameter(title: "内容") var message: String
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("对 \(\.$character) 说 \(\.$message)") }
    func perform() async throws -> some IntentResult {
        _ = try await IntentBridge.run(character: character, text: message, scenario: nil, notify: true, operationID: operationID)
        return .result()
    }
}
struct MessageCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "给角色发送一条消息并获取回复"
    static let description = IntentDescription("返回角色回复的文字，可交给朗读、显示或其他快捷指令动作。")
    @Parameter(title: "角色") var character: CompanionEntity
    @Parameter(title: "内容") var message: String
    @Parameter(title: "同时发送通知", default: false) var notify: Bool
    private var operationID = UUID()
    static var parameterSummary: some ParameterSummary { Summary("给 \(\.$character) 发送 \(\.$message) 并获取回复") { \.$notify } }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let output = try await IntentBridge.run(character: character, text: message, scenario: nil, notify: notify, operationID: operationID)
        return .result(value: output)
    }
}
struct LumiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CharacterSpeakIntent(), phrases: ["用 \(.applicationName) 让角色说话"], shortTitle: "让角色说话", systemImageName: "sparkles")
        AppShortcut(intent: SayToCharacterIntent(), phrases: ["用 \(.applicationName) 对角色说句话"], shortTitle: "对角色说一句话", systemImageName: "bubble.left")
        AppShortcut(intent: MessageCharacterIntent(), phrases: ["用 \(.applicationName) 获取角色回复"], shortTitle: "获取角色回复", systemImageName: "bubble.left.and.bubble.right")
    }
}
