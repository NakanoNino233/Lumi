import Foundation
import SwiftData

struct MomentComment: Codable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    // Optional fields keep comments from earlier versions readable as the user's comments.
    var authorID: UUID?
    var authorName: String?
    var createdAt: Date?
    var replyToID: UUID?
    var replyToName: String?
    var displayName: String { authorName ?? "我" }
}

struct MomentReaction: Codable, Identifiable, Sendable {
    var id: UUID // The friend's stable ID, one like per friend.
    var name: String
    var liked: Bool
    var interactionID: UUID
}

@Model final class MomentPost {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var authorID: UUID?
    var authorName: String?
    var liked: Bool = false
    var commentData: Data?
    var reactionData: Data?
    var comments: [MomentComment] {
        get { commentData.flatMap { try? JSONDecoder().decode([MomentComment].self, from: $0) } ?? [] }
        set { commentData = try? JSONEncoder().encode(newValue) }
    }
    var reactions: [MomentReaction] {
        get { reactionData.flatMap { try? JSONDecoder().decode([MomentReaction].self, from: $0) } ?? [] }
        set { reactionData = try? JSONEncoder().encode(newValue) }
    }
    // Only new user comments invite another response. AI comments never create an endless loop.
    var interactionID: UUID { comments.last(where: { $0.authorID == nil })?.id ?? id }
    var displayName: String { authorName ?? "我" }
    var likeNames: [String] { (liked ? ["我"] : []) + reactions.filter(\.liked).map(\.name) }
    @Attribute(.externalStorage) var imagesData: Data?
    var images: [ChatAttachment] {
        get { imagesData.flatMap { try? JSONDecoder().decode([ChatAttachment].self, from: $0) } ?? [] }
        set { imagesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
    init(content: String, images: [ChatAttachment] = [], authorID: UUID? = nil, authorName: String? = nil) {
        id = UUID(); self.content = content; createdAt = .now; self.images = images
        self.authorID = authorID; self.authorName = authorName
    }
}

enum MomentsPreferences {
    static let coverKey = "moments.cover"
    static let enabledKey = "moments.automatic"
    static let tagsKey = "moments.personalTags"
    static func enabled(in defaults: UserDefaults = AppPreferences.defaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }
}

enum MomentsTags {
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted }
    }
    static func isValid(_ text: String) -> Bool {
        guard text.utf8.count <= 1000 else { return false }
        let tags = parse(text)
        return tags.count <= 3 && tags.allSatisfy { $0.count <= 12 && $0.rangeOfCharacter(from: .controlCharacters) == nil }
    }
    static func visible(_ text: String) -> [String] {
        isValid(text) ? parse(text) : []
    }
}
