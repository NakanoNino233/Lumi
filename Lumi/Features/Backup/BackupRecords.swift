import Foundation
import SwiftData

// Explicit versioned records: Keychain values and runtime permissions are never encoded.
struct BackupLumiCharacter: Codable, Sendable {
    var id: UUID
    var name: String
    var personaPrompt: String
    var createdAt: Date
    var isBuiltIn: Bool
    var avatarData: Data?
    var portraitData: Data?
    var speechStyle: String
    var taboos: String
    var backgroundStory: String
    var firstGreeting: String
    var affection: Int
    var stageIndex: Int
    var familiarThreshold: Int
    var closeThreshold: Int
    var partnerThreshold: Int
    var affectionDay: String
    var dailyGain: Int
    var dailyLoss: Int
    var lastAffectionAt: Date?
    var mood: String
    var lastMemeAt: Date?
    var pinnedAt: Date?
    var lastMomentAt: Date?
    @MainActor init(_ value: LumiCharacter) {
        id = value.id
        name = value.name
        personaPrompt = value.personaPrompt
        createdAt = value.createdAt
        isBuiltIn = value.isBuiltIn
        avatarData = value.avatarData
        portraitData = value.portraitData
        speechStyle = value.speechStyle
        taboos = value.taboos
        backgroundStory = value.backgroundStory
        firstGreeting = value.firstGreeting
        affection = value.affection
        stageIndex = value.stageIndex
        familiarThreshold = value.familiarThreshold
        closeThreshold = value.closeThreshold
        partnerThreshold = value.partnerThreshold
        affectionDay = value.affectionDay
        dailyGain = value.dailyGain
        dailyLoss = value.dailyLoss
        lastAffectionAt = value.lastAffectionAt
        mood = value.mood
        lastMemeAt = value.lastMemeAt
        pinnedAt = value.pinnedAt
        lastMomentAt = value.lastMomentAt
    }
    @MainActor func apply(to value: LumiCharacter) {
        value.id = id
        value.name = name
        value.personaPrompt = personaPrompt
        value.createdAt = createdAt
        value.isBuiltIn = isBuiltIn
        value.avatarData = avatarData
        value.portraitData = portraitData
        value.speechStyle = speechStyle
        value.taboos = taboos
        value.backgroundStory = backgroundStory
        value.firstGreeting = firstGreeting
        value.affection = affection
        value.stageIndex = stageIndex
        value.familiarThreshold = familiarThreshold
        value.closeThreshold = closeThreshold
        value.partnerThreshold = partnerThreshold
        value.affectionDay = affectionDay
        value.dailyGain = dailyGain
        value.dailyLoss = dailyLoss
        value.lastAffectionAt = lastAffectionAt
        value.mood = mood
        value.lastMemeAt = lastMemeAt
        value.pinnedAt = pinnedAt
        value.lastMomentAt = lastMomentAt
    }
    @MainActor func make() throws -> LumiCharacter {
        let value = LumiCharacter()
        apply(to: value); return value
    }
}
struct BackupConversation: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var title: String
    var createdAt: Date
    var lastMessageAt: Date
    @MainActor init(_ value: Conversation) {
        id = value.id
        characterID = value.characterID
        title = value.title
        createdAt = value.createdAt
        lastMessageAt = value.lastMessageAt
    }
    @MainActor func apply(to value: Conversation) {
        value.id = id
        value.characterID = characterID
        value.title = title
        value.createdAt = createdAt
        value.lastMessageAt = lastMessageAt
    }
    @MainActor func make() throws -> Conversation {
        let value = Conversation(characterID: characterID, title: title)
        apply(to: value); return value
    }
}
struct BackupMessage: Codable, Sendable {
    var id: UUID
    var conversationID: UUID
    var role: String
    var content: String
    var createdAt: Date
    var statusRaw: String
    var replyToID: UUID?
    var recalledMemoryIDs: [UUID]
    var recalledMemoryTexts: [String]
    var isProactive: Bool
    var externalEventID: String?
    var mountedSkillIDs: [UUID]
    var memeData: Data?
    var attachmentData: Data?
    var toolActivityData: Data?
    var voiceData: Data?
    var voiceDuration: Double?
    @MainActor init(_ value: Message) {
        id = value.id
        conversationID = value.conversationID
        role = value.role
        content = value.content
        createdAt = value.createdAt
        statusRaw = value.statusRaw
        replyToID = value.replyToID
        recalledMemoryIDs = value.recalledMemoryIDs
        recalledMemoryTexts = value.recalledMemoryTexts
        isProactive = value.isProactive
        externalEventID = value.externalEventID
        mountedSkillIDs = value.mountedSkillIDs
        memeData = value.memeData
        attachmentData = value.attachmentData
        toolActivityData = value.toolActivityData
        voiceData = value.voiceData; voiceDuration = value.voiceDuration
    }
    @MainActor func apply(to value: Message) {
        value.id = id
        value.conversationID = conversationID
        value.role = role
        value.content = content
        value.createdAt = createdAt
        value.statusRaw = statusRaw
        value.replyToID = replyToID
        value.recalledMemoryIDs = recalledMemoryIDs
        value.recalledMemoryTexts = recalledMemoryTexts
        value.isProactive = isProactive
        value.externalEventID = externalEventID
        value.mountedSkillIDs = mountedSkillIDs
        value.memeData = memeData
        value.attachmentData = attachmentData
        value.toolActivityData = toolActivityData
        value.voiceData = voiceData; value.voiceDuration = voiceDuration ?? 0
    }
    @MainActor func make() throws -> Message {
        let value = Message(conversationID: conversationID, role: role, content: content)
        apply(to: value); return value
    }
}
struct BackupMemoryFact: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var category: String
    var text: String
    var importance: Int
    var sourceMessageID: UUID?
    var createdAt: Date
    var lastMentionedAt: Date?
    var pinOrder: Int
    @MainActor init(_ value: MemoryFact) {
        id = value.id
        characterID = value.characterID
        category = value.category
        text = value.text
        importance = value.importance
        sourceMessageID = value.sourceMessageID
        createdAt = value.createdAt
        lastMentionedAt = value.lastMentionedAt
        pinOrder = value.pinOrder
    }
    @MainActor func apply(to value: MemoryFact) {
        value.id = id
        value.characterID = characterID
        value.category = category
        value.text = text
        value.importance = importance
        value.sourceMessageID = sourceMessageID
        value.createdAt = createdAt
        value.lastMentionedAt = lastMentionedAt
        value.pinOrder = pinOrder
    }
    @MainActor func make() throws -> MemoryFact {
        let value = MemoryFact(characterID: characterID, category: category, text: text)
        apply(to: value); return value
    }
}
struct BackupUserProfile: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var summary: String
    var compactedBefore: Date?
    var lastExtractedAt: Date?
    var updatedAt: Date
    @MainActor init(_ value: UserProfile) {
        id = value.id
        characterID = value.characterID
        summary = value.summary
        compactedBefore = value.compactedBefore
        lastExtractedAt = value.lastExtractedAt
        updatedAt = value.updatedAt
    }
    @MainActor func apply(to value: UserProfile) {
        value.id = id
        value.characterID = characterID
        value.summary = summary
        value.compactedBefore = compactedBefore
        value.lastExtractedAt = lastExtractedAt
        value.updatedAt = updatedAt
    }
    @MainActor func make() throws -> UserProfile {
        let value = UserProfile(characterID: characterID)
        apply(to: value); return value
    }
}
struct BackupAnniversary: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var title: String
    var date: Date
    var repeatsYearly: Bool
    @MainActor init(_ value: Anniversary) {
        id = value.id
        characterID = value.characterID
        title = value.title
        date = value.date
        repeatsYearly = value.repeatsYearly
    }
    @MainActor func apply(to value: Anniversary) {
        value.id = id
        value.characterID = characterID
        value.title = title
        value.date = date
        value.repeatsYearly = repeatsYearly
    }
    @MainActor func make() throws -> Anniversary {
        let value = Anniversary(characterID: characterID, title: title, date: date)
        apply(to: value); return value
    }
}
struct BackupDiaryEntry: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var day: String
    var content: String
    var updatedAt: Date
    @MainActor init(_ value: DiaryEntry) {
        id = value.id
        characterID = value.characterID
        day = value.day
        content = value.content
        updatedAt = value.updatedAt
    }
    @MainActor func apply(to value: DiaryEntry) {
        value.id = id
        value.characterID = characterID
        value.day = day
        value.content = content
        value.updatedAt = updatedAt
    }
    @MainActor func make() throws -> DiaryEntry {
        let value = DiaryEntry(characterID: characterID, day: day, content: content)
        apply(to: value); return value
    }
}
struct BackupAffectionAward: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var userMessageID: UUID
    var fingerprint: String
    var createdAt: Date
    var delta: Int
    @MainActor init(_ value: AffectionAward) {
        id = value.id
        characterID = value.characterID
        userMessageID = value.userMessageID
        fingerprint = value.fingerprint
        createdAt = value.createdAt
        delta = value.delta
    }
    @MainActor func apply(to value: AffectionAward) {
        value.id = id
        value.characterID = characterID
        value.userMessageID = userMessageID
        value.fingerprint = fingerprint
        value.createdAt = createdAt
        value.delta = delta
    }
    @MainActor func make() throws -> AffectionAward {
        let value = AffectionAward(characterID: characterID, userMessageID: userMessageID, fingerprint: fingerprint, delta: delta, createdAt: createdAt)
        apply(to: value); return value
    }
}
struct BackupProviderConfig: Codable, Sendable {
    var id: UUID
    var name: String
    var baseURL: String
    var modelName: String
    var supportsTools: Bool
    var supportsVision: Bool
    var defaultsVersion: Int?
    @MainActor init(_ value: ProviderConfig) {
        id = value.id
        name = value.name
        baseURL = value.baseURL
        modelName = value.modelName
        supportsTools = value.supportsTools
        supportsVision = value.supportsVision
        defaultsVersion = value.defaultsVersion
    }
    @MainActor func apply(to value: ProviderConfig) {
        value.id = id
        value.name = name
        value.baseURL = baseURL
        value.modelName = modelName
        value.supportsTools = supportsTools
        value.supportsVision = supportsVision
        value.defaultsVersion = defaultsVersion
    }
    @MainActor func make() throws -> ProviderConfig {
        let value = ProviderConfig()
        apply(to: value); return value
    }
}
struct BackupMemePack: Codable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var license: String
    var source: String
    var enabled: Bool
    var createdAt: Date
    @MainActor init(_ value: MemePack) {
        id = value.id
        name = value.name
        summary = value.summary
        license = value.license
        source = value.source
        enabled = value.enabled
        createdAt = value.createdAt
    }
    @MainActor func apply(to value: MemePack) {
        value.id = id
        value.name = name
        value.summary = summary
        value.license = license
        value.source = source
        value.enabled = enabled
        value.createdAt = createdAt
    }
    @MainActor func make() throws -> MemePack {
        let value = MemePack(name: name)
        apply(to: value); return value
    }
}
struct BackupMeme: Codable, Sendable {
    var id: UUID
    var packID: UUID
    var fileName: String
    var caption: String
    var keywords: String
    var mood: String
    var usageCount: Int
    var source: String
    var license: String
    @MainActor init(_ value: Meme) {
        id = value.id
        packID = value.packID
        fileName = value.fileName
        caption = value.caption
        keywords = value.keywords
        mood = value.mood
        usageCount = value.usageCount
        source = value.source
        license = value.license
    }
    @MainActor func apply(to value: Meme) {
        value.id = id
        value.packID = packID
        value.fileName = fileName
        value.caption = caption
        value.keywords = keywords
        value.mood = mood
        value.usageCount = usageCount
        value.source = source
        value.license = license
    }
    @MainActor func make() throws -> Meme {
        let value = Meme(packID: packID, fileName: fileName, caption: caption)
        apply(to: value); return value
    }
}
struct BackupTokenUsageRecord: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var model: String
    var ownersJSON: String
    var functionRaw: String?
    var input: Int64
    var output: Int64
    var cached: Int64
    var hasUsage: Bool
    var hasCacheUsage: Bool
    @MainActor init(_ value: TokenUsageRecord) {
        id = value.id
        createdAt = value.createdAt
        model = value.model
        ownersJSON = value.ownersJSON
        functionRaw = value.functionRaw
        input = value.input
        output = value.output
        cached = value.cached
        hasUsage = value.hasUsage
        hasCacheUsage = value.hasCacheUsage
    }
    @MainActor func apply(to value: TokenUsageRecord) {
        value.id = id
        value.createdAt = createdAt
        value.model = model
        value.ownersJSON = ownersJSON
        value.functionRaw = functionRaw
        value.input = input
        value.output = output
        value.cached = cached
        value.hasUsage = hasUsage
        value.hasCacheUsage = hasCacheUsage
    }
    @MainActor func make() throws -> TokenUsageRecord {
        let value = TokenUsageRecord(id: id, endpoint: ProviderEndpoint(baseURL: "https://example.invalid", model: model))
        apply(to: value); return value
    }
}
struct BackupGroupChat: Codable, Sendable {
    var id: UUID
    var name: String
    var announcement: String
    var scene: String
    var memberIDs: [UUID]
    var createdAt: Date
    var lastMessageAt: Date
    var pinnedAt: Date?
    var independentReplies: Bool
    var sharesMemory: Bool
    var automaticChat: Bool
    var automaticRounds: Int
    var mentionNotifications: Bool
    var settingsData: Data?
    var relationshipData: Data?
    @MainActor init(_ value: GroupChat) {
        id = value.id
        name = value.name
        announcement = value.announcement
        scene = value.scene
        memberIDs = value.memberIDs
        createdAt = value.createdAt
        lastMessageAt = value.lastMessageAt
        pinnedAt = value.pinnedAt
        independentReplies = value.independentReplies
        sharesMemory = value.sharesMemory
        automaticChat = value.automaticChat
        automaticRounds = value.automaticRounds
        mentionNotifications = value.mentionNotifications
        settingsData = value.settingsData
        relationshipData = value.relationshipData
    }
    @MainActor func apply(to value: GroupChat) {
        value.id = id
        value.name = name
        value.announcement = announcement
        value.scene = scene
        value.memberIDs = memberIDs
        value.createdAt = createdAt
        value.lastMessageAt = lastMessageAt
        value.pinnedAt = pinnedAt
        value.independentReplies = independentReplies
        value.sharesMemory = sharesMemory
        value.automaticChat = automaticChat
        value.automaticRounds = automaticRounds
        value.mentionNotifications = mentionNotifications
        value.settingsData = settingsData
        value.relationshipData = relationshipData
    }
    @MainActor func make() throws -> GroupChat {
        let value = GroupChat(name: name, memberIDs: memberIDs)
        apply(to: value); return value
    }
}
struct BackupGroupMessage: Codable, Sendable {
    var id: UUID
    var groupID: UUID
    var speakerID: UUID?
    var speakerName: String
    var role: String
    var text: String
    var createdAt: Date
    var mentionedIDs: [UUID]
    var replyToID: UUID?
    var notificationAt: Date?
    @MainActor init(_ value: GroupMessage) {
        id = value.id
        groupID = value.groupID
        speakerID = value.speakerID
        speakerName = value.speakerName
        role = value.role
        text = value.text
        createdAt = value.createdAt
        mentionedIDs = value.mentionedIDs
        replyToID = value.replyToID
        notificationAt = value.notificationAt
    }
    @MainActor func apply(to value: GroupMessage) {
        value.id = id
        value.groupID = groupID
        value.speakerID = speakerID
        value.speakerName = speakerName
        value.role = role
        value.text = text
        value.createdAt = createdAt
        value.mentionedIDs = mentionedIDs
        value.replyToID = replyToID
        value.notificationAt = notificationAt
    }
    @MainActor func make() throws -> GroupMessage {
        let value = GroupMessage(groupID: groupID, role: role, text: text)
        apply(to: value); return value
    }
}
struct BackupGroupPerspective: Codable, Sendable {
    var id: UUID
    var groupID: UUID
    var characterID: UUID
    var summary: String
    var updatedAt: Date
    @MainActor init(_ value: GroupPerspective) {
        id = value.id
        groupID = value.groupID
        characterID = value.characterID
        summary = value.summary
        updatedAt = value.updatedAt
    }
    @MainActor func apply(to value: GroupPerspective) {
        value.id = id
        value.groupID = groupID
        value.characterID = characterID
        value.summary = summary
        value.updatedAt = updatedAt
    }
    @MainActor func make() throws -> GroupPerspective {
        let value = GroupPerspective(groupID: groupID, characterID: characterID)
        apply(to: value); return value
    }
}
struct BackupMomentPost: Codable, Sendable {
    var id: UUID
    var content: String
    var createdAt: Date
    var liked: Bool
    var commentData: Data?
    var imagesData: Data?
    var authorID: UUID?
    var authorName: String?
    var reactionData: Data?
    @MainActor init(_ value: MomentPost) {
        id = value.id
        content = value.content
        createdAt = value.createdAt
        liked = value.liked
        commentData = value.commentData
        imagesData = value.imagesData
        authorID = value.authorID
        authorName = value.authorName
        reactionData = value.reactionData
    }
    @MainActor func apply(to value: MomentPost) {
        value.id = id
        value.content = content
        value.createdAt = createdAt
        value.liked = liked
        value.commentData = commentData
        value.imagesData = imagesData
        value.authorID = authorID
        value.authorName = authorName
        value.reactionData = reactionData
    }
    @MainActor func make() throws -> MomentPost {
        let value = MomentPost(content: content)
        apply(to: value); return value
    }
}
struct BackupScheduledGreeting: Codable, Sendable {
    var id: UUID
    var characterID: UUID
    var fireDate: Date
    var text: String
    var scenario: String
    var stateRaw: String
    var isClosure: Bool
    var createdAt: Date
    var importedAt: Date?
    var replyNoticeID: UUID?
    @MainActor init(_ value: ScheduledGreeting) {
        id = value.id
        characterID = value.characterID
        fireDate = value.fireDate
        text = value.text
        scenario = value.scenario
        stateRaw = value.stateRaw
        isClosure = value.isClosure
        createdAt = value.createdAt
        importedAt = value.importedAt
        replyNoticeID = value.replyNoticeID
    }
    @MainActor func apply(to value: ScheduledGreeting) {
        value.id = id
        value.characterID = characterID
        value.fireDate = fireDate
        value.text = text
        value.scenario = scenario
        value.stateRaw = stateRaw
        value.isClosure = isClosure
        value.createdAt = createdAt
        value.importedAt = importedAt
        value.replyNoticeID = replyNoticeID
    }
    @MainActor func make() throws -> ScheduledGreeting {
        let value = ScheduledGreeting(characterID: characterID, fireDate: fireDate, text: text, scenario: scenario)
        apply(to: value); return value
    }
}
struct BackupMarketInstallation: Codable, Sendable {
    var id: String
    var sourceID: String
    var itemData: Data
    var packageData: Data
    var previousItemData: Data?
    var previousPackageData: Data?
    var targetIDs: [UUID]
    var baselineTheme: Data?
    var installedAt: Date
    @MainActor init(_ value: MarketInstallation) {
        id = value.id
        sourceID = value.sourceID
        itemData = value.itemData
        packageData = value.packageData
        previousItemData = value.previousItemData
        previousPackageData = value.previousPackageData
        targetIDs = value.targetIDs
        baselineTheme = value.baselineTheme
        installedAt = value.installedAt
    }
    @MainActor func apply(to value: MarketInstallation) {
        value.id = id
        value.sourceID = sourceID
        value.itemData = itemData
        value.packageData = packageData
        value.previousItemData = previousItemData
        value.previousPackageData = previousPackageData
        value.targetIDs = targetIDs
        value.baselineTheme = baselineTheme
        value.installedAt = installedAt
    }
    @MainActor func make() throws -> MarketInstallation {
        let value = try MarketInstallation(sourceID: sourceID, item: JSONDecoder().decode(MarketItem.self, from: itemData), data: packageData)
        apply(to: value); return value
    }
}
struct BackupInstalledSkill: Codable, Sendable {
    var id: UUID
    var name: String
    var summary: String
    var instructions: String
    var permissions: [String]
    var tools: [String]
    var enabled: Bool
    var createdAt: Date
    var builtinKey: String?
    @MainActor init(_ value: InstalledSkill) {
        id = value.id
        name = value.name
        summary = value.summary
        instructions = value.instructions
        permissions = value.permissions
        tools = value.tools
        enabled = value.enabled
        createdAt = value.createdAt
        builtinKey = value.builtinKey
    }
    @MainActor func apply(to value: InstalledSkill) {
        value.id = id
        value.name = name
        value.summary = summary
        value.instructions = instructions
        value.permissions = permissions
        value.tools = tools
        value.enabled = enabled
        value.createdAt = createdAt
        value.builtinKey = builtinKey
    }
    @MainActor func make() throws -> InstalledSkill {
        let value = InstalledSkill(SkillDocument(name: name, description: summary, body: instructions, permissions: permissions, tools: tools))
        apply(to: value); return value
    }
}

