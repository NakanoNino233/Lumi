#if DEBUG
import SwiftUI
import SwiftData

@MainActor enum Stage2Preview {
    static let container: ModelContainer = {
        let store = try! ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let character = LumiCharacter(name: "小夏", personaPrompt: "温暖、独立的虚构插画师。")
        character.speechStyle = "自然、温柔，有一点生活里的幽默。"; character.firstGreeting = "嗨，今天有什么想慢慢说的吗？"
        character.affection = 32; character.stageIndex = 1
        let context = store.mainContext; context.insert(character)
        let profile = UserProfile(characterID: character.id); profile.summary = "喜欢茉莉花茶，最近正在准备一场重要的考试。"; context.insert(profile)
        let fact = MemoryFact(characterID: character.id, category: "喜好", text: "喜欢茉莉花茶", importance: 4); fact.isPinned = true; context.insert(fact)
        context.insert(MemoryFact(characterID: character.id, category: "生日", text: "生日是六月十日", importance: 5))
        context.insert(Anniversary(characterID: character.id, title: "第一次聊天", date: .now))
        context.insert(DiaryEntry(characterID: character.id, day: RelationshipEngine.dayKey(.now), content: "今天聊起了喜欢的茶，也聊到了备考时的小小紧张。愿每一点认真的努力，都能被自己看见。"))
        try! context.save(); return store
    }()
    static var character: LumiCharacter { try! container.mainContext.fetch(FetchDescriptor<LumiCharacter>()).first! }
}

#Preview("Memories") {
    NavigationStack { MemoriesView(character: Stage2Preview.character, provider: ProviderConfig()) }
        .modelContainer(Stage2Preview.container).tint(.lumiAccent).environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("Character Chat") {
    NavigationStack { ChatView(provider: ProviderConfig(), character: Stage2Preview.character) }
        .modelContainer(Stage2Preview.container).tint(.lumiAccent).environment(\.locale, Locale(identifier: "zh-Hans"))
}
#endif
