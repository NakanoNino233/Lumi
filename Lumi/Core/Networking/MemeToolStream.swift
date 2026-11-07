import Foundation

enum MemeStreamEvent: Sendable, Equatable {
    case text(String)
    case meme(MemeRequest)
}

struct MemeToolDefinition: Encodable, Sendable {
    let type = "function"
    var function = Function()
    struct Function: Encodable, Sendable {
        let name = "send_meme"
        let description = "Choose a local reaction sticker by keyword and optional mood. Do not provide file paths."
        var parameters = Parameters()
    }
    struct Parameters: Encodable, Sendable {
        let type = "object"
        let properties = ["keyword": Field(description: "Short reaction keywords"), "mood": Field(description: "Optional mood, such as happy, shy, comfort, sigh")]
        let required = ["keyword"]
        let additionalProperties = false
    }
    struct Field: Encodable, Sendable { let type = "string"; var description: String }
}

struct MemeToolAccumulator {
    private struct Fragment { var name = ""; var arguments = "" }
    private var calls: [Int: Fragment] = [:]
    mutating func consume(_ event: String) throws -> String? {
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    struct Tool: Decodable {
                        struct Function: Decodable { var name: String?; var arguments: String? }
                        var index: Int; var function: Function?
                    }
                    var content: String?; var tool_calls: [Tool]?
                }
                var delta: Delta?
            }
            var choices: [Choice]?
            var error: CompletionEnvelope.ProviderError?
        }
        guard let data = event.data(using: .utf8), let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            if event.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { throw LLMError.invalidResponse }; return nil
        }
        guard envelope.error == nil else { throw LLMError.invalidResponse }
        for call in envelope.choices?.first?.delta?.tool_calls ?? [] {
            guard (0..<2).contains(call.index) else { throw LLMError.invalidResponse }
            var item = calls[call.index] ?? Fragment()
            item.name += call.function?.name ?? ""; item.arguments += call.function?.arguments ?? ""
            guard item.name.utf8.count <= 80, item.arguments.utf8.count <= 4096 else { throw LLMError.responseTooLarge }
            calls[call.index] = item
        }
        return envelope.choices?.first?.delta?.content
    }
    func finish() throws -> [MemeRequest] {
        try calls.keys.sorted().map { key in
            let call = calls[key]!
            guard call.name == "send_meme", let object = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: String],
                  Set(object.keys).isSubset(of: ["keyword", "mood"]), let keyword = object["keyword"], !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  keyword.count <= 120, (object["mood"]?.count ?? 0) <= 40 else { throw LLMError.invalidResponse }
            return MemeRequest(keyword: keyword, mood: object["mood"] ?? "")
        }
    }
}

func textMemeEvents(_ stream: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<MemeStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do { for try await text in stream { continuation.yield(.text(text)) }; continuation.finish() }
            catch { continuation.finish(throwing: error) }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
    }
}

extension LLMClient {
    func streamMeme(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], tools: Bool) -> AsyncThrowingStream<MemeStreamEvent, Error> {
        guard tools else { return textMemeEvents(stream(endpoint: endpoint, key: key, messages: messages)) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let usageID = UUID()
                    let request = try request(endpoint: endpoint, key: key, messages: messages, streaming: true, memeTool: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    await usageRecorder.record(id: usageID, endpoint: endpoint, usage: nil)
                    guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw LLMError.invalidResponse }
                    var parser = SSEParser(); var accumulator = MemeToolAccumulator(); var buffer = Data(); var count = 0; var hasText = false
                    func consume(_ events: [String]) async throws {
                        for event in events {
                            await recordUsage(event, id: usageID, endpoint: endpoint)
                            if let text = try accumulator.consume(event), !text.isEmpty {
                                count += text.utf8.count; guard count <= SSEParser.maximumEventBytes else { throw LLMError.responseTooLarge }
                                hasText = true; continuation.yield(.text(text))
                            }
                        }
                    }
                    for try await byte in bytes {
                        try Task.checkCancellation(); buffer.append(byte)
                        if byte != 10 && byte != 13 && buffer.count < 4096 { continue }
                        try await consume(parser.append(buffer)); buffer.removeAll(keepingCapacity: true)
                        if parser.isDone { break }
                    }
                    try await consume(parser.append(buffer) + parser.finish())
                    let calls = try accumulator.finish()
                    guard hasText || !calls.isEmpty else { throw LLMError.emptyResponse }
                    for call in calls { continuation.yield(.meme(call)) }
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
                catch { continuation.finish(throwing: LLMError.sanitized(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
