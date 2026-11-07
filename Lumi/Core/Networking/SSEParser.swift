import Foundation

/// Incremental byte framing preserves UTF-8 split across transport chunks.
struct SSEParser: Sendable {
    private var line = Data()
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var previousWasCR = false
    private(set) var isDone = false
    static let maximumEventBytes = 1_048_576

    mutating func append(_ chunk: Data) throws -> [String] {
        var events: [String] = []
        for byte in chunk {
            guard !isDone else { break }
            if byte == 10 && previousWasCR { previousWasCR = false; continue }
            if byte == 10 || byte == 13 {
                try consumeLine(into: &events)
                previousWasCR = byte == 13
            } else {
                previousWasCR = false
                line.append(byte)
                if line.count + eventBytes > Self.maximumEventBytes { throw LLMError.responseTooLarge }
            }
        }
        return events
    }
    mutating func finish() throws -> [String] {
        var events: [String] = []
        if !isDone {
            if !line.isEmpty { try consumeLine(into: &events) }
            dispatch(into: &events)
        }
        return events
    }
    private mutating func consumeLine(into events: inout [String]) throws {
        guard let text = String(data: line, encoding: .utf8) else { throw LLMError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if text.isEmpty { dispatch(into: &events); return }
        guard text.hasPrefix("data:") else { return } // comments, heartbeat, id, event
        var data = String(text.dropFirst(5))
        if data.first == " " { data.removeFirst() }
        eventBytes += data.utf8.count
        guard eventBytes <= Self.maximumEventBytes else { throw LLMError.responseTooLarge }
        dataLines.append(data)
    }
    private mutating func dispatch(into events: inout [String]) {
        guard !dataLines.isEmpty else { return }
        let event = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true); eventBytes = 0
        if event.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" { isDone = true }
        else { events.append(event) }
    }
}

struct CompletionEnvelope: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable { var content: String?; var reasoning_content: String? }
        var delta: Delta?
        var message: Delta?
        var finish_reason: String?
    }
    struct ProviderError: Decodable, Sendable { var code: String? }
    var choices: [Choice]?
    var error: ProviderError?
}

struct CompletionDecoder: Sendable {
    /// Non-JSON heartbeat lines are harmless; reasoning is intentionally not returned.
    static func content(from event: String) throws -> String? {
        guard let data = event.data(using: .utf8) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CompletionEnvelope.self, from: data) else {
            if event.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { throw LLMError.invalidResponse }
            return nil
        }
        if envelope.error != nil { throw LLMError.invalidResponse }
        return envelope.choices?.first?.delta?.content
    }
}
