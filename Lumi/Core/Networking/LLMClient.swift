import Foundation

struct ProviderEndpoint: Sendable, Equatable {
    var baseURL: String
    var model: String
    var isOpenAI: Bool { URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() == "api.openai.com" }
    var tokenOwners: [TokenOwner] = []
    var tokenFunction: TokenFunction = .unclassified
    func function(_ value: TokenFunction) -> Self { var copy = self; copy.tokenFunction = value; return copy }
    func attributed(to owners: [TokenOwner]) -> Self {
        var copy = self
        var seen = Set<UUID>()
        copy.tokenOwners = owners.filter { seen.insert($0.id).inserted }
        return copy
    }
    @MainActor func attributed(to character: LumiCharacter) -> Self { attributed(to: [TokenOwner(id: character.id, name: character.name)]) }
    func completionURL() throws -> URL {
        guard let parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var url = parts.url else { throw LLMError.invalidConfiguration }
        if !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("chat/completions") {
            url.append(path: "chat/completions")
        }
        return url
    }
}

struct ChatTurn: Codable, Sendable, Equatable {
    var role: String
    var content: String
    var imageURLs: [String] = []
    var toolCalls: [ToolCall]? = nil
    var toolCallID: String? = nil
    enum CodingKeys: String, CodingKey { case role, content, toolCalls = "tool_calls", toolCallID = "tool_call_id" }
    struct Part: Codable { var type: String; var text: String?; var image_url: ImageURL? }
    struct ImageURL: Codable { var url: String }
    init(role: String, content: String, imageURLs: [String] = [], toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role; self.content = content; self.imageURLs = imageURLs; self.toolCalls = toolCalls; self.toolCallID = toolCallID
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        toolCalls = try values.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallID = try values.decodeIfPresent(String.self, forKey: .toolCallID)
        if let text = try? values.decode(String.self, forKey: .content) { content = text }
        else {
            let parts = try values.decode([Part].self, forKey: .content)
            content = parts.compactMap(\.text).joined(separator: "\n")
            imageURLs = parts.compactMap { $0.image_url?.url }
        }
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role, forKey: .role)
        try values.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try values.encodeIfPresent(toolCallID, forKey: .toolCallID)
        if imageURLs.isEmpty { try values.encode(content, forKey: .content) }
        else {
            let parts = [Part(type: "text", text: content)] + imageURLs.map { Part(type: "image_url", image_url: ImageURL(url: $0)) }
            try values.encode(parts, forKey: .content)
        }
    }
}
struct CompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatTurn]
    let stream: Bool
    let max_tokens: Int
    var tools: [NativeToolDefinition]? = nil
    struct Thinking: Encodable, Sendable { var type = "disabled" }
    var thinking: Thinking? = nil
    var usesCompletionTokenLimit = false
    var reasoning_effort: String? = nil
    struct StreamOptions: Encodable, Sendable { let include_usage = true }
    var stream_options: StreamOptions? { stream ? .init() : nil }
    enum CodingKeys: String, CodingKey { case model, messages, stream, max_tokens, max_completion_tokens, tools, thinking, stream_options, reasoning_effort }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(model, forKey: .model); try values.encode(messages, forKey: .messages)
        try values.encode(stream, forKey: .stream)
        try values.encode(max_tokens, forKey: usesCompletionTokenLimit ? .max_completion_tokens : .max_tokens)
        try values.encodeIfPresent(reasoning_effort, forKey: .reasoning_effort)
        try values.encodeIfPresent(tools, forKey: .tools); try values.encodeIfPresent(thinking, forKey: .thinking)
        try values.encodeIfPresent(stream_options, forKey: .stream_options)
    }
}

protocol ChatClient: Sendable {
    func streamTools(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], definitions: [NativeToolDefinition]) -> AsyncThrowingStream<ToolStreamEvent, Error>
    func streamMeme(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], tools: Bool) -> AsyncThrowingStream<MemeStreamEvent, Error>
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error>
    func complete(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], limit: Int) async throws -> String
}

extension ChatClient {
    func streamMeme(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], tools: Bool) -> AsyncThrowingStream<MemeStreamEvent, Error> { textMemeEvents(stream(endpoint: endpoint, key: key, messages: messages)) }
    func complete(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], limit: Int) async throws -> String {
        var result = ""
        for try await chunk in stream(endpoint: endpoint, key: key, messages: messages) {
            result += chunk
            guard result.utf8.count <= 128_000 else { throw LLMError.responseTooLarge }
        }
        return result
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Do not forward a credential to a redirect destination.
        completionHandler(nil)
    }
}

