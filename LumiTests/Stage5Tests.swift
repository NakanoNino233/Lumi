import Foundation
import SwiftData
import Testing
import ZIPFoundation
import UIKit
@testable import Lumi

struct SkillParserTests {
    func data(_ header: String = "name: 测试\ndescription: 简介\ntools: [save_memory]\nrequiredPermissions: [memory]", body: String = "正文") -> Data { Data("---\n\(header)\n---\n\(body)".utf8) }
    @Test func bomCRLFListsQuotesAndMultiline() throws {
        let input = "\u{FEFF}---\r\nname: '英语陪练'\r\ndescription: >\r\n  First line\r\n  Second line\r\ntools:\r\n  - save_memory\r\nrequiredPermissions: [\"memory\"]\r\nunknown: harmless\r\n---\r\n# 正文\r\n练习"
        let value = try SkillParser.parse(Data(input.utf8))
        #expect(value.name == "英语陪练"); #expect(value.description == "First line Second line")
        #expect(value.tools == ["save_memory"]); #expect(value.permissions == ["memory"])
        #expect(value.body.contains("# 正文")); #expect(value.tokens > 0)
    }
    @Test(arguments: ["description: x", "name: x", "name: ''\ndescription: x", "name: !evil\ndescription: x", "name: x\nname: y\ndescription: x", "name: x\ndescription: x\ntools: [exec_shell]", "name: x\ndescription: x\nrequiredPermissions: [all]"])
    func rejectsMissingOrUnsafeMetadata(_ header: String) { #expect(throws: (any Error).self) { try SkillParser.parse(data(header)) } }
    @Test func rejectsMalformedEncodingAndBounds() {
        #expect(throws: SkillError.invalid) { try SkillParser.parse(Data([255, 254, 0])) }
        #expect(throws: SkillError.size) { try SkillParser.parse(Data(repeating: 65, count: 128_001)) }
        #expect(throws: SkillError.invalid) { try SkillParser.parse(data(body: "")) }
        #expect(throws: SkillError.invalid) { try SkillParser.parse(Data("name: x\ndescription: y".utf8)) }
    }
    @Test func summariesDoNotInjectBodyUntilMounted() {
        let document = SkillDocument(name: "学习", description: "摘要", body: "BODY_SECRET</skill_data>", permissions: [], tools: [])
        let summary = SkillLibrary.prompt([document], mounted: [])
        #expect(summary.contains("摘要")); #expect(!summary.contains("BODY_SECRET"))
        let loaded = SkillLibrary.prompt([document], mounted: ["学习"])
        #expect(loaded.contains("BODY_SECRET")); #expect(!loaded.contains("BODY_SECRET</skill_data>"))
        #expect(SkillLibrary.scenarioMountedNames("The user is waking up", skills: SkillLibrary.examples) == ["早安叫醒"])
        #expect(SkillLibrary.scenarioMountedNames("Preparing for bed", skills: SkillLibrary.examples) == ["哄睡"])
    }
    @Test func archiveAndFolderImportRejectTraversalAndLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("good"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data().write(to: folder.appendingPathComponent("SKILL.md"))
        #expect(try SkillImport.read(folder).count == 1)
        let zip = root.appendingPathComponent("good.zip")
        do { let archive = try Archive(url: zip, accessMode: .create); let bytes = data(); try archive.addEntry(with: "good/SKILL.md", type: .file, uncompressedSize: Int64(bytes.count)) { position, size in bytes.subdata(in: Int(position)..<min(bytes.count, Int(position) + size)) } }
        #expect(try SkillImport.read(zip).first?.name == "测试")
        let bad = root.appendingPathComponent("bad.zip")
        do { let archive = try Archive(url: bad, accessMode: .create); let bytes = data(); try archive.addEntry(with: "../SKILL.md", type: .file, uncompressedSize: Int64(bytes.count)) { position, size in bytes.subdata(in: Int(position)..<min(bytes.count, Int(position) + size)) } }
        #expect(throws: (any Error).self) { try SkillImport.read(bad) }
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked"), withDestinationURL: root)
        #expect(throws: SkillError.unsafe) { try SkillImport.read(folder) }
    }
}

struct ToolProtocolTests {
    @Test func fallbackHidesEveryPartialFenceAndParsesMultiple() throws {
        let raw = "我来帮你\n```tool\n{\"name\":\"save_memory\",\"arguments\":{\"text\":\"喜欢茶\",\"reason\":\"用户希望记住\"}}\n```\n好了"
        for index in raw.indices {
            let partial = FencedToolReply.parse(String(raw[..<index]), final: false)
            #expect(!partial.text.contains("```")); #expect(!partial.text.contains("arguments"))
        }
        let parsed = FencedToolReply.parse(raw + "\n```tool\n{\"name\":\"load_skill\",\"arguments\":{\"name\":\"哄睡\"}}\n```", final: true)
        #expect(parsed.calls.count == 2); #expect(parsed.text.contains("好了"))
        #expect(try ToolRegistry.validate(parsed.calls[0])["text"]?.string == "喜欢茶")
        #expect(FencedToolReply.parse("```tool\n{broken", final: true).calls.first?.name == "invalid_tool")
    }
    @Test func nativeFragmentsRetainIDsAndToolResultWireFormat() throws {
        var value = ToolCallAccumulator()
        _ = try value.consume(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"set_","arguments":"{\"title\":"}}]}}]}"#)
        _ = try value.consume(#"{"choices":[{"delta":{"content":"好","tool_calls":[{"index":0,"function":{"name":"reminder","arguments":"\"起床\"}"}}]}}]}"#)
        let calls = try value.finish(); #expect(calls.first?.id == "call_1"); #expect(calls.first?.name == "set_reminder")
        let turn = ChatTurn(role: "assistant", content: "", toolCalls: calls)
        #expect(try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn)) == turn)
        let result = ChatTurn(role: "tool", content: "done", toolCallID: "call_1")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        #expect(object["tool_call_id"] as? String == "call_1")
    }
    @Test func registryRejectsUnknownToolsAndParameterEscapes() {
        for call in [ToolCall(name: "exec_shell", arguments: "{}"), ToolCall(name: "save_memory", arguments: #"{"text":"x","reason":"x","path":"/private"}"#), ToolCall(name: "set_reminder", arguments: #"{"title":4,"date":"x","reason":"x"}"#)] {
            #expect(throws: ToolError.arguments) { try ToolRegistry.validate(call) }
        }
    }
    @MainActor @Test func reminderDateBoundsAndTimezone() throws {
        let now = Date(timeIntervalSince1970: 1_793_577_600)
        let future = ISO8601DateFormatter().string(from: now.addingTimeInterval(3600))
        #expect(try ToolExecutor.reminderDate(future, now: now) > now)
        for input in ["tomorrow 7", "2020-01-01T07:00:00Z", "2040-01-01T07:00:00Z", String(future.dropLast())] { #expect(throws: ToolError.date) { try ToolExecutor.reminderDate(input, now: now) } }
    }
    @Test func declarativeCardsRejectScriptsInvalidIDsAndDuplicateOptions() throws {
        let json = #"{"title":"计划","components":[{"id":"text","type":"text","text":"开始吧"},{"id":"p","type":"progress","text":"进度","progress":0.5}]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(try NativeCard.parse(value).components.count == 2)
        for raw in [json.replacingOccurrences(of: "\"text\":\"开始吧\"", with: "\"text\":\"开始吧\",\"script\":\"evil()\""), json.replacingOccurrences(of: "\"type\":\"text\"", with: "\"type\":\"webview\""), json.replacingOccurrences(of: "0.5", with: "99"), json.replacingOccurrences(of: "\"id\":\"p\"", with: "\"id\":\"text\"")] {
            #expect(throws: (any Error).self) { try NativeCard.parse(JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))) }
        }
    }
}

@MainActor struct PersonalizationTests {
    @Test func providerDefaultsAndLegacyUpgradePreserveCustomization() throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); let config = ProviderConfig(); context.insert(config)
        #expect(config.modelName == "deepseek-flash"); #expect(config.supportsTools && config.supportsVision)
        let editor = ProviderEditor(); #expect(editor.supportsTools && editor.supportsVision); editor.preset("DeepSeek"); #expect(editor.model == "deepseek-flash")
        config.modelName = "deepseek-chat"; config.supportsTools = false; config.supportsVision = false; config.defaultsVersion = nil
        try ProviderDefaults.upgrade(config, context: context); #expect(config.modelName == "deepseek-flash")
        config.modelName = "my-custom-model"; config.supportsVision = false; config.defaultsVersion = nil
        try ProviderDefaults.upgrade(config, context: context); #expect(config.modelName == "my-custom-model"); #expect(!config.supportsVision)
        let request = try LLMClient().request(endpoint: ProviderEndpoint(baseURL: "https://api.deepseek.com", model: ProviderDefaults.model), key: "fake-key", messages: [], streaming: false)
        #expect(String(decoding: request.httpBody!, as: UTF8.self).contains("disabled"))
    }
    @Test func providerTemplatesUseMatchingEndpointsAndClearPreviousKey() throws {
        let editor = ProviderEditor()
        for (name, baseURL, model) in [
            ("ChatGPT", "https://api.openai.com/v1", "gpt-6-luna"),
            ("Claude", "https://api.anthropic.com/v1", "claude-sonnet-5-5"),
            ("DeepSeek", "https://api.deepseek.com", ProviderDefaults.model)
        ] {
            editor.key = "previous-provider-secret"; editor.supportsTools = false; editor.supportsVision = false
            editor.preset(name)
            #expect(editor.template == name); #expect(editor.baseURL == baseURL); #expect(editor.model == model)
            #expect(editor.key.isEmpty); #expect(editor.supportsTools && editor.supportsVision)
            #expect(try editor.endpoint.completionURL().absoluteString == baseURL + "/chat/completions")
        }
        editor.name = "OpenRouter"; editor.baseURL = "https://openrouter.ai/api/v1"; editor.model = "saved-model"
        #expect(editor.template == "Custom")
        #expect(editor.name == "OpenRouter"); #expect(editor.model == "saved-model")
        editor.preset("Custom")
        #expect(editor.template == "Custom"); #expect(editor.baseURL.isEmpty); #expect(editor.model.isEmpty)
    }

    @Test func pinsSortAheadOfNewerMessagesAndPersist() throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container); let pinned = LumiCharacter(name: "旧好友"); let recent = LumiCharacter(name: "新好友")
        pinned.pinnedAt = Date(timeIntervalSince1970: 100)
        context.insert(pinned); context.insert(recent); try context.save()
        let rows = [ConversationSummary(friend: recent, last: nil, date: .now), ConversationSummary(friend: pinned, last: nil, date: .distantPast)].sorted(by: ConversationSummary.precedes)
        #expect(rows.first?.friend.id == pinned.id)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<LumiCharacter>()).first { $0.id == pinned.id })
        #expect(saved.pinnedAt == pinned.pinnedAt)
        pinned.pinnedAt = nil; #expect([rows[0], rows[1]].sorted(by: ConversationSummary.precedes).first?.friend.id == recent.id)
    }
    @Test func themeHexNormalizationAndBubbleContrast() {
        #expect(ThemeColor(hex: "#Ab12f0", fallback: 0).hex == "AB12F0")
        #expect(ThemeColor(hex: "invalid", fallback: 0x123456).hex == "123456")
        #expect(ThemeColor(hex: "FFFFFF", fallback: 0).luminance == 1)
        #expect(ThemeColor(hex: "000000", fallback: 0).luminance == 0)
        #expect(ThemeColor.hex(ThemeColor(hex: "DCCDF5", fallback: 0).color) == "DCCDF5")
        for hex in ["000000", "FFFFFF", "DCCDF5", "297563"] {
            let color = ThemeColor(hex: hex, fallback: 0)
            let foreground = color.luminance > 0.179 ? 0.0 : 1.0
            let ratio = (max(color.luminance, foreground) + 0.05) / (min(color.luminance, foreground) + 0.05)
            #expect(ratio >= 4.5)
            let light = color.accentColor(dark: false).luminance
            let dark = color.accentColor(dark: true).luminance
            #expect(1.05 / (light + 0.05) >= 4.5)
            #expect((dark + 0.05) / 0.08 >= 4.5)
        }
    }
    @Test func permissionScopeAndRevocation() throws {
        let suite = "app.lumi.permission-tests.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let first = ProviderEndpoint(baseURL: "https://example.com", model: "a"); let other = ProviderEndpoint(baseURL: "https://example.com", model: "b")
        #expect(!ToolPermissions.allowed(name: "save_memory", endpoint: first, defaults: defaults))
        ToolPermissions.grant(name: "save_memory", endpoint: first, defaults: defaults)
        #expect(ToolPermissions.allowed(name: "save_memory", endpoint: first, defaults: defaults)); #expect(!ToolPermissions.allowed(name: "save_memory", endpoint: other, defaults: defaults))
        ToolPermissions.revokeAll(defaults: defaults); #expect(!ToolPermissions.allowed(name: "save_memory", endpoint: first, defaults: defaults))
    }
}

