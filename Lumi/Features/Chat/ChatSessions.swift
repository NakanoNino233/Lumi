import Foundation
import Observation
import SwiftData

@MainActor final class ChatSessions {
    static let shared = ChatSessions()
    private var chats: [UUID: ChatModel] = [:]
    private var groups: [UUID: GroupChatModel] = [:]
    private let fallback = ChatModel()
    func chat(for id: UUID?) -> ChatModel {
        guard let id else { return fallback }
        if let model = chats[id] { return model }
        let model = ChatModel(); chats[id] = model; return model
    }
    func group(for id: UUID) -> GroupChatModel {
        if let model = groups[id] { return model }
        let model = GroupChatModel(); groups[id] = model; return model
    }
    func removeGroup(_ id: UUID) { groups.removeValue(forKey: id)?.stop(notice: false) }
    func removeFriend(_ id: UUID) { chats.removeValue(forKey: id)?.stop() }
    func reset() {
        chats.values.forEach { $0.pauseForRestore() }
        groups.values.forEach { $0.stop(notice: false) }
        fallback.pauseForRestore(); chats.removeAll(); groups.removeAll()
    }
}

/// Read positions persist across launches; only the visible, active chat consumes new messages.
@MainActor @Observable final class ChatReadState {
    static let shared = ChatReadState()
    private(set) var revision = 0
    private var visible: Set<UUID> = []
    func lastRead(_ id: UUID) -> Date {
        _ = revision
        return AppPreferences.defaults.object(forKey: "chat.lastRead.\(id)") as? Date ?? .distantPast
    }
    func enter(_ id: UUID) { visible.insert(id); markRead(id) }
    func leave(_ id: UUID) { visible.remove(id) }
    func markRead(_ id: UUID, at date: Date = .now) {
        AppPreferences.defaults.set(date, forKey: "chat.lastRead.\(id)"); revision &+= 1
    }
    func received(in id: UUID) { if visible.contains(id) { markRead(id) } }
    func remove(_ id: UUID) { visible.remove(id); AppPreferences.defaults.removeObject(forKey: "chat.lastRead.\(id)"); revision &+= 1 }
}

enum ReplyDelivery {
    /// Paragraphs become distinct chat bubbles, without breaking code blocks or long formatted replies.
    static func parts(_ text: String) -> [String] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        guard !clean.contains("```"), clean.count < 2000 else { return [clean] }
        let separated = clean.replacingOccurrences(of: #"\n\s*\n|[ \t]{3,}"#, with: "\u{001E}", options: .regularExpression)
            .components(separatedBy: "\u{001E}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard separated.count > 4 else { return separated }
        return Array(separated.prefix(3)) + [separated.dropFirst(3).joined(separator: "\n\n")]
    }
    static func delay(for text: String) -> Duration {
        .milliseconds(Int(min(6500, max(1200, Double(text.count) * 75))) + Int.random(in: 150...650))
    }
}
