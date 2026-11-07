import Foundation
import Testing
import SwiftData
@testable import Lumi

struct SSEParserTests {
    @Test func normalAndDone() throws {
        var parser = SSEParser()
        #expect(try parser.append(Data("data: hello\n\ndata: [DONE]\n\ndata: ignored\n\n".utf8)) == ["hello"])
        #expect(parser.isDone)
    }
    @Test func everyUTF8SplitBoundary() throws {
        let data = Data("data: {\"choices\":[{\"delta\":{\"content\":\"你好🌻\"}}]}\r\n\r\ndata: [DONE]\r\n\r\n".utf8)
        for boundary in 0...data.count {
            var parser = SSEParser()
            let events = try parser.append(data.prefix(boundary)) + parser.append(data.suffix(data.count - boundary)) + parser.finish()
            #expect(events.count == 1)
            #expect(try CompletionDecoder.content(from: events[0]) == "你好🌻")
            #expect(parser.isDone)
        }
    }
    @Test func byteAtATimeAndHeartbeats() throws {
        var parser = SSEParser(); var events: [String] = []
        for byte in Data(": heartbeat\n\nid: 5\nevent: message\ndata: a\ndata: b\n\n".utf8) {
            events += try parser.append(Data([byte]))
        }
        #expect(events == ["a\nb"])
    }
    @Test func newlineVariantsAndEOF() throws {
        for separator in ["\n", "\r", "\r\n"] {
            var parser = SSEParser()
            let events = try parser.append(Data("data:first\(separator)\(separator)data: second".utf8)) + parser.finish()
            #expect(events == ["first", "second"])
        }
    }
    @Test func preservesWhitespaceAndEmptyData() throws {
        var parser = SSEParser()
        #expect(try parser.append(Data("data:  padded \ndata:\n\n".utf8)) == [" padded \n"])
    }
    @Test func ignoresNonJSON() throws {
        #expect(try CompletionDecoder.content(from: "heartbeat") == nil)
    }
    @Test func malformedJSONIsVisibleError() {
        #expect(throws: LLMError.invalidResponse) { try CompletionDecoder.content(from: "{broken") }
    }
    @Test func reasoningIsNeverDisplayed() throws {
        #expect(try CompletionDecoder.content(from: #"{"choices":[{"delta":{"reasoning_content":"private reasoning"}}]}"#) == nil)
        #expect(try CompletionDecoder.content(from: #"{"choices":[{"delta":{"reasoning_content":"private","content":"answer"}}]}"#) == "answer")
        #expect(try CompletionDecoder.content(from: #"{"choices":[],"usage":{"total_tokens":10}}"#) == nil)
    }
    @Test func rejectsInvalidUTF8() {
        var parser = SSEParser()
        #expect(throws: LLMError.invalidResponse) { try parser.append(Data([100,97,116,97,58,32,255,10])) }
    }
    @Test func rejectsOversizedEvent() {
        var parser = SSEParser()
        #expect(throws: LLMError.responseTooLarge) { try parser.append(Data(repeating: 65, count: SSEParser.maximumEventBytes + 1)) }
    }
}

