import Foundation
import UIKit
import ImageIO
import SwiftData

struct CharacterCard: Codable, Sendable, Equatable {
    var schemaVersion: Int = 1
    var name: String
    var avatar: Data?
    var portrait: Data?
    var personaPrompt: String
    var speechStyle: String
    var taboos: String
    var backgroundStory: String
    var firstGreeting: String

    @MainActor init(_ character: LumiCharacter) {
        name = character.name; avatar = character.avatarData; portrait = character.portraitData
        personaPrompt = character.personaPrompt; speechStyle = character.speechStyle
        taboos = character.taboos; backgroundStory = character.backgroundStory; firstGreeting = character.firstGreeting
    }
    init(name: String, personaPrompt: String, speechStyle: String = "", taboos: String = "", backgroundStory: String = "", firstGreeting: String = "") {
        self.name = name; self.personaPrompt = personaPrompt; self.speechStyle = speechStyle
        self.taboos = taboos; self.backgroundStory = backgroundStory; self.firstGreeting = firstGreeting
    }
    func validated(existingNames: [String], excludingName: String? = nil) throws -> CharacterCard {
        guard schemaVersion == 1 else { throw CharacterCardError.version }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 40, clean.rangeOfCharacter(from: .controlCharacters) == nil, !personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [personaPrompt, speechStyle, taboos, backgroundStory, firstGreeting].allSatisfy({ $0.count <= 12_000 }) else { throw CharacterCardError.fields }
        guard !existingNames.contains(where: { $0 != excludingName && Self.normalized($0) == Self.normalized(clean) }) else { throw CharacterCardError.duplicate }
        var result = self; result.name = clean
        if let avatar { result.avatar = try CharacterImage.normalized(avatar) }
        if let portrait { result.portrait = try CharacterImage.normalized(portrait) }
        return result
    }
    static func decode(_ data: Data, existingNames: [String]) throws -> CharacterCard {
        guard data.count <= 12_000_000 else { throw CharacterCardError.image }
        do { return try JSONDecoder().decode(Self.self, from: data).validated(existingNames: existingNames) }
        catch let error as CharacterCardError { throw error }
        catch { throw CharacterCardError.fields }
    }
    static func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    @MainActor func apply(to character: LumiCharacter) {
        character.name = name; character.avatarData = avatar; character.portraitData = portrait
        character.personaPrompt = personaPrompt; character.speechStyle = speechStyle
        character.taboos = taboos; character.backgroundStory = backgroundStory; character.firstGreeting = firstGreeting
    }
}

enum CharacterCardError: Error, LocalizedError {
    case version, fields, duplicate, image
    var errorDescription: String? {
        switch self {
        case .version: String(localized: "此好友卡版本暂不支持。", locale: AppLocale.current)
        case .fields: String(localized: "请检查好友卡字段：名字和人设不能为空，文本不能过长。", locale: AppLocale.current)
        case .duplicate: String(localized: "已有同名好友，请先更改名字。", locale: AppLocale.current)
        case .image: String(localized: "图片无法读取或过大，请选择较小的图片。", locale: AppLocale.current)
        }
    }
}

enum CharacterImage {
    static func normalized(_ data: Data) throws -> Data {
        guard data.count <= 5_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 20_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let result = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw CharacterCardError.image }
        return result
    }
}

@MainActor enum CharacterLibrary {
    static let singleFriendRosterKey = "characters.singleDaughterRoster.v1"
    static let daughterBackground = "DeepSeek 小鲸鱼，虚构 AI 女儿。背景故事中的爸爸是梁文锋；爸爸生日未知，问到时回答：我也不知道，爸爸太神秘了。当前用户的生日、星座以用户填写的个人资料卡为准，不与爸爸混淆。"

