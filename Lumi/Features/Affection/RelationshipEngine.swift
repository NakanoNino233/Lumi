import Foundation
import SwiftData
import CryptoKit

struct ParsedReply: Sendable {
    var text: String
    var memoryIDs: [UUID]
    var affectionDelta: Int?
    var mood: String?
}

enum ReplyParser {
    static func parse(_ raw: String) -> ParsedReply {
        let source = raw as NSString
        let mem = try! NSRegularExpression(pattern: #"<mem\s+id="([0-9A-Fa-f-]{36})"\s*/>"#)
        let memoryIDs = mem.matches(in: raw, range: NSRange(location: 0, length: source.length)).compactMap { UUID(uuidString: source.substring(with: $0.range(at: 1))) }
        let meta = try! NSRegularExpression(pattern: #"<meta\s+affection_delta="(-?\d{1,4})"\s+mood="([^"<>]{0,40})"\s*/>"#)
        let match = meta.firstMatch(in: raw, range: NSRange(location: 0, length: source.length))
        let delta = match.flatMap { Int(source.substring(with: $0.range(at: 1))) }
        let mood = match.map { source.substring(with: $0.range(at: 2)) }
        var text = ""; var tail = raw[...]
        while let start = tail.firstIndex(of: "<") {
            text += tail[..<start]
            let rest = tail[start...]
            let lower = rest.lowercased()
            if lower.hasPrefix("<mem") || lower.hasPrefix("<meta") || "<mem".hasPrefix(lower) || "<meta".hasPrefix(lower) {
                guard let end = rest.firstIndex(of: ">") else { tail = ""; break }
                tail = rest[rest.index(after: end)...]
            } else {
                text.append("<"); tail = rest[rest.index(after: start)...]
            }
        }
        text += tail
        return ParsedReply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), memoryIDs: Array(Set(memoryIDs)), affectionDelta: delta, mood: mood)
    }
}

@MainActor enum RelationshipEngine {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    static func fingerprint(_ text: String) -> String {
        let normalized = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func stage(_ score: Int, character: LumiCharacter) -> Int {
        if score >= character.partnerThreshold { return 3 }
        if score >= character.closeThreshold { return 2 }
        if score >= character.familiarThreshold { return 1 }
        return 0
    }
    @discardableResult static func apply(delta: Int?, mood: String?, user: Message, character: LumiCharacter, context: ModelContext, now: Date = .now) throws -> Bool {
        let cid = character.id
        let awards = try context.fetch(FetchDescriptor<AffectionAward>(predicate: #Predicate { $0.characterID == cid }))
        // Re-generation and deleting/re-sending the same text cannot re-award a turn.
        guard !awards.contains(where: { $0.userMessageID == user.id }) else { return false }
        let day = dayKey(now)
        if character.affectionDay != day { character.affectionDay = day; character.dailyGain = 0; character.dailyLoss = 0 }
        let hash = fingerprint(user.content)
        let repeated = awards.contains { dayKey($0.createdAt) == day && $0.fingerprint == hash }
        var amount = max(-3, min(3, delta ?? 0))
        if repeated || user.content.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 { amount = 0 }
        if amount > 0 {
            if let previous = character.lastAffectionAt, now.timeIntervalSince(previous) < 60 { amount = 0 }
            amount = min(amount, max(0, 6 - character.dailyGain))
        } else { amount = max(amount, -max(0, 6 - character.dailyLoss)) }
        let before = character.affection
        character.affection = max(0, min(100, before + amount))
        let actual = character.affection - before
        if actual > 0 { character.dailyGain += actual; character.lastAffectionAt = now }
        if actual < 0 { character.dailyLoss += -actual }
        if let mood { character.mood = String(mood.prefix(40)) }
        context.insert(AffectionAward(characterID: cid, userMessageID: user.id, fingerprint: hash, delta: actual, createdAt: now))
        let newStage = stage(character.affection, character: character)
        let changed = character.stageIndex != newStage
        character.stageIndex = newStage
        return changed
    }
    static func stageText(_ index: Int) -> String {
        var resource = stageName(index); resource.locale = AppLocale.current
        return String(localized: resource)
    }
    static func stageName(_ index: Int) -> LocalizedStringResource {
        switch index { case 1: "熟悉"; case 2: "暧昧"; case 3: "恋人"; default: "陌生" }
    }
}
