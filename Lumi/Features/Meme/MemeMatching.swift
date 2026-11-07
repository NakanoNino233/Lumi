import Foundation

enum MemeMatcher {
    static let moods = ["happy", "shy", "sad", "angry", "confused", "sigh", "comfort", "like", "sleep", "morning"]
    static func normalizedMood(_ text: String) -> String {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases: [String: [String]] = ["happy": ["开心", "高兴", "快乐", "得意", "笑"], "shy": ["害羞", "撒娇", "脸红"], "sad": ["难过", "伤心", "哭"], "angry": ["生气", "愤怒"], "confused": ["疑惑", "疑问", "慌张"], "sigh": ["无语", "叹气", "疲惫"], "comfort": ["安慰", "抱抱", "温柔"], "like": ["喜欢", "比心", "爱"], "sleep": ["困", "睡觉", "晚安"], "morning": ["早安", "早上好"]]
        if moods.contains(value) { return value }
        return moods.first { aliases[$0]?.contains(where: { value.contains($0) }) == true } ?? value
    }
    static func best(keyword: String, mood: String = "", candidates: [MemeCandidate], excluding: Set<UUID> = []) -> MemeCandidate? {
        let query = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = KeywordMemoryRetriever.terms(query)
        let wantedMood = normalizedMood(mood.isEmpty ? keyword : mood)
        return candidates.filter { !excluding.contains($0.id) }.compactMap { candidate -> (MemeCandidate, Int)? in
            let hay = (candidate.caption + " " + candidate.keywords).lowercased()
            let overlap = terms.intersection(KeywordMemoryRetriever.terms(hay)).count
            let exact = !query.isEmpty && hay.contains(query)
            let moodMatch = !wantedMood.isEmpty && normalizedMood(candidate.mood) == wantedMood
            guard overlap > 0 || exact || moodMatch else { return nil }
            return (candidate, overlap * 5 + (exact ? 20 : 0) + (moodMatch ? 12 : 0))
        }.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            if left.0.usageCount != right.0.usageCount { return left.0.usageCount < right.0.usageCount }
            return left.0.id.uuidString < right.0.id.uuidString
        }.first?.0
    }
}

struct MemeRequest: Sendable, Equatable { var keyword: String; var mood: String = "" }
struct ParsedMemeReply: Sendable { var text: String; var requests: [MemeRequest] }

enum MemeReplyParser {
    static func parse(_ text: String, final: Bool, replacement: ((String) -> String)? = nil) -> ParsedMemeReply {
        var output = ""; var remaining = text[...]; var requests: [MemeRequest] = []
        while let start = remaining.firstIndex(where: { $0 == "[" || $0 == "［" }) {
            output += remaining[..<start]
            let suffix = remaining[start...]
            let rest = String(suffix.dropFirst())
            let afterName = rest.hasPrefix("表情") ? String(rest.dropFirst(2)).drop(while: { $0.isWhitespace }) : nil
            if let afterName, let first = afterName.first, first == ":" || first == "：" {
                if let end = suffix.firstIndex(where: { $0 == "]" || $0 == "］" }) {
                    let inner = String(suffix[suffix.index(after: start)..<end])
                    let split = inner.firstIndex(where: { $0 == ":" || $0 == "：" })!
                    let keyword = String(inner[inner.index(after: split)...].trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
                    if !keyword.isEmpty {
                        if requests.count < 16 { requests.append(MemeRequest(keyword: keyword)) }
                        if final { output += replacement?(keyword) ?? keyword }
                    }
                    remaining = suffix[suffix.index(after: end)...]
                } else {
                    if final { output += afterName.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) }
                    remaining = ""; break
                }
            } else if "表情".hasPrefix(rest) || afterName?.isEmpty == true {
                // Suppress a marker prefix even when a stream stops in the middle of it.
                remaining = ""; break
            } else {
                output.append(suffix.first!); remaining = suffix.dropFirst()
            }
        }
        output += remaining
        return ParsedMemeReply(text: output.trimmingCharacters(in: .whitespacesAndNewlines), requests: requests)
    }
}
