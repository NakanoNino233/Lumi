import Foundation
import SwiftData

@Model final class GroupChat {
    @Attribute(.unique) var id: UUID
    var name: String
    var announcement: String
    var scene: String
    var memberIDs: [UUID]
    var createdAt: Date
    var lastMessageAt: Date
    var pinnedAt: Date?
    var independentReplies = false
    var sharesMemory = false
    var automaticChat = false
    var automaticRounds = 3
    var automaticBudget = 60_000
    var mentionNotifications = false
    var settingsData: Data?
    var memberSettings: [GroupMemberSetting] {
        get { settingsData.flatMap { try? JSONDecoder().decode([GroupMemberSetting].self, from: $0) } ?? [] }
        set { settingsData = try? JSONEncoder().encode(newValue) }
    }
    var relationshipData: Data?
    var relationships: [GroupRelationship] {
        get { relationshipData.flatMap { try? JSONDecoder().decode([GroupRelationship].self, from: $0) } ?? [] }
        set { relationshipData = try? JSONEncoder().encode(newValue) }
    }
    init(name: String, announcement: String = "", scene: String = "宿舍夜聊", memberIDs: [UUID]) {
        id = UUID(); self.name = name; self.announcement = announcement; self.scene = scene
        self.memberIDs = memberIDs; createdAt = .now; lastMessageAt = .now
    }
}

enum GroupParticipation: String, Codable, CaseIterable, Sendable {
    case talkative, normal, quiet
    var title: LocalizedStringResource {
        switch self { case .talkative: "话痨"; case .normal: "普通"; case .quiet: "高冷" }
    }
    var weight: Double { switch self { case .talkative: 0.9; case .normal: 0.55; case .quiet: 0.2 } }
}
struct GroupMemberSetting: Codable, Sendable { var characterID: UUID; var participation: GroupParticipation }
struct GroupRelationship: Codable, Identifiable, Sendable {
    var id: String { [first.uuidString, second.uuidString].sorted().joined(separator: ":") }
    var first: UUID
    var second: UUID
    var text: String
}

@Model final class GroupMessage {
    @Attribute(.unique) var id: UUID
    var groupID: UUID
    var speakerID: UUID?
    var speakerName: String
    var role: String
    var text: String
    var createdAt: Date
    var mentionedIDs: [UUID]
    var replyToID: UUID?
    var notificationAt: Date?
    init(groupID: UUID, role: String, text: String, speakerID: UUID? = nil, speakerName: String = "我", mentionedIDs: [UUID] = [], replyToID: UUID? = nil) {
        id = UUID(); self.groupID = groupID; self.role = role; self.text = text
        self.speakerID = speakerID; self.speakerName = speakerName; self.mentionedIDs = mentionedIDs
        self.replyToID = replyToID; createdAt = .now
    }
}

@Model final class GroupPerspective {
    @Attribute(.unique) var id: UUID
    var groupID: UUID
    var characterID: UUID
    var summary: String
    var updatedAt: Date
    init(groupID: UUID, characterID: UUID) {
        id = UUID(); self.groupID = groupID; self.characterID = characterID; summary = ""; updatedAt = .now
    }
}

@MainActor enum GroupStore {
    static func validate(name: String, members: [LumiCharacter]) throws {
        let names = members.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              (2...6).contains(members.count), Set(members.map(\.id)).count == members.count,
              Set(names).count == members.count, names.allSatisfy({ !$0.isEmpty && !["我", "用户", "user", "system", "assistant"].contains($0.lowercased()) }) else { throw GroupError.members }
    }
    static func delete(_ group: GroupChat, context: ModelContext) throws {
        let id = group.id
        ChatSessions.shared.removeGroup(id)
        let messages = try context.fetch(FetchDescriptor<GroupMessage>(predicate: #Predicate { $0.groupID == id }))
        LocalNotificationDriver().remove(messages.filter { $0.notificationAt != nil }.map { "lumi.greeting." + $0.id.uuidString })
        for message in messages { context.delete(message) }
        for perspective in try context.fetch(FetchDescriptor<GroupPerspective>(predicate: #Predicate { $0.groupID == id })) { context.delete(perspective) }
        context.delete(group); try context.save(); ChatReadState.shared.remove(id)
    }
    static func privateContext(characterID: UUID, context: ModelContext) throws -> String {
        let groups = try context.fetch(FetchDescriptor<GroupChat>()).filter { $0.sharesMemory && $0.memberIDs.contains(characterID) }
        let ids = Set(groups.map(\.id))
        let summaries = try context.fetch(FetchDescriptor<GroupPerspective>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            .filter { $0.characterID == characterID && ids.contains($0.groupID) }.prefix(3)
        return summaries.map { "群聊回忆（与私聊分开）：" + PromptBuilder.clip($0.summary, budget: 500) }.joined(separator: "\n")
    }
}

enum GroupError: LocalizedError, Equatable {
    case members, format, budget
    var errorDescription: String? {
        switch self {
        case .members: String(localized: "请选择 2–6 位名字不同的好友，并填写 40 字以内的群名。", locale: AppLocale.current)
        case .format: String(localized: "群消息格式不正确，请重试。", locale: AppLocale.current)
        case .budget: String(localized: "自动闲聊已达到用量上限，已停止。", locale: AppLocale.current)
        }
    }
}