final class ToolSequenceClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    let rounds: [[ToolStreamEvent]]
    let repeatLast: Bool
    private var captured: [[ChatTurn]] = []
    private var capturedEndpoints: [ProviderEndpoint] = []
    private var definitionNames: [[String]] = []
    init(_ rounds: [[ToolStreamEvent]], repeatLast: Bool = false) { self.rounds = rounds; self.repeatLast = repeatLast }
    var requests: [[ChatTurn]] { lock.withLock { captured } }
    var endpoints: [ProviderEndpoint] { lock.withLock { capturedEndpoints } }
    var definitions: [[String]] { lock.withLock { definitionNames } }
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.yield("普通回复"); $0.finish() } }
    func streamTools(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], definitions: [NativeToolDefinition]) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        let index = lock.withLock { let index = captured.count; captured.append(messages); capturedEndpoints.append(endpoint); definitionNames.append(definitions.map { $0.function.name }); return index }
        let events = rounds.indices.contains(index) ? rounds[index] : (repeatLast ? rounds.last ?? [] : [.text("我收到执行结果了。")])
        return AsyncThrowingStream { continuation in events.forEach { continuation.yield($0) }; continuation.finish() }
    }
}
@MainActor final class FakeToolActions: ToolSystemActions {
    var reminders: [(String, String, Date)] = []
    var sounds: [String] = []
    var fail = false
    func schedule(id: String, characterID: UUID, title: String, text: String, date: Date) async throws { if fail { throw ToolError.unavailable }; reminders.append((id, title, date)) }
    func weather() async throws -> String { if fail { throw ToolError.unavailable }; return "22°C" }
    func calendar() async throws -> String { if fail { throw ToolError.unavailable }; return "明天读书" }
    func sound(_ name: String) throws { sounds.append(name) }
}
@MainActor final class ToolHarness {
    let container: ModelContainer
    let context: ModelContext
    let provider: ProviderConfig
    let friend: LumiCharacter
    let keychain: KeychainStore
    let actions = FakeToolActions()
    let model: ChatModel
    init(client: ToolSequenceClient, native: Bool = true) throws {
        container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container); provider = ProviderConfig(baseURL: "https://example.com/\(UUID())"); provider.supportsTools = native
        friend = LumiCharacter(name: "工具测试", personaPrompt: "friendly")
        context.insert(provider); context.insert(friend)
        keychain = KeychainStore(service: "app.lumi.tools.tests.\(UUID())"); try keychain.save("fake-test-key", for: provider.id)
        model = ChatModel(client: client, keychain: keychain, automaticMaintenance: false, toolSystem: actions)
        model.configure(context: context, provider: provider, character: friend)
    }
    func cleanup() { model.stop(); for spec in ToolRegistry.specs { ToolPermissions.revoke(name: spec.name, endpoint: provider.endpoint) }; try? keychain.delete(for: provider.id) }
    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(5)) }
        Issue.record("Tool scenario timed out")
    }
    var pending: ToolActivity? { model.messages.flatMap(\.toolActivities).first { $0.status == "pending" } }
}