struct EndpointTests {
    @Test(arguments: [
        ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions"),
        ("https://api.example.com/v1/", "https://api.example.com/v1/chat/completions"),
        ("https://api.example.com/v1/chat/completions", "https://api.example.com/v1/chat/completions")
    ]) func buildsEndpoint(input: (String, String)) throws {
        #expect(try ProviderEndpoint(baseURL: input.0, model: "model").completionURL().absoluteString == input.1)
    }
    @Test(arguments: ["http://api.example.com", "https://user:secret@api.example.com", "https://api.example.com?key=secret", "https://api.example.com#secret", "not a url", "https://"])
    func rejectsUnsafeURL(_ url: String) {
        #expect(throws: LLMError.invalidConfiguration) { try ProviderEndpoint(baseURL: url, model: "model").completionURL() }
    }
    @Test func modelRequired() {
        #expect(throws: LLMError.invalidConfiguration) { try ProviderEndpoint(baseURL: "https://example.com", model: " ").completionURL() }
    }
    @Test func providerRequestFormatsCoverConnectionStreamingAndTools() throws {
        let client = LLMClient(usageRecorder: TokenUsageRecorder(disabled: true))
        for (baseURL, model, openAI) in [
            ("https://api.openai.com/v1", "gpt-6-luna", true),
            ("https://api.anthropic.com/v1", "claude-sonnet-5-5", false),
            ("https://api.deepseek.com", ProviderDefaults.model, false),
            ("https://api.example.com/v1", "custom-model", false)
        ] {
            let endpoint = ProviderEndpoint(baseURL: baseURL, model: model)
            for mode in 0..<4 {
                let request = try client.request(endpoint: endpoint, key: "fake-key", messages: [ChatTurn(role: "user", content: "Hello")], streaming: mode != 0, limit: 32, memeTool: mode == 2, definitions: mode == 3 ? [ToolRegistry.spec("save_memory")!.definition] : nil)
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(body[openAI ? "max_completion_tokens" : "max_tokens"] as? Int == 32)
                #expect(body[openAI ? "max_tokens" : "max_completion_tokens"] == nil)
                #expect(body["reasoning_effort"] as? String == (openAI ? "none" : nil))
                #expect((body["thinking"] != nil) == (model == ProviderDefaults.model))
                #expect((body["stream_options"] != nil) == (mode != 0))
                let tools = body["tools"] as? [[String: Any]]
                #expect(tools?.count == (mode >= 2 ? 1 : nil))
                if mode >= 2 {
                    #expect((tools?.first?["function"] as? [String: Any])?["name"] as? String == (mode == 2 ? "send_meme" : "save_memory"))
                }
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-key")
            }
        }
    }

    @Test func credentialOnlyInHeader() throws {
        let request = try LLMClient().request(endpoint: ProviderEndpoint(baseURL: "https://example.com/v1", model: "model"), key: "test-secret-marker", messages: [ChatTurn(role: "user", content: "hello")], streaming: true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret-marker")
        #expect(!String(decoding: request.httpBody!, as: UTF8.self).contains("test-secret-marker"))
        #expect(!request.url!.absoluteString.contains("test-secret-marker"))
    }
    @Test(arguments: [(401, LLMError.unauthorized), (402, .balance), (429, .rateLimited), (404, .modelMissing), (503, .server)])
    func statusMapping(value: (Int, LLMError)) { #expect(LLMError.http(value.0) == value.1) }
    @Test func sanitizesSensitiveErrors() {
        let error = NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bearer secret"])
        #expect(LLMError.sanitized(error) == .network)
        #expect(!LLMError.sanitized(error).localizedDescription.contains("secret"))
        #expect(LLMError.sanitized(URLError(.timedOut)) == .timeout)
        #expect(LLMError.sanitized(URLError(.notConnectedToInternet)) == .offline)
    }
}

struct KeychainTests {
    @Test func CRUD() throws {
        let store = KeychainStore(service: "app.lumi.tests.\(UUID().uuidString)")
        let id = UUID(); let other = UUID()
        defer { try? store.delete(for: id); try? store.delete(for: other) }
        #expect(try store.read(for: id) == nil)
        try store.save("first-test-secret", for: id)
        #expect(try store.read(for: id) == "first-test-secret")
        #expect(try store.read(for: other) == nil)
        try store.save("updated-test-secret", for: id)
        #expect(try store.read(for: id) == "updated-test-secret")
        try store.delete(for: id)
        #expect(try store.read(for: id) == nil)
        try store.delete(for: id)
    }
}

final class GateClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    private var requests: [[ChatTurn]] = []
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { requests.append(messages); continuations.append(continuation) }
        }
    }
    var count: Int { lock.withLock { requests.count } }
    func request(_ index: Int) -> [ChatTurn] { lock.withLock { requests[index] } }
    func yield(_ text: String, index: Int) { lock.withLock { continuations[index] }.yield(text) }
    func finish(_ index: Int) { lock.withLock { continuations[index] }.finish() }
}

