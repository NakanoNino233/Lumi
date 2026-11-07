import Foundation
import SwiftData

@Model final class LumiCharacter {
    @Attribute(.unique) var id: UUID
    var name: String
    var personaPrompt: String
    var createdAt: Date
    var isBuiltIn: Bool
    @Attribute(.externalStorage) var avatarData: Data?
    @Attribute(.externalStorage) var portraitData: Data?
    var speechStyle: String = ""
    var taboos: String = ""
    var backgroundStory: String = ""
    var firstGreeting: String = ""
    var affection: Int = 0
    var stageIndex: Int = 0
    var familiarThreshold: Int = 25
    var closeThreshold: Int = 55
    var partnerThreshold: Int = 80
    var affectionDay: String = ""
    var dailyGain: Int = 0
    var dailyLoss: Int = 0
    var lastAffectionAt: Date?
    var mood: String = ""
    var lastMemeAt: Date?
    var pinnedAt: Date?
    var lastMomentAt: Date?
    init(id: UUID = UUID(), name: String = "小夏", personaPrompt: String = "", isBuiltIn: Bool = true) {
        self.id = id; self.name = name; self.personaPrompt = personaPrompt
        self.createdAt = .now; self.isBuiltIn = isBuiltIn
    }
}

@Model final class Conversation {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var title: String
    var createdAt: Date
    var lastMessageAt: Date
    init(characterID: UUID, title: String) {
        id = UUID(); self.characterID = characterID; self.title = title
        createdAt = .now; lastMessageAt = .now
    }
}

enum MessageStatus: String, Sendable { case queued, sent, generating, complete, interrupted, failed }

@Model final class Message {
    @Attribute(.unique) var id: UUID
    var conversationID: UUID
    var role: String
    var content: String
    var createdAt: Date
    var statusRaw: String
    var replyToID: UUID?
    var recalledMemoryIDs: [UUID] = []
    var recalledMemoryTexts: [String] = []
    var isProactive: Bool = false
    var externalEventID: String?
    var mountedSkillIDs: [UUID] = []
    @Attribute(.externalStorage) var voiceData: Data?
    var voiceDuration: Double = 0
    @Attribute(.externalStorage) var memeData: Data?
    var memes: [SentMeme] {
        get { memeData.flatMap { try? JSONDecoder().decode([SentMeme].self, from: $0) } ?? [] }
        set { memeData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
    @Attribute(.externalStorage) var attachmentData: Data?
    @Attribute(.externalStorage) var toolActivityData: Data?
    var toolActivities: [ToolActivity] {
        get { toolActivityData.flatMap { try? JSONDecoder().decode([ToolActivity].self, from: $0) } ?? [] }
        set { toolActivityData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
    var attachments: [ChatAttachment] {
        get { attachmentData.flatMap { try? JSONDecoder().decode([ChatAttachment].self, from: $0) } ?? [] }
        set { attachmentData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
    var memoryCitations: [MemoryCitation] { zip(recalledMemoryIDs, recalledMemoryTexts).map { MemoryCitation(id: $0.0, text: $0.1) } }
    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .complete }
        set { statusRaw = newValue.rawValue }
    }
    init(conversationID: UUID, role: String, content: String, status: MessageStatus = .complete, replyToID: UUID? = nil) {
        id = UUID(); self.conversationID = conversationID; self.role = role; self.content = content
        createdAt = .now; statusRaw = status.rawValue; self.replyToID = replyToID
    }
}

@Model final class MemoryFact {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var category: String
    var text: String
    var importance: Int
    var sourceMessageID: UUID?
    var createdAt: Date
    var lastMentionedAt: Date?
    var pinOrder: Int = 0
    var isPinned: Bool {
        get { pinOrder > 0 }
        set { pinOrder = newValue ? 1 : 0 }
    }
    init(id: UUID = UUID(), characterID: UUID, category: String, text: String, importance: Int = 3, sourceMessageID: UUID? = nil) {
        self.id = id; self.characterID = characterID; self.category = category; self.text = text
        self.importance = importance; self.sourceMessageID = sourceMessageID; createdAt = .now
    }
}

@Model final class UserProfile {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var summary: String = ""
    var compactedBefore: Date?
    var lastExtractedAt: Date?
    var updatedAt: Date
    init(characterID: UUID) { id = UUID(); self.characterID = characterID; updatedAt = .now }
}

@Model final class Anniversary {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var title: String
    var date: Date
    var repeatsYearly: Bool
    init(characterID: UUID, title: String, date: Date, repeatsYearly: Bool = true) {
        id = UUID(); self.characterID = characterID; self.title = title; self.date = date; self.repeatsYearly = repeatsYearly
    }
}

@Model final class DiaryEntry {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var day: String
    var content: String
    var updatedAt: Date
    var dayDate: Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    init(characterID: UUID, day: String, content: String) {
        id = UUID(); self.characterID = characterID; self.day = day; self.content = content; updatedAt = .now
    }
}

@Model final class AffectionAward {
    @Attribute(.unique) var id: UUID
    var characterID: UUID
    var userMessageID: UUID
    var fingerprint: String
    var createdAt: Date
    var delta: Int
    init(characterID: UUID, userMessageID: UUID, fingerprint: String, delta: Int, createdAt: Date) {
        id = UUID(); self.characterID = characterID; self.userMessageID = userMessageID
        self.fingerprint = fingerprint; self.delta = delta; self.createdAt = createdAt
    }
}

enum LumiSchema {
    static var models: [any PersistentModel.Type] {
        [LumiCharacter.self, Conversation.self, Message.self, ProviderConfig.self,
         MemoryFact.self, UserProfile.self, Anniversary.self, DiaryEntry.self, AffectionAward.self, ScheduledGreeting.self, MomentPost.self, MemePack.self, Meme.self, InstalledSkill.self,
         GroupChat.self, GroupMessage.self, GroupPerspective.self, TokenUsageRecord.self, MarketInstallation.self]
    }
    static var schema: Schema { Schema(models) }
}

// Deliberately contains no secret; the credential is indexed by id in Keychain.
@Model final class ProviderConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURL: String
    var modelName: String
    var supportsTools: Bool
    var supportsVision: Bool
    var defaultsVersion: Int?
    init(id: UUID = UUID(), name: String = "DeepSeek", baseURL: String = "https://api.deepseek.com", modelName: String = ProviderDefaults.model) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.modelName = modelName
        supportsTools = true; supportsVision = true; defaultsVersion = 1
    }
    var endpoint: ProviderEndpoint { ProviderEndpoint(baseURL: baseURL, model: modelName) }
}

struct MemoryCitation: Identifiable { let id: UUID; let text: String }