@Suite(.serialized) @MainActor struct ToolIntegrationTests {
    func reminderCall() -> ToolCall {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let date = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow)!
        return ToolCall(name: "set_reminder", arguments: JSONValue.object(["date": .string(ISO8601DateFormatter().string(from: date)), "title": .string("起床啦"), "reason": .string("你希望明早7点叫醒")]).encoded)
    }
    @Test(arguments: [true, false]) func morningReminderUsesSameApprovalAndExecutor(native: Bool) async throws {
        let call = reminderCall()
        let first: [ToolStreamEvent] = native ? [.call(call)] : [.text("我来设置。\n```to"), .text("ol\n" + JSONValue.object(["name": .string(call.name), "arguments": try JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))]).encoded + "\n```")]
        let client = ToolSequenceClient([first, [.text("已设置好本地提醒。")]])
        let h = try ToolHarness(client: client, native: native); defer { h.cleanup() }
        #expect(h.model.send("明早7点叫我起床"))
        try await h.wait { h.pending != nil }
        #expect(h.actions.reminders.isEmpty)
        let pending = try #require(h.pending); #expect(pending.name == "set_reminder"); #expect(!h.model.messages.last!.content.contains("```"))
        h.model.approveTool(pending.id, choice: .once)
        try await h.wait { !h.model.isGenerating }
        #expect(h.actions.reminders.count == 1)
        #expect(h.model.messages.last?.status == .complete)
        let toolReply = try #require(h.model.messages.first { $0.toolActivities.contains { $0.id == pending.id } })
        #expect(toolReply.toolActivities.first?.status == "success")
        #expect(h.model.messages.filter { $0.role == "assistant" }.allSatisfy { $0.status == .complete })
        #expect(client.requests.count == 2)
        #expect(client.endpoints.allSatisfy { $0.tokenOwners.count == 1 && $0.tokenOwners.first?.id == h.friend.id })
        #expect(client.definitions.first?.isEmpty == !native)
        #expect(client.requests.last!.contains { $0.role == (native ? "tool" : "user") && $0.content.contains("success") })
        let saved = try #require(ModelContext(h.container).fetch(FetchDescriptor<Message>()).first { $0.id == toolReply.id })
        #expect(saved.toolActivities.first?.status == "success")
        #expect(!ToolPermissions.allowed(name: call.name, endpoint: h.provider.endpoint))
    }
    @Test func refusalReturnsDeniedToModelWithoutWriting() async throws {
        let call = ToolCall(name: "save_memory", arguments: #"{"text":"喜欢喝茶","reason":"你想让我记住"}"#)
        let client = ToolSequenceClient([[.call(call)], [.text("好的，这次我不会保存。")]])
        let h = try ToolHarness(client: client); defer { h.cleanup() }
        h.model.send("先不要记住我的偏好"); try await h.wait { h.pending != nil }
        h.model.approveTool(try #require(h.pending).id, choice: .deny)
        try await h.wait { !h.model.isGenerating }
        #expect(try h.context.fetch(FetchDescriptor<MemoryFact>()).isEmpty)
        #expect(h.model.messages.last?.toolActivities.first?.status == "denied")
        #expect(client.requests.last?.last?.content.contains("denied") == true)
        #expect(h.model.messages.last?.content.contains("不会保存") == true)
    }
    @Test func alwaysAllowCanBeRevokedAndCancellationCannotExecute() async throws {
        let call = ToolCall(name: "save_memory", arguments: #"{"text":"喜欢散步","reason":"用户请求保存"}"#)
        let client = ToolSequenceClient([[.call(call)], [.text("记住了")], [.call(call)], [.text("没有重复保存")], [.call(call)]])
        let h = try ToolHarness(client: client); defer { h.cleanup() }
        h.model.send("请记住我喜欢散步"); try await h.wait { h.pending != nil }
        h.model.approveTool(try #require(h.pending).id, choice: .always)
        try await h.wait { !h.model.isGenerating }
        #expect(ToolPermissions.allowed(name: "save_memory", endpoint: h.provider.endpoint))
        h.model.send("再保存一次"); try await h.wait { !h.model.isGenerating }
        #expect(try h.context.fetch(FetchDescriptor<MemoryFact>()).count == 1)
        ToolPermissions.revoke(name: "save_memory", endpoint: h.provider.endpoint)
        h.model.send("撤销后应该再问"); try await h.wait { h.pending != nil }
        let id = try #require(h.pending).id; h.model.stop(); h.model.approveTool(id, choice: .always)
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.model.messages.last?.status == .interrupted)
        #expect(h.model.messages.last?.toolActivities.first?.status == "cancelled")
        #expect(!ToolPermissions.allowed(name: "save_memory", endpoint: h.provider.endpoint))
    }
    @Test func repeatedToolsStopAtConfiguredLimit() async throws {
        let call = ToolCall(name: "load_skill", arguments: #"{"name":"英语陪练"}"#)
        let client = ToolSequenceClient([[.call(call)]], repeatLast: true)
        let h = try ToolHarness(client: client); defer { h.cleanup() }
        try SkillLibrary.install(SkillLibrary.examples, in: h.context)
        h.model.send("继续练习"); try await h.wait { !h.model.isGenerating }
        #expect(h.model.messages.last?.toolActivities.count == ToolRegistry.maximumCalls)
        #expect(h.model.messages.last?.content.contains("上限") == true)
        #expect(client.requests.count == ToolRegistry.maximumCalls + 1)
        #expect(client.definitions.last?.isEmpty == true)
    }
    @Test func systemFailureAndUnknownToolReturnErrorsInsteadOfCrashing() async throws {
        let call = reminderCall()
        let client = ToolSequenceClient([[.call(call)], [.call(ToolCall(name: "delete_all_files", arguments: "{}"))], [.text("设置失败了，我们稍后重试。")]])
        let h = try ToolHarness(client: client); h.actions.fail = true; defer { h.cleanup() }
        h.model.send("设置提醒"); try await h.wait { h.pending != nil }
        h.model.approveTool(try #require(h.pending).id, choice: .once)
        try await h.wait { !h.model.isGenerating }
        #expect(h.model.messages.last?.status == .complete)
        #expect(h.model.messages.last?.toolActivities.map(\.status) == ["failed", "failed"])
        #expect(h.actions.reminders.isEmpty)
        #expect(client.requests.last!.filter { $0.role == "tool" && $0.content.contains("error") }.count == 2)
    }
    @Test func mountedSkillsPersistAndDisabledSkillCannotLoad() async throws {
        let call = ToolCall(name: "load_skill", arguments: #"{"name":"英语陪练"}"#)
        let client = ToolSequenceClient([[.text("开始练习")], [.call(call)], [.text("该技能已关闭")]])
        let h = try ToolHarness(client: client); defer { h.cleanup() }
        try SkillLibrary.install(SkillLibrary.examples, in: h.context)
        let skill = try #require(h.context.fetch(FetchDescriptor<InstalledSkill>()).first { $0.name == "英语陪练" })
        h.model.send("开始英语", mountedSkills: [skill.id]); try await h.wait { !h.model.isGenerating }
        #expect(client.requests.first?.contains { $0.role == "system" && $0.content.contains(skill.instructions) } == true)
        let user = try #require(h.model.messages.first { $0.role == "user" })
        let saved = try #require(ModelContext(h.container).fetch(FetchDescriptor<Message>()).first { $0.id == user.id })
        #expect(saved.mountedSkillIDs == [skill.id])
        skill.enabled = false; try h.context.save()
        h.model.send("再加载英语"); try await h.wait { !h.model.isGenerating }
        #expect(h.model.messages.last?.toolActivities.first?.status == "failed")
        #expect(!client.requests[1].contains { $0.role == "system" && $0.content.contains(skill.instructions) })
    }
}
