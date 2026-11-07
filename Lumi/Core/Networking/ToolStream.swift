import Foundation

struct ToolCallAccumulator {
    private struct Fragment { var id = ""; var name = ""; var arguments = "" }
    private var calls: [Int: Fragment] = [:]
    private struct Envelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                struct Call: Decodable {
                    struct Function: Decodable { var name: String?; var arguments: String? }
                    var index: Int; var id: String?; var function: Function?
                }
                var content: String?; var tool_calls: [Call]?
            }
            var delta: Delta?
        }
        var choices: [Choice]?; var error: CompletionEnvelope.ProviderError?
    }
    mutating func consume(_ event: String) throws -> String? {
        guard let data = event.data(using: .utf8), let value = try? JSONDecoder().decode(Envelope.self, from: data) else {
            if event.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { throw LLMError.invalidResponse }; return nil
        }
        guard value.error == nil else { throw LLMError.invalidResponse }
        for delta in value.choices?.first?.delta?.tool_calls ?? [] {
            guard (0..<16).contains(delta.index) else { throw LLMError.responseTooLarge }
            var fragment = calls[delta.index] ?? Fragment()
            fragment.id += delta.id ?? ""; fragment.name += delta.function?.name ?? ""; fragment.arguments += delta.function?.arguments ?? ""
            guard fragment.id.count <= 128, fragment.name.count <= 80, fragment.arguments.utf8.count <= 16_000 else { throw LLMError.responseTooLarge }
            calls[delta.index] = fragment
        }
        return value.choices?.first?.delta?.content
    }
    func finish() throws -> [ToolCall] {
        var ids = Set<String>()
        return try calls.keys.sorted().map { index in
            let fragment = calls[index]!
            guard !fragment.name.isEmpty else { throw LLMError.invalidResponse }
            let id = fragment.id.isEmpty ? "lumi_call_\(index)" : fragment.id
            guard ids.insert(id).inserted else { throw LLMError.invalidResponse }
            return ToolCall(id: id, name: fragment.name, arguments: fragment.arguments)
        }
    }
}

extension ChatClient {
    func streamTools(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], definitions: [NativeToolDefinition]) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        let source = streamMeme(endpoint: endpoint, key: key, messages: messages, tools: definitions.contains { $0.function.name == "send_meme" })
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in source {
                        switch event {
                        case .text(let text): continuation.yield(.text(text))
                        case .meme(let meme): continuation.yield(.call(ToolCall(name: "send_meme", arguments: JSONValue.object(["keyword": .string(meme.keyword), "mood": .string(meme.mood)]).encoded)))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
extension LLMClient {
    func streamTools(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], definitions: [NativeToolDefinition]) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        guard !definitions.isEmpty else {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do { for try await text in stream(endpoint: endpoint, key: key, messages: messages) { continuation.yield(.text(text)) }; continuation.finish() }
                    catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let usageID = UUID()
                    let request = try request(endpoint: endpoint, key: key, messages: messages, streaming: true, definitions: definitions)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response)
                    await usageRecorder.record(id: usageID, endpoint: endpoint, usage: nil)
                    guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw LLMError.invalidResponse }
                    var parser = SSEParser(); var accumulator = ToolCallAccumulator(); var buffer = Data(); var count = 0; var hasText = false
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
                    let calls = try accumulator.finish(); guard hasText || !calls.isEmpty else { throw LLMError.emptyResponse }
                    for call in calls { continuation.yield(.call(call)) }; continuation.finish()
                } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
                catch { continuation.finish(throwing: LLMError.sanitized(error)) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