struct LLMClient: ChatClient, Sendable {
    let session: URLSession
    let usageRecorder: TokenUsageRecorder
    init(session: URLSession? = nil, usageRecorder: TokenUsageRecorder = .shared) {
        self.usageRecorder = usageRecorder
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 180
            configuration.urlCache = nil; configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }
    func request(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], streaming: Bool, limit: Int = 2048, memeTool: Bool = false, definitions: [NativeToolDefinition]? = nil) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.missingKey }
        var request = URLRequest(url: try endpoint.completionURL())
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpBody = try StableJSON.encoder().encode(CompletionRequest(model: endpoint.model, messages: messages, stream: streaming, max_tokens: limit, tools: definitions ?? (memeTool ? [ToolRegistry.spec("send_meme")!.definition] : nil), thinking: URL(string: endpoint.baseURL)?.host == "api.deepseek.com" ? .init() : nil, usesCompletionTokenLimit: endpoint.isOpenAI, reasoning_effort: endpoint.isOpenAI && (endpoint.model == "gpt-6-luna" || endpoint.model.hasPrefix("gpt-6-luna-")) ? "none" : nil))
        return request
    }
    func complete(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], limit: Int = 16) async throws -> String {
        do {
            let usageID = UUID()
            let request = try request(endpoint: endpoint, key: key, messages: messages, streaming: false, limit: limit)
            let (bytes, response) = try await session.bytes(for: request)
            try validate(response)
            await usageRecorder.record(id: usageID, endpoint: endpoint, usage: nil)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                guard data.count <= SSEParser.maximumEventBytes else { throw LLMError.responseTooLarge }
            }
            await usageRecorder.record(id: usageID, endpoint: endpoint, usage: ReportedTokenUsage.decode(data))
            guard let envelope = try? JSONDecoder().decode(CompletionEnvelope.self, from: data), envelope.error == nil else { throw LLMError.invalidResponse }
            guard let content = envelope.choices?.first?.message?.content, !content.isEmpty else { throw LLMError.emptyResponse }
            return content
        } catch is CancellationError { throw CancellationError() }
        catch { throw LLMError.sanitized(error) }
    }
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let usageID = UUID()
                    let request = try request(endpoint: endpoint, key: key, messages: messages, streaming: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    await usageRecorder.record(id: usageID, endpoint: endpoint, usage: nil)
                    guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw LLMError.invalidResponse }
                    var parser = SSEParser()
                    var outputBytes = 0
                    var hasContent = false
                    var transportBuffer = Data()
                    // Flush on LF/CR (or a bounded chunk), while preserving split UTF-8 in the parser.
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        transportBuffer.append(byte)
                        if byte != 10 && byte != 13 && transportBuffer.count < 4096 { continue }
                        let events = try parser.append(transportBuffer)
                        transportBuffer.removeAll(keepingCapacity: true)
                        for event in events {
                            await recordUsage(event, id: usageID, endpoint: endpoint)
                            if let text = try CompletionDecoder.content(from: event), !text.isEmpty {
                                outputBytes += text.utf8.count
                                guard outputBytes <= SSEParser.maximumEventBytes else { throw LLMError.responseTooLarge }
                                hasContent = true; continuation.yield(text)
                            }
                        }
                        if parser.isDone { break }
                    }
                    let tail = try parser.append(transportBuffer) + parser.finish()
                    for event in tail {
                        await recordUsage(event, id: usageID, endpoint: endpoint)
                        if let text = try CompletionDecoder.content(from: event), !text.isEmpty {
                            outputBytes += text.utf8.count
                            guard outputBytes <= SSEParser.maximumEventBytes else { throw LLMError.responseTooLarge }
                            hasContent = true; continuation.yield(text)
                        }
                    }
                    guard hasContent else { throw LLMError.emptyResponse }
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
                catch { continuation.finish(throwing: LLMError.sanitized(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    func recordUsage(_ event: String, id: UUID, endpoint: ProviderEndpoint) async {
        if let usage = ReportedTokenUsage.decode(Data(event.utf8)) {
            await usageRecorder.record(id: id, endpoint: endpoint, usage: usage)
        }
    }
    func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw LLMError.http(response.statusCode) }
    }
}