@MainActor struct ChatModelTests {
    private func setup() throws -> (ModelContainer, ModelContext, ChatModel, GateClient, ProviderConfig, KeychainStore) {
        let schema = LumiSchema.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let provider = ProviderConfig(); context.insert(provider)
        let keychain = KeychainStore(service: "app.lumi.chat-tests.\(UUID())")
        try keychain.save("fake-local-test-key", for: provider.id)
        let client = GateClient()
        let model = ChatModel(client: client, keychain: keychain, automaticMaintenance: false)
        model.configure(context: context, provider: provider)
        return (container, context, model, client, provider, keychain)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Timed out waiting for local chat state")
    }
    @Test func queueExcludesFutureMessagesAndDrains() async throws {
        let (container, context, model, client, provider, keychain) = try setup()
        defer { model.stop(); try? keychain.delete(for: provider.id); withExtendedLifetime(container) {} }
        model.send("first"); try await waitFor { client.count == 1 }
        model.send("second")
        #expect(model.queuedIDs.count == 1)
        #expect(!client.request(0).contains { $0.content == "second" })
        client.yield("reply one", index: 0); client.finish(0)
        try await waitFor { client.count == 2 }
        #expect(client.request(1).contains { $0.content == "second" })
        #expect(client.request(1).contains { $0.content == "reply one" })
        client.yield("reply two", index: 1); client.finish(1)
        try await waitFor { !model.isGenerating }
        #expect(model.queuedIDs.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Message>()).count == 4)
    }
    @Test func stopRejectsLateChunksAndImmediateSendRestarts() async throws {
        let (container, _, model, client, provider, keychain) = try setup()
        defer { model.stop(); try? keychain.delete(for: provider.id); withExtendedLifetime(container) {} }
        model.send("first"); try await waitFor { client.count == 1 }
        client.yield("partial", index: 0)
        try await waitFor { model.messages.contains { $0.content == "partial" } }
        model.send("second"); let queued = try #require(model.queuedIDs.first)
        model.sendImmediately(queued)
        try await waitFor { client.count == 2 }
        client.yield(" stale", index: 0); client.finish(0)
        client.yield("new reply", index: 1); client.finish(1)
        try await waitFor { !model.isGenerating }
        #expect(!model.messages.contains { $0.content.contains("stale") })
        #expect(model.messages.contains { $0.content == "partial" && $0.status == .interrupted })
        #expect(model.messages.contains { $0.content == "new reply" && $0.status == .complete })
    }
    @Test func recoveredQueueRequiresExplicitRetry() throws {
        let (container, context, model, _, provider, keychain) = try setup()
        defer { try? keychain.delete(for: provider.id); withExtendedLifetime(container) {} }
        let id = try #require(model.conversation?.id)
        context.insert(Message(conversationID: id, role: "assistant", content: "partial", status: .generating))
        context.insert(Message(conversationID: id, role: "user", content: "waiting", status: .queued))
        try context.save()
        let restored = ChatModel(); restored.configure(context: ModelContext(container), provider: provider)
        #expect(restored.messages.allSatisfy { $0.status == .interrupted })
        #expect(!restored.isGenerating)
        #expect(restored.queuedIDs.isEmpty)
    }
    @Test func crisisDoesNotCallProvider() async throws {
        let (container, _, model, client, provider, keychain) = try setup()
        defer { model.stop(); try? keychain.delete(for: provider.id); withExtendedLifetime(container) {} }
        model.send("我不想活了")
        try await waitFor { !model.isGenerating }
        #expect(client.count == 0)
        #expect(model.messages.last?.status == .complete)
    }
    @Test func persistentStoreReopens() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Lumi-\(UUID()).store")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let schema = LumiSchema.schema
        let id = UUID()
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(Message(conversationID: id, role: "user", content: "survives restart"))
            try context.save()
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)])
        let records = try ModelContext(reopened).fetch(FetchDescriptor<Message>())
        #expect(records.count == 1)
        #expect(records.first?.content == "survives restart")
    }
}