struct LumiBackup: Codable, Sendable {
    var version = 1
    var createdAt = Date()
    var preferences: [String: BackupPreference] = [:]
    var momentCoverData: Data?
    var personalProfile: PersonalProfile?
    var files: [String: String] = [:]
    var lumiCharacters: [BackupLumiCharacter] = []
    var conversations: [BackupConversation] = []
    var messages: [BackupMessage] = []
    var memoryFacts: [BackupMemoryFact] = []
    var userProfiles: [BackupUserProfile] = []
    var anniversarys: [BackupAnniversary] = []
    var diaryEntrys: [BackupDiaryEntry] = []
    var affectionAwards: [BackupAffectionAward] = []
    var providerConfigs: [BackupProviderConfig] = []
    var memePacks: [BackupMemePack] = []
    var memes: [BackupMeme] = []
    var tokenUsageRecords: [BackupTokenUsageRecord] = []
    var groupChats: [BackupGroupChat] = []
    var groupMessages: [BackupGroupMessage] = []
    var groupPerspectives: [BackupGroupPerspective] = []
    var momentPosts: [BackupMomentPost] = []
    var scheduledGreetings: [BackupScheduledGreeting] = []
    var marketInstallations: [BackupMarketInstallation] = []
    var installedSkills: [BackupInstalledSkill] = []
    @MainActor static func capture(_ context: ModelContext, defaults: UserDefaults) throws -> Self {
        var backup = Self()
        backup.lumiCharacters = try context.fetch(FetchDescriptor<LumiCharacter>()).map(BackupLumiCharacter.init)
        backup.conversations = try context.fetch(FetchDescriptor<Conversation>()).map(BackupConversation.init)
        backup.messages = try context.fetch(FetchDescriptor<Message>()).map(BackupMessage.init)
        backup.memoryFacts = try context.fetch(FetchDescriptor<MemoryFact>()).map(BackupMemoryFact.init)
        backup.userProfiles = try context.fetch(FetchDescriptor<UserProfile>()).map(BackupUserProfile.init)
        backup.anniversarys = try context.fetch(FetchDescriptor<Anniversary>()).map(BackupAnniversary.init)
        backup.diaryEntrys = try context.fetch(FetchDescriptor<DiaryEntry>()).map(BackupDiaryEntry.init)
        backup.affectionAwards = try context.fetch(FetchDescriptor<AffectionAward>()).map(BackupAffectionAward.init)
        backup.providerConfigs = try context.fetch(FetchDescriptor<ProviderConfig>()).map(BackupProviderConfig.init)
        backup.memePacks = try context.fetch(FetchDescriptor<MemePack>()).map(BackupMemePack.init)
        backup.memes = try context.fetch(FetchDescriptor<Meme>()).map(BackupMeme.init)
        backup.tokenUsageRecords = try context.fetch(FetchDescriptor<TokenUsageRecord>()).map(BackupTokenUsageRecord.init)
        backup.groupChats = try context.fetch(FetchDescriptor<GroupChat>()).map(BackupGroupChat.init)
        backup.groupMessages = try context.fetch(FetchDescriptor<GroupMessage>()).map(BackupGroupMessage.init)
        backup.groupPerspectives = try context.fetch(FetchDescriptor<GroupPerspective>()).map(BackupGroupPerspective.init)
        backup.momentPosts = try context.fetch(FetchDescriptor<MomentPost>()).map(BackupMomentPost.init)
        backup.scheduledGreetings = try context.fetch(FetchDescriptor<ScheduledGreeting>()).map(BackupScheduledGreeting.init)
        backup.marketInstallations = try context.fetch(FetchDescriptor<MarketInstallation>()).map(BackupMarketInstallation.init)
        backup.installedSkills = try context.fetch(FetchDescriptor<InstalledSkill>()).map(BackupInstalledSkill.init)
        backup.preferences = BackupPreference.capture(defaults)
        backup.momentCoverData = defaults.data(forKey: MomentsPreferences.coverKey)
        if defaults.data(forKey: PersonalProfile.storageKey) != nil { backup.personalProfile = PersonalProfile.load(defaults: defaults) }
        return backup
    }
    @MainActor func restore(context: ModelContext, replacing: Bool) throws {
        let oldLumiCharacter = try context.fetch(FetchDescriptor<LumiCharacter>())
        let byIDLumiCharacter = Dictionary(uniqueKeysWithValues: oldLumiCharacter.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(lumiCharacters.map(\.id))
            for value in oldLumiCharacter where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in lumiCharacters {
            if let existing = byIDLumiCharacter[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldConversation = try context.fetch(FetchDescriptor<Conversation>())
        let byIDConversation = Dictionary(uniqueKeysWithValues: oldConversation.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(conversations.map(\.id))
            for value in oldConversation where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in conversations {
            if let existing = byIDConversation[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMessage = try context.fetch(FetchDescriptor<Message>())
        let byIDMessage = Dictionary(uniqueKeysWithValues: oldMessage.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(messages.map(\.id))
            for value in oldMessage where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in messages {
            if let existing = byIDMessage[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMemoryFact = try context.fetch(FetchDescriptor<MemoryFact>())
        let byIDMemoryFact = Dictionary(uniqueKeysWithValues: oldMemoryFact.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(memoryFacts.map(\.id))
            for value in oldMemoryFact where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in memoryFacts {
            if let existing = byIDMemoryFact[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldUserProfile = try context.fetch(FetchDescriptor<UserProfile>())
        let byIDUserProfile = Dictionary(uniqueKeysWithValues: oldUserProfile.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(userProfiles.map(\.id))
            for value in oldUserProfile where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in userProfiles {
            if let existing = byIDUserProfile[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldAnniversary = try context.fetch(FetchDescriptor<Anniversary>())
        let byIDAnniversary = Dictionary(uniqueKeysWithValues: oldAnniversary.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(anniversarys.map(\.id))
            for value in oldAnniversary where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in anniversarys {
            if let existing = byIDAnniversary[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldDiaryEntry = try context.fetch(FetchDescriptor<DiaryEntry>())
        let byIDDiaryEntry = Dictionary(uniqueKeysWithValues: oldDiaryEntry.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(diaryEntrys.map(\.id))
            for value in oldDiaryEntry where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in diaryEntrys {
            if let existing = byIDDiaryEntry[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldAffectionAward = try context.fetch(FetchDescriptor<AffectionAward>())
        let byIDAffectionAward = Dictionary(uniqueKeysWithValues: oldAffectionAward.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(affectionAwards.map(\.id))
            for value in oldAffectionAward where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in affectionAwards {
            if let existing = byIDAffectionAward[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldProviderConfig = try context.fetch(FetchDescriptor<ProviderConfig>())
        let byIDProviderConfig = Dictionary(uniqueKeysWithValues: oldProviderConfig.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(providerConfigs.map(\.id))
            for value in oldProviderConfig where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in providerConfigs {
            if let existing = byIDProviderConfig[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMemePack = try context.fetch(FetchDescriptor<MemePack>())
        let byIDMemePack = Dictionary(uniqueKeysWithValues: oldMemePack.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(memePacks.map(\.id))
            for value in oldMemePack where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in memePacks {
            if let existing = byIDMemePack[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMeme = try context.fetch(FetchDescriptor<Meme>())
        let byIDMeme = Dictionary(uniqueKeysWithValues: oldMeme.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(memes.map(\.id))
            for value in oldMeme where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in memes {
            if let existing = byIDMeme[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldTokenUsageRecord = try context.fetch(FetchDescriptor<TokenUsageRecord>())
        let byIDTokenUsageRecord = Dictionary(uniqueKeysWithValues: oldTokenUsageRecord.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(tokenUsageRecords.map(\.id))
            for value in oldTokenUsageRecord where !incoming.contains(value.id) { context.delete(value) }
        }
        guard lumiCharacters.allSatisfy({ (0...100).contains($0.affection) && (0...3).contains($0.stageIndex) &&
            (0...6).contains($0.dailyGain) && (0...6).contains($0.dailyLoss) &&
            (0...100).contains($0.familiarThreshold) && (0...100).contains($0.closeThreshold) && (0...100).contains($0.partnerThreshold) }),
            memes.allSatisfy({ (0...1_000_000_000).contains($0.usageCount) }),
            memoryFacts.allSatisfy({ (1...5).contains($0.importance) && (0...1_000_000).contains($0.pinOrder) }),
            preferences.allSatisfy({ $0.value.valid(for: $0.key) }) else { throw BackupError.invalid }
        for receipt in marketInstallations {
            guard let item = try? JSONDecoder().decode(MarketItem.self, from: receipt.itemData),
                  receipt.id == receipt.sourceID + "/" + item.id else { throw BackupError.invalid }
            try item.verify(receipt.packageData)
            guard (receipt.previousItemData == nil) == (receipt.previousPackageData == nil) else { throw BackupError.invalid }
            if let data = receipt.previousItemData, let bytes = receipt.previousPackageData {
                try JSONDecoder().decode(MarketItem.self, from: data).verify(bytes)
            }
        }
        for record in tokenUsageRecords {
            if let existing = byIDTokenUsageRecord[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldGroupChat = try context.fetch(FetchDescriptor<GroupChat>())
        let byIDGroupChat = Dictionary(uniqueKeysWithValues: oldGroupChat.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(groupChats.map(\.id))
            for value in oldGroupChat where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in groupChats {
            if let existing = byIDGroupChat[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldGroupMessage = try context.fetch(FetchDescriptor<GroupMessage>())
        let byIDGroupMessage = Dictionary(uniqueKeysWithValues: oldGroupMessage.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(groupMessages.map(\.id))
            for value in oldGroupMessage where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in groupMessages {
            if let existing = byIDGroupMessage[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldGroupPerspective = try context.fetch(FetchDescriptor<GroupPerspective>())
        let byIDGroupPerspective = Dictionary(uniqueKeysWithValues: oldGroupPerspective.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(groupPerspectives.map(\.id))
            for value in oldGroupPerspective where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in groupPerspectives {
            if let existing = byIDGroupPerspective[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMomentPost = try context.fetch(FetchDescriptor<MomentPost>())
        let byIDMomentPost = Dictionary(uniqueKeysWithValues: oldMomentPost.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(momentPosts.map(\.id))
            for value in oldMomentPost where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in momentPosts {
            if let existing = byIDMomentPost[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldScheduledGreeting = try context.fetch(FetchDescriptor<ScheduledGreeting>())
        let byIDScheduledGreeting = Dictionary(uniqueKeysWithValues: oldScheduledGreeting.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(scheduledGreetings.map(\.id))
            for value in oldScheduledGreeting where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in scheduledGreetings {
            if let existing = byIDScheduledGreeting[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldMarketInstallation = try context.fetch(FetchDescriptor<MarketInstallation>())
        let byIDMarketInstallation = Dictionary(uniqueKeysWithValues: oldMarketInstallation.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(marketInstallations.map(\.id))
            for value in oldMarketInstallation where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in marketInstallations {
            if let existing = byIDMarketInstallation[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
        let oldInstalledSkill = try context.fetch(FetchDescriptor<InstalledSkill>())
        let byIDInstalledSkill = Dictionary(uniqueKeysWithValues: oldInstalledSkill.map { ($0.id, $0) })
        if replacing {
            let incoming = Set(installedSkills.map(\.id))
            for value in oldInstalledSkill where !incoming.contains(value.id) { context.delete(value) }
        }
        for record in installedSkills {
            if let existing = byIDInstalledSkill[record.id] { if replacing { record.apply(to: existing) } }
            else { context.insert(try record.make()) }
        }
    }
    func validate() throws {
        guard version == 1 else { throw BackupError.version }
        var count = 0
        guard Set(lumiCharacters.map(\.id)).count == lumiCharacters.count else { throw BackupError.invalid }
        count += lumiCharacters.count
        guard Set(conversations.map(\.id)).count == conversations.count else { throw BackupError.invalid }
        count += conversations.count
        guard Set(messages.map(\.id)).count == messages.count else { throw BackupError.invalid }
        count += messages.count
        guard Set(memoryFacts.map(\.id)).count == memoryFacts.count else { throw BackupError.invalid }
        count += memoryFacts.count
        guard Set(userProfiles.map(\.id)).count == userProfiles.count else { throw BackupError.invalid }
        count += userProfiles.count
        guard Set(anniversarys.map(\.id)).count == anniversarys.count else { throw BackupError.invalid }
        count += anniversarys.count
        guard Set(diaryEntrys.map(\.id)).count == diaryEntrys.count else { throw BackupError.invalid }
        count += diaryEntrys.count
        guard Set(affectionAwards.map(\.id)).count == affectionAwards.count else { throw BackupError.invalid }
        count += affectionAwards.count
        guard Set(providerConfigs.map(\.id)).count == providerConfigs.count else { throw BackupError.invalid }
        count += providerConfigs.count
        guard Set(memePacks.map(\.id)).count == memePacks.count else { throw BackupError.invalid }
        count += memePacks.count
        guard Set(memes.map(\.id)).count == memes.count else { throw BackupError.invalid }
        count += memes.count
        guard Set(tokenUsageRecords.map(\.id)).count == tokenUsageRecords.count else { throw BackupError.invalid }
        count += tokenUsageRecords.count
        guard Set(groupChats.map(\.id)).count == groupChats.count else { throw BackupError.invalid }
        count += groupChats.count
        guard Set(groupMessages.map(\.id)).count == groupMessages.count else { throw BackupError.invalid }
        count += groupMessages.count
        guard Set(groupPerspectives.map(\.id)).count == groupPerspectives.count else { throw BackupError.invalid }
        count += groupPerspectives.count
        guard Set(momentPosts.map(\.id)).count == momentPosts.count else { throw BackupError.invalid }
        count += momentPosts.count
        guard Set(scheduledGreetings.map(\.id)).count == scheduledGreetings.count else { throw BackupError.invalid }
        count += scheduledGreetings.count
        guard Set(marketInstallations.map(\.id)).count == marketInstallations.count else { throw BackupError.invalid }
        count += marketInstallations.count
        guard Set(installedSkills.map(\.id)).count == installedSkills.count else { throw BackupError.invalid }
        count += installedSkills.count
        guard count <= 100_000, preferences.keys.allSatisfy(BackupPreference.keys.contains) else { throw BackupError.limit }
        guard messages.allSatisfy({ message in
            let duration = message.voiceDuration ?? 0
            return duration.isFinite && (0...60).contains(duration) &&
                (message.voiceData.map { !$0.isEmpty && $0.count <= 5_000_000 && duration > 0 } ?? true)
        }) else { throw BackupError.invalid }
        let characters = Set(lumiCharacters.map(\.id)); let conversations = Set(conversations.map(\.id)); let groups = Set(groupChats.map(\.id)); let packs = Set(memePacks.map(\.id))
        guard self.conversations.allSatisfy({ characters.contains($0.characterID) }), messages.allSatisfy({ conversations.contains($0.conversationID) }),
              memoryFacts.allSatisfy({ characters.contains($0.characterID) }), userProfiles.allSatisfy({ characters.contains($0.characterID) }),
              anniversarys.allSatisfy({ characters.contains($0.characterID) }), diaryEntrys.allSatisfy({ characters.contains($0.characterID) }),
              groupMessages.allSatisfy({ groups.contains($0.groupID) }), groupPerspectives.allSatisfy({ groups.contains($0.groupID) && characters.contains($0.characterID) }),
              groupChats.allSatisfy({ Set($0.memberIDs).count == $0.memberIDs.count && $0.memberIDs.allSatisfy(characters.contains) }),
              memes.allSatisfy({ packs.contains($0.packID) }) else { throw BackupError.invalid }
        if let cover = momentCoverData, !cover.isEmpty {
            guard cover.count <= 10_000_000 else { throw BackupError.limit }
            try MemeArchive.validateImage(cover)
        }
        try personalProfile?.validate()
        for post in momentPosts {
            guard post.authorID.map(characters.contains) ?? true else { throw BackupError.invalid }
            if let data = post.commentData {
                guard let comments = try? JSONDecoder().decode([MomentComment].self, from: data), comments.count <= 100,
                      Set(comments.map(\.id)).count == comments.count,
                      comments.allSatisfy({ $0.text.count <= 500 && ($0.authorID.map(characters.contains) ?? true) }) else { throw BackupError.invalid }
            }
            if let data = post.reactionData {
                guard let reactions = try? JSONDecoder().decode([MomentReaction].self, from: data),
                      Set(reactions.map(\.id)).count == reactions.count,
                      reactions.allSatisfy({ characters.contains($0.id) }) else { throw BackupError.invalid }
            }
        }
        for meme in memes {
            guard !meme.fileName.contains("/"), !meme.fileName.contains("\\"), MemeArchive.imageExtensions.contains((meme.fileName as NSString).pathExtension.lowercased()),
                  files["memes/" + meme.packID.uuidString + "/" + (try MemeArchive.safePath(meme.fileName))] != nil else { throw BackupError.invalid }
        }
        guard lumiCharacters.allSatisfy({ (0...100).contains($0.affection) && (0...3).contains($0.stageIndex) &&
            (0...6).contains($0.dailyGain) && (0...6).contains($0.dailyLoss) &&
            (0...100).contains($0.familiarThreshold) && (0...100).contains($0.closeThreshold) && (0...100).contains($0.partnerThreshold) }),
            memes.allSatisfy({ (0...1_000_000_000).contains($0.usageCount) }),
            memoryFacts.allSatisfy({ (1...5).contains($0.importance) && (0...1_000_000).contains($0.pinOrder) }),
            preferences.allSatisfy({ $0.value.valid(for: $0.key) }) else { throw BackupError.invalid }
        for receipt in marketInstallations {
            guard let item = try? JSONDecoder().decode(MarketItem.self, from: receipt.itemData),
                  receipt.id == receipt.sourceID + "/" + item.id else { throw BackupError.invalid }
            try item.verify(receipt.packageData)
            guard (receipt.previousItemData == nil) == (receipt.previousPackageData == nil) else { throw BackupError.invalid }
            if let data = receipt.previousItemData, let bytes = receipt.previousPackageData {
                try JSONDecoder().decode(MarketItem.self, from: data).verify(bytes)
            }
        }
        for record in tokenUsageRecords { guard record.input >= 0, record.output >= 0, record.cached >= 0, record.cached <= record.input else { throw BackupError.invalid } }
        for skill in installedSkills { guard skill.permissions.allSatisfy(SkillParser.permissionNames.contains), skill.tools.allSatisfy(ToolRegistry.names.contains), skill.instructions.utf8.count <= SkillParser.maximumBytes else { throw BackupError.invalid } }
        for provider in providerConfigs { _ = try ProviderEndpoint(baseURL: provider.baseURL, model: provider.modelName).completionURL() }
    }
}