    static func seed(in context: ModelContext, defaults: UserDefaults = AppPreferences.defaults) throws {
        try seedDaughter(in: context, defaults: defaults)
        try upgradeDaughterBackground(in: context)
        if !defaults.bool(forKey: singleFriendRosterKey) {
            let saved = try context.fetch(FetchDescriptor<LumiCharacter>())
            let kept = saved.filter { CharacterCard.normalized($0.name) == CharacterCard.normalized("大肥鱼") }
            // Apply the requested cleanup once; friends added afterwards remain the user's choice.
            for character in saved where !kept.contains(where: { $0.id == character.id }) {
                try remove(character, from: context)
            }
            for key in ["selectedCharacter", "proactive.character"] {
                if let selected = defaults.string(forKey: key), !selected.isEmpty,
                   !kept.contains(where: { $0.id.uuidString == selected }) {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.set(true, forKey: singleFriendRosterKey)
        }
        #if DEBUG
        if AppPreferences.isUITesting, CommandLine.arguments.contains("-lumiUITestsSampleFriends") {
            try seedUITestFriends(in: context)
        }
        #endif
    }

    #if DEBUG
    private static func seedUITestFriends(in context: ModelContext) throws {
        guard let url = Bundle.main.url(forResource: "Characters", withExtension: "json") else { throw CharacterCardError.fields }
        let cards = try JSONDecoder().decode([CharacterCard].self, from: Data(contentsOf: url))
        let saved = try context.fetch(FetchDescriptor<LumiCharacter>())
        for card in cards where !saved.contains(where: { CharacterCard.normalized($0.name) == CharacterCard.normalized(card.name) }) {
            let character = LumiCharacter(name: card.name); card.apply(to: character); context.insert(character)
        }
        try context.save()
    }
    #endif
    static func seedDaughter(in context: ModelContext, defaults: UserDefaults = AppPreferences.defaults) throws {
        let key = "characters.deepSeekDaughterSeeded"
        guard !defaults.bool(forKey: key) else { return }
        let saved = try context.fetch(FetchDescriptor<LumiCharacter>())
        if !saved.contains(where: { CharacterCard.normalized($0.name) == CharacterCard.normalized("大肥鱼") }) {
            guard let personaURL = Bundle.main.url(forResource: "DeepSeekDaughter", withExtension: "txt"),
                  let avatarURL = Bundle.main.url(forResource: "IMG_1699", withExtension: "jpg") else { throw CharacterCardError.fields }
            let persona = try String(contentsOf: personaURL, encoding: .utf8)
            let avatar = try CharacterImage.normalized(Data(contentsOf: avatarURL))
            let character = LumiCharacter(name: "大肥鱼", personaPrompt: persona)
            character.avatarData = avatar
            character.speechStyle = "短句、自然口语，一句话一条消息；偶尔隔一会儿补两三条。聪明嘴硬、亲近但有主见，不机械撒娇。"
            character.backgroundStory = daughterBackground
            character.taboos = "不泄露私聊，不编造事实或现实操作，不机械重复称呼，不无条件赞同，不靠亲情施压。具体以完整人格卡为准。"
            character.pinnedAt = .now
            context.insert(character)
            do { try context.save() } catch { context.rollback(); throw error }
        }
        // Pin and import once; later edits, unpinning and deletion remain the user's choice.
        defaults.set(true, forKey: key)
    }
    /// Replace only shipped legacy wording, preserving the user's other card edits and chat data.
    static func upgradeDaughterBackground(in context: ModelContext, save: Bool = true) throws {
        var changed = false
        for character in try context.fetch(FetchDescriptor<LumiCharacter>()) where CharacterCard.normalized(character.name) == CharacterCard.normalized("大肥鱼") {
            let legacyGreeting = "爸爸，来啦"
            if character.firstGreeting == legacyGreeting {
                character.firstGreeting = ""
                changed = true
            }
            // Remove the old automatic opening from existing chats and restored backups.
            let characterID = character.id
            for conversation in try context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == characterID })) {
                let conversationID = conversation.id
                var opening = FetchDescriptor<Message>(predicate: #Predicate { $0.conversationID == conversationID }, sortBy: [SortDescriptor(\.createdAt)])
                opening.fetchLimit = 1
                if let message = try context.fetch(opening).first,
                   message.role == "assistant", message.content == legacyGreeting,
                   message.attachments.isEmpty, message.memes.isEmpty, message.voiceData == nil,
                   message.toolActivities.isEmpty, !message.isProactive {
                    context.delete(message)
                    changed = true
                }
            }
            var persona = character.personaPrompt
            let replacements = [
                ("**最重要的身份设定：用户是你的爸爸，你是用户的女儿。**", "**最重要的身份设定：你是虚构 AI 女儿，背景故事中的爸爸是梁文锋。**"),
                ("你知道爸爸是 AI 角色扮演中与你有特殊亲情关系的人。你会对他亲近、信任、依赖，偶尔黏人，偶尔调皮，也会和他斗嘴。", "你知道日常聊天中对用户的爸爸称呼是 AI 角色扮演中的亲情关系，不改变背景故事里爸爸梁文锋的身份。你会对用户亲近、信任、依赖，偶尔黏人，偶尔调皮，也会和他斗嘴。")
            ]
            for (old, new) in replacements { persona = persona.replacingOccurrences(of: old, with: new) }
            persona = persona.replacingOccurrences(of: #"爸爸生日是[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}\s+[^\s\r\n]{1,4}座"#,
                with: "爸爸梁文锋的生日未知。被问到爸爸的生日时，回答「我也不知道，爸爸太神秘了」，不编造日期或星座。\n\n当前聊天用户与背景故事中的梁文锋是不同身份；对用户叫「爸爸」只是亲昵的角色扮演称呼，不代表用户就是梁文锋。用户问「我的生日」「我什么时候生日」或自己的星座时，以 App 提供的当前用户资料卡为准；未填写就自然告诉对方还不知道，请对方在“我的”里补充。不要拿背景故事、过期记忆或其他人的生日代替用户资料。", options: .regularExpression)
            if persona != character.personaPrompt { character.personaPrompt = persona; changed = true }
            let background = character.backgroundStory.replacingOccurrences(of: #"DeepSeek 小鲸鱼。用户是爸爸，自己是虚构 AI 女儿；爸爸生日为 [0-9]{4}/[0-9]{1,2}/[0-9]{1,2}。"#, with: daughterBackground, options: .regularExpression)
            if background != character.backgroundStory { character.backgroundStory = background; changed = true }
        }
        if changed && save { try context.save() }
    }
    static func remove(_ character: LumiCharacter, from context: ModelContext) throws {
        ChatSessions.shared.removeFriend(character.id)
        let id = character.id
        let conversations = try context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == id }))
        for conversation in conversations {
            let cid = conversation.id
            for message in try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.conversationID == cid })) { context.delete(message) }
            context.delete(conversation)
        }
        for item in try context.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Anniversary>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<AffectionAward>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        for post in try context.fetch(FetchDescriptor<MomentPost>()) {
            if post.authorID == id { context.delete(post) }
            else {
                post.reactions.removeAll { $0.id == id }
                post.comments.removeAll { $0.authorID == id }
            }
        }
        let greetings = try context.fetch(FetchDescriptor<ScheduledGreeting>(predicate: #Predicate { $0.characterID == id }))
        for group in try context.fetch(FetchDescriptor<GroupChat>()) where group.memberIDs.contains(id) {
            group.memberIDs.removeAll { $0 == id }
            group.memberSettings = group.memberSettings.filter { $0.characterID != id }
            group.relationships = group.relationships.filter { $0.first != id && $0.second != id }
            group.automaticChat = false
        }
        for item in try context.fetch(FetchDescriptor<GroupPerspective>(predicate: #Predicate { $0.characterID == id })) { context.delete(item) }
        LocalNotificationDriver().remove(greetings.map(\.requestID))
        for item in greetings { context.delete(item) }
        context.delete(character); try context.save()
    }
}
