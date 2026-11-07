import SwiftUI
import SwiftData

@MainActor private struct GroupPreviewData {
    let container: ModelContainer
    let group: GroupChat
    let provider: ProviderConfig
    init() {
        container = try! ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        provider = ProviderConfig(); context.insert(provider)
        let friends = ["小夏", "林序", "阿澈", "望舒"].map { LumiCharacter(name: $0) }
        friends.forEach { context.insert($0) }
        group = GroupChat(name: "夜聊小分队", announcement: "今天也辛苦啦，来分享一件小事吧。", memberIDs: friends.map(\.id))
        context.insert(group)
        let lines = ["今天下班路上看见了很好看的晚霞。", "我刚泡好茶，你们呢？", "等会儿开一局？我今天状态超好！", "先听你们聊，我把这页书看完。"]
        let user = GroupMessage(groupID: group.id, role: "user", text: "@小夏 @林序 今天有什么开心的事？")
        context.insert(user)
        for (index, friend) in friends.enumerated() {
            let message = GroupMessage(groupID: group.id, role: "assistant", text: lines[index], speakerID: friend.id, speakerName: friend.name, replyToID: user.id)
            message.createdAt = user.createdAt.addingTimeInterval(Double(index + 1)); context.insert(message)
        }
        try! context.save()
    }
}

#Preview("四人群聊") {
    let data = GroupPreviewData()
    NavigationStack { GroupChatView(group: data.group, provider: data.provider, onPrivateChat: { _ in }, onDelete: {}) }
        .modelContainer(data.container).tint(.lumiAccent).environment(\.locale, Locale(identifier: "zh-Hans"))
}

#Preview("我的") {
    NavigationStack { MyProfileView(provider: ProviderConfig()) }
        .modelContainer(for: LumiSchema.models, inMemory: true).tint(.lumiAccent)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
}
