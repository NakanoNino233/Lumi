import Foundation
import Testing
import SwiftData
@testable import Lumi

private struct StubResponse: Sendable {
    let status: Int
    let mime: String
    let body: String
}

private final class StubRoutes: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: StubResponse] = [:]
    func add(_ response: StubResponse, host: String) { lock.withLock { routes[host] = response } }
    func get(_ host: String) -> StubResponse? { lock.withLock { routes[host] } }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let routes = StubRoutes()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let host = url.host, let stub = Self.routes.get(host),
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": stub.mime]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

struct LLMTransportTests {
    @Test func genericToolSSEThroughURLSession() async throws {
        let first = #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"reminder_1","function":{"name":"set_","arguments":"{\"title\":\"Wake up\","}}]}}]}"#
        let second = #"{"choices":[{"delta":{"content":"One moment","tool_calls":[{"index":0,"function":{"name":"reminder","arguments":"\"date\":\"2026-11-03T07:00:00+08:00\",\"reason\":\"You asked\"}"}}]}}]}"#
        let (client, endpoint, session) = setup(mime: "text/event-stream", body: "data: " + first + "\n\ndata: " + second + "\n\ndata: [DONE]\n\n")
        defer { session.invalidateAndCancel() }
        var events: [ToolStreamEvent] = []
        for try await event in client.streamTools(endpoint: endpoint, key: "fake-local-key", messages: [], definitions: [ToolRegistry.spec("set_reminder")!.definition]) { events.append(event) }
        #expect(events.count == 2); #expect(events.first == .text("One moment"))
        if case .call(let call) = events.last {
            #expect(call.id == "reminder_1"); #expect(call.name == "set_reminder")
            #expect(try ToolRegistry.validate(call)["title"]?.string == "Wake up")
        } else { Issue.record("Missing native tool call") }
    }
    @Test(arguments: [0, 1, 2, 3]) @MainActor
    func actualUsageAcrossAllTransports(_ mode: Int) async throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let recorder = TokenUsageRecorder(container: store)
        let usage = #"{"prompt_tokens":100,"completion_tokens":25,"prompt_cache_hit_tokens":80}"#
        let chunk = #"{"choices":[],"usage":USAGE}"#.replacingOccurrences(of: "USAGE", with: usage)
        let body = mode == 3
            ? #"{"choices":[{"message":{"content":"OK"}}],"usage":USAGE}"#.replacingOccurrences(of: "USAGE", with: usage)
            : "data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\ndata: " + chunk + "\n\ndata: " + chunk + "\n\ndata: [DONE]\n\n"
        let (client, rawEndpoint, session) = setup(mime: mode == 3 ? "application/json" : "text/event-stream", body: body, recorder: recorder)
        defer { session.invalidateAndCancel() }
        let endpoint = rawEndpoint.attributed(to: [TokenOwner(id: UUID(), name: "A")])
        switch mode {
        case 0: for try await _ in client.stream(endpoint: endpoint, key: "fake-key", messages: []) { }
        case 1: for try await _ in client.streamTools(endpoint: endpoint, key: "fake-key", messages: [], definitions: [ToolRegistry.spec("save_memory")!.definition]) { }
        case 2: for try await _ in client.streamMeme(endpoint: endpoint, key: "fake-key", messages: [], tools: true) { }
        default: _ = try await client.complete(endpoint: endpoint, key: "fake-key", messages: [])
        }
        let records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        #expect(records.count == 1); #expect(records.first?.total == 125); #expect(records.first?.cached == 80)
        #expect(records.first?.owners == endpoint.tokenOwners)
    }
    @Test @MainActor func finalContentChunkUsageAndNoUsageEstimation() async throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let recorder = TokenUsageRecorder(container: store)
        for reported in [false, true] {
            let final = reported ? #", "usage":{"prompt_tokens":40,"completion_tokens":5,"prompt_cache_hit_tokens":0}"# : ""
            let body = #"data: {"choices":[{"delta":{"content":"OK"},"finish_reason":"stop"}]FINAL}"#.replacingOccurrences(of: "FINAL", with: final) + "\n\ndata: [DONE]\n\n"
            let (client, endpoint, session) = setup(mime: "text/event-stream", body: body, recorder: recorder)
            defer { session.invalidateAndCancel() }
            for try await _ in client.streamTools(endpoint: endpoint, key: "fake-key", messages: [], definitions: []) { }
        }
        let records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        #expect(records.count == 2); #expect(records.filter(\.hasUsage).count == 1)
        let summary = TokenUsageSummary(records: records, characters: [])
        #expect(summary.total == 45); #expect(summary.unknownRequests == 1); #expect(summary.cacheRate == 0)
    }
    @Test @MainActor func reportedUsageSurvivesResponseFailure() async throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let recorder = TokenUsageRecorder(container: store)
        let body = #"data: {"choices":[],"usage":{"prompt_tokens":30,"completion_tokens":5}}"#
            + "\n\ndata: {\"error\":{\"code\":\"late_failure\"}}\n\ndata: [DONE]\n\n"
        let (client, endpoint, session) = setup(mime: "text/event-stream", body: body, recorder: recorder)
        defer { session.invalidateAndCancel() }
        await #expect(throws: LLMError.invalidResponse) {
            for try await _ in client.stream(endpoint: endpoint, key: "fake-key", messages: []) { }
        }
        let records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        #expect(records.count == 1); #expect(records.first?.hasUsage == true); #expect(records.first?.total == 35)
    }
    private func setup(status: Int = 200, mime: String, body: String, recorder: TokenUsageRecorder = TokenUsageRecorder(disabled: true)) -> (LLMClient, ProviderEndpoint, URLSession) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        StubProtocol.routes.add(StubResponse(status: status, mime: mime, body: body), host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        return (LLMClient(session: session, usageRecorder: recorder), ProviderEndpoint(baseURL: "https://" + host, model: "test-model"), session)
    }
    @Test func nativeMemeToolOnlySSEThroughURLSession() async throws {
        let object: [String: Any] = ["choices": [["delta": ["tool_calls": [["index": 0, "function": ["name": "send_meme", "arguments": "{\"keyword\":\"抱抱\",\"mood\":\"comfort\"}"]]]]]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let (client, endpoint, session) = setup(mime: "text/event-stream", body: "data: " + json + "\n\ndata: [DONE]\n\n")
        defer { session.invalidateAndCancel() }
        var events: [MemeStreamEvent] = []
        for try await event in client.streamMeme(endpoint: endpoint, key: "fake-local-key", messages: [], tools: true) { events.append(event) }
        #expect(events == [.meme(MemeRequest(keyword: "抱抱", mood: "comfort"))])
    }

    @Test func streamThroughURLSession() async throws {
        let body = """
        : heartbeat

        data: {"choices":[{"delta":{"reasoning_content":"hidden"}}]}

        data: {"choices":[{"delta":{"content":"你好"}}]}

        data: {"choices":[{"delta":{"content":" 🌻"},"finish_reason":"stop"}]}

        data: [DONE]


        """
        let (client, endpoint, session) = setup(mime: "text/event-stream; charset=utf-8", body: body)
        defer { session.invalidateAndCancel() }
        var output = ""
        for try await text in client.stream(endpoint: endpoint, key: "fake-test-key", messages: [ChatTurn(role: "user", content: "hello")]) { output += text }
        #expect(output == "你好 🌻")
    }
    @Test func nonStreamingResponse() async throws {
        let (client, endpoint, session) = setup(mime: "application/json", body: #"{"choices":[{"message":{"content":"OK"}}]}"#)
        defer { session.invalidateAndCancel() }
        #expect(try await client.complete(endpoint: endpoint, key: "fake-test-key", messages: []) == "OK")
    }
    @Test(arguments: [(401, LLMError.unauthorized), (402, .balance), (429, .rateLimited), (404, .modelMissing), (503, .server)])
    func httpErrorDuringStream(value: (Int, LLMError)) async {
        let (client, endpoint, session) = setup(status: value.0, mime: "application/json", body: #"{"error":{"message":"Bearer do-not-show-this"}}"#)
        defer { session.invalidateAndCancel() }
        do {
            for try await _ in client.stream(endpoint: endpoint, key: "fake-test-key", messages: []) { }
            Issue.record("Expected HTTP error")
        } catch { #expect(error as? LLMError == value.1) }
    }
    @Test func emptyReasoningOnlyStreamFails() async {
        let (client, endpoint, session) = setup(mime: "text/event-stream", body: "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"hidden\"}}]}\n\ndata: [DONE]\n\n")
        defer { session.invalidateAndCancel() }
        do {
            for try await _ in client.stream(endpoint: endpoint, key: "fake-test-key", messages: []) { }
            Issue.record("Expected empty response")
        } catch { #expect(error as? LLMError == .emptyResponse) }
    }
    @Test func rejectsWrongContentType() async {
        let (client, endpoint, session) = setup(mime: "text/html", body: "<html>error</html>")
        defer { session.invalidateAndCancel() }
        do {
            for try await _ in client.stream(endpoint: endpoint, key: "fake-test-key", messages: []) { }
            Issue.record("Expected incompatible stream")
        } catch { #expect(error as? LLMError == .invalidResponse) }
    }
}
