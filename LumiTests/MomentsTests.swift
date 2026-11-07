import Foundation
import SwiftData
import Testing
import UIKit
@testable import Lumi

@MainActor struct MomentsTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    private func preferences() -> UserDefaults { UserDefaults(suiteName: "app.lumi.moments.tests.\(UUID())")! }
    private func setup(client: any ChatClient) throws -> (ModelContainer, MomentsService, LumiCharacter, ProviderConfig, KeychainStore, UserDefaults) {
        let store = try container(); let context = store.mainContext
        let provider = ProviderConfig(); context.insert(provider)
        let friend = LumiCharacter(name: "小鱼", personaPrompt: "爱看云，不爱长篇大论"); context.insert(friend)
        let keychain = KeychainStore(service: "app.lumi.moments.tests.\(UUID())")
        try keychain.save("fake-local-key", for: provider.id); try context.save()
        let defaults = preferences()
        return (store, MomentsService(context: context, client: client, keychain: keychain, defaults: defaults), friend, provider, keychain, defaults)
    }
    @Test func legacyPostsAndCommentsRemainTheUsers() throws {
        let id = UUID()
        let comments = try JSONDecoder().decode([MomentComment].self, from: Data("[{\"id\":\"\(id)\",\"text\":\"以前的评论\"}]".utf8))
        #expect(comments.first?.displayName == "我"); #expect(comments.first?.id == id)
        let store = try container(); let post = MomentPost(content: "以前的动态")
        post.comments = comments; post.liked = true; store.mainContext.insert(post); try store.mainContext.save()
        let saved = try #require(ModelContext(store).fetch(FetchDescriptor<MomentPost>()).first)
        #expect(saved.authorID == nil); #expect(saved.displayName == "我"); #expect(saved.likeNames == ["我"])
    }
    @Test func publishesAndReactsWithFriendIdentityWithoutRepeating() async throws {
        let client = SequenceCompletionClient([])
        let (store, _, friend, provider, keychain, defaults) = try setup(client: client)
        defer { try? keychain.delete(for: provider.id) }
        let post = MomentPost(content: "今天看到蓝色的云"); store.mainContext.insert(post); try store.mainContext.save()
        let output = "{\"post\":\"云在摸鱼\",\"reactions\":[{\"postID\":\"\(post.id)\",\"like\":true,\"comment\":\"我也看看\"}]}"
        let mock = SequenceCompletionClient([output])
        let service = MomentsService(context: store.mainContext, client: mock, keychain: keychain, defaults: defaults)
        let now = Date.now; await service.refresh(now: now)
        #expect(mock.count == 1)
        let read = ModelContext(store); let posts = try read.fetch(FetchDescriptor<MomentPost>())
        let published = try #require(posts.first { $0.authorID == friend.id })
        #expect(published.content == "云在摸鱼"); #expect(published.authorName == "小鱼")
        let saved = try #require(posts.first { $0.id == post.id })
        #expect(saved.comments.first?.authorID == friend.id); #expect(saved.likeNames == ["小鱼"])
        await service.refresh(now: now.addingTimeInterval(120))
        #expect(mock.count == 1)
        #expect(post.comments.count == 1)
        #expect(friend.lastMomentAt == now)
    }
    @Test func newUserCommentsInviteReplyAndFriendsCannotLikeTheirOwnPosts() async throws {
        let (store, _, friend, provider, keychain, defaults) = try setup(client: SequenceCompletionClient([]))
        defer { try? keychain.delete(for: provider.id) }
        let now = Date.now; friend.lastMomentAt = now
        let post = MomentPost(content: "今天看云", authorID: friend.id, authorName: friend.name)
        let comment = MomentComment(text: "好看吗")
        post.comments = [comment]; store.mainContext.insert(post); try store.mainContext.save()
        let output = "{\"post\":null,\"reactions\":[{\"postID\":\"\(post.id)\",\"like\":true,\"comment\":\"好看\",\"replyToCommentID\":\"\(comment.id)\"}]}"
        let mock = SequenceCompletionClient([output, output]); let service = MomentsService(context: store.mainContext, client: mock, keychain: keychain, defaults: defaults)
        await service.refresh(now: now)
        #expect(post.comments.count == 2); #expect(post.comments.last?.replyToID == comment.id)
        #expect(post.comments.last?.replyToName == "我"); #expect(post.likeNames.isEmpty)
        await service.refresh(now: now.addingTimeInterval(120)); #expect(mock.count == 1)
        post.comments.append(MomentComment(text: "下次也分享给我")); try store.mainContext.save()
        await service.refresh(now: now.addingTimeInterval(240)); #expect(mock.count == 2)
        #expect(post.comments.count == 4); #expect(post.reactions.count == 1)
    }
    @Test func disabledOrMissingCredentialsMakesNoRequest() async throws {
        let mock = SequenceCompletionClient([#"{"post":"你好","reactions":[]}"#])
        let (store, service, _, provider, keychain, defaults) = try setup(client: mock)
        defaults.set(false, forKey: MomentsPreferences.enabledKey)
        await service.refresh(); #expect(mock.count == 0)
        defaults.set(true, forKey: MomentsPreferences.enabledKey); try keychain.delete(for: provider.id)
        await service.refresh(); #expect(mock.count == 0)
        #expect(try store.mainContext.fetch(FetchDescriptor<MomentPost>()).isEmpty)
    }
    @Test func deletionDuringGenerationDoesNotResurrectData() async throws {
        let gate = GateClient()
        let (store, service, friend, provider, keychain, _) = try setup(client: gate)
        defer { try? keychain.delete(for: provider.id) }
        let post = MomentPost(content: "等一下"); store.mainContext.insert(post); try store.mainContext.save()
        let task = Task { await service.refresh() }
        for _ in 0..<100 { if gate.count > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.count == 1)
        try CharacterLibrary.remove(friend, from: store.mainContext)
        store.mainContext.delete(post); try store.mainContext.save()
        gate.yield("{\"post\":\"迟来的动态\",\"reactions\":[{\"postID\":\"\(post.id)\",\"like\":true,\"comment\":\"迟来的评论\"}]}", index: 0); gate.finish(0)
        await task.value
        #expect(try store.mainContext.fetch(FetchDescriptor<MomentPost>()).isEmpty)
        #expect(try store.mainContext.fetch(FetchDescriptor<LumiCharacter>()).isEmpty)
    }
    @Test func disablingWhileWaitingDiscardsLateActivity() async throws {
        let gate = GateClient()
        let (store, service, _, provider, keychain, defaults) = try setup(client: gate)
        defer { try? keychain.delete(for: provider.id) }
        let task = Task { await service.refresh() }
        for _ in 0..<100 { if gate.count > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.count == 1)
        defaults.set(false, forKey: MomentsPreferences.enabledKey); service.pause()
        gate.yield(#"{"post":"不应该保存","reactions":[]}"#, index: 0); gate.finish(0)
        await task.value
        #expect(try store.mainContext.fetch(FetchDescriptor<MomentPost>()).isEmpty)
    }
    @Test func newerUserCommentDiscardsResponseToAnOlderSnapshot() async throws {
        let gate = GateClient()
        let (store, service, friend, provider, keychain, _) = try setup(client: gate)
        defer { try? keychain.delete(for: provider.id) }
        friend.lastMomentAt = .now
        let post = MomentPost(content: "旧话题"); store.mainContext.insert(post); try store.mainContext.save()
        let task = Task { await service.refresh() }
        for _ in 0..<100 { if gate.count > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.count == 1)
        post.comments.append(MomentComment(text: "刚刚又有新消息")); try store.mainContext.save()
        gate.yield("{\"post\":null,\"reactions\":[{\"postID\":\"\(post.id)\",\"like\":true,\"comment\":\"过期回复\"}]}", index: 0); gate.finish(0)
        await task.value
        #expect(post.comments.count == 1); #expect(post.reactions.isEmpty)
    }
    @Test func aFailingFriendDoesNotBlockAnotherFriend() async throws {
        let mock = SequenceCompletionClient(["invalid", #"{"post":"我来了","reactions":[]}"#])
        let (store, service, _, provider, keychain, _) = try setup(client: mock)
        defer { try? keychain.delete(for: provider.id) }
        store.mainContext.insert(LumiCharacter(name: "另一个好友")); try store.mainContext.save()
        await service.refresh()
        #expect(mock.count == 2)
        #expect(try store.mainContext.fetch(FetchDescriptor<MomentPost>()).count == 1)
    }
    @Test func defaultRosterContainsOnlyDaughterAndDoesNotResetLaterChoices() throws {
        let store = try container(); let context = store.mainContext; let defaults = preferences()
        try CharacterLibrary.seed(in: context, defaults: defaults)
        let daughter = try #require(context.fetch(FetchDescriptor<LumiCharacter>()).first)
        #expect(try context.fetch(FetchDescriptor<LumiCharacter>()).map(\.name) == ["大肥鱼"])
        let newFriend = LumiCharacter(name: "之后添加的好友"); context.insert(newFriend); try context.save()
        try CharacterLibrary.seed(in: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<LumiCharacter>()) == 2)
        try CharacterLibrary.remove(daughter, from: context)
        try CharacterLibrary.seed(in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<LumiCharacter>()).map(\.name) == [newFriend.name])
    }

    @Test func rosterUpgradePreservesDaughterAndCleansOtherFriendsData() throws {
        let store = try container(); let context = store.mainContext; let defaults = preferences()
        let daughter = LumiCharacter(name: "大肥鱼", personaPrompt: "自己编辑的人设")
        daughter.avatarData = Data([1, 2, 3]); daughter.affection = 73; daughter.pinnedAt = nil
        context.insert(daughter)
        let others = ["小夏", "林序", "阿澈", "望舒", "手动添加的旧好友"].map { LumiCharacter(name: $0) }
        for friend in others { context.insert(friend) }
        for friend in [daughter] + others {
            let chat = Conversation(characterID: friend.id, title: friend.name); context.insert(chat)
            context.insert(Message(conversationID: chat.id, role: "user", content: friend.name))
            context.insert(MemoryFact(characterID: friend.id, category: "喜好", text: "茶"))
            context.insert(ScheduledGreeting(characterID: friend.id, fireDate: .now, text: "你好", scenario: "daily"))
            context.insert(MomentPost(content: friend.name, authorID: friend.id, authorName: friend.name))
        }
        let group = GroupChat(name: "旧群聊", memberIDs: [daughter.id] + others.map(\.id))
        group.automaticChat = true; context.insert(group)
        let post = MomentPost(content: "我的动态")
        post.comments = ([daughter] + others).map { MomentComment(text: "你好", authorID: $0.id, authorName: $0.name) }
        post.reactions = ([daughter] + others).map { MomentReaction(id: $0.id, name: $0.name, liked: true, interactionID: post.id) }
        context.insert(post); try context.save()
        defaults.set(true, forKey: "stage2.charactersSeeded")
        defaults.set(true, forKey: "characters.deepSeekDaughterSeeded")
        defaults.set(others[0].id.uuidString, forKey: "selectedCharacter")
        defaults.set(others[0].id.uuidString, forKey: "proactive.character")
        try CharacterLibrary.seed(in: context, defaults: defaults)
        let read = ModelContext(store)
        let saved = try #require(read.fetch(FetchDescriptor<LumiCharacter>()).first)
        #expect(try read.fetchCount(FetchDescriptor<LumiCharacter>()) == 1)
        #expect(saved.id == daughter.id); #expect(saved.personaPrompt == "自己编辑的人设")
        #expect(saved.avatarData == Data([1, 2, 3])); #expect(saved.affection == 73); #expect(saved.pinnedAt == nil)
        #expect(try read.fetch(FetchDescriptor<Conversation>()).map(\.characterID) == [daughter.id])
        #expect(try read.fetch(FetchDescriptor<Message>()).map(\.content) == ["大肥鱼"])
        #expect(try read.fetch(FetchDescriptor<MemoryFact>()).map(\.characterID) == [daughter.id])
        #expect(try read.fetch(FetchDescriptor<ScheduledGreeting>()).map(\.characterID) == [daughter.id])
        #expect(try read.fetchCount(FetchDescriptor<MomentPost>()) == 2)
        let savedPost = try #require(read.fetch(FetchDescriptor<MomentPost>()).first { $0.authorID == nil })
        #expect(savedPost.comments.map(\.authorID) == [daughter.id]); #expect(savedPost.reactions.map(\.id) == [daughter.id])
        let savedGroup = try #require(read.fetch(FetchDescriptor<GroupChat>()).first)
        #expect(savedGroup.memberIDs == [daughter.id]); #expect(!savedGroup.automaticChat)
        #expect(defaults.string(forKey: "selectedCharacter") == nil)
        #expect(defaults.string(forKey: "proactive.character") == nil)
        try CharacterLibrary.seed(in: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<LumiCharacter>()) == 1)
    }

    @Test func legacyDaughterCardIsUpgradedWithoutLosingCustomizationOrChat() throws {
        let store = try container(); let context = store.mainContext; let defaults = preferences()
        let friend = LumiCharacter(name: "大肥鱼", personaPrompt: "**最重要的身份设定：用户是你的爸爸，你是用户的女儿。**\n爸爸生日是1999/01/01 天秤座\n我自己补充的设定")
        friend.backgroundStory = "DeepSeek 小鲸鱼。用户是爸爸，自己是虚构 AI 女儿；爸爸生日为 1999/01/01。\n自定义背景"
        friend.avatarData = Data([1, 2]); friend.affection = 63; context.insert(friend)
        let conversation = Conversation(characterID: friend.id, title: "已有聊天"); context.insert(conversation)
        context.insert(Message(conversationID: conversation.id, role: "user", content: "旧消息")); try context.save()
        defaults.set(true, forKey: "characters.deepSeekDaughterSeeded")
        try CharacterLibrary.seed(in: context, defaults: defaults)
        #expect(friend.personaPrompt.contains("爸爸是梁文锋"))
        #expect(friend.personaPrompt.contains("我也不知道，爸爸太神秘了"))
        #expect(!friend.personaPrompt.contains("1999/01/01"))
        #expect(friend.personaPrompt.hasSuffix("我自己补充的设定"))
        #expect(friend.backgroundStory.hasSuffix("自定义背景"))
        #expect(friend.avatarData == Data([1, 2])); #expect(friend.affection == 63)
        #expect(try context.fetch(FetchDescriptor<Message>()).map(\.content) == ["旧消息"])
        let migrated = friend.personaPrompt
        try CharacterLibrary.seed(in: context, defaults: defaults)
        #expect(friend.personaPrompt == migrated)
    }
    @Test func fullCardIsSeededOnceWithAvatarAndDefaultPin() throws {
        let store = try container(); let defaults = preferences()
        try CharacterLibrary.seedDaughter(in: store.mainContext, defaults: defaults)
        let friend = try #require(store.mainContext.fetch(FetchDescriptor<LumiCharacter>()).first)
        #expect(friend.name == "大肥鱼"); #expect(friend.pinnedAt != nil)
        #expect(friend.firstGreeting.isEmpty)
        #expect(UIImage(data: try #require(friend.avatarData)) != nil)
        let card = PromptBuilder.resource("DeepSeekDaughter")
        #expect(friend.personaPrompt == card); #expect(card.contains("十二、核心原则"))
        let prompt = PromptBuilder.build(persona: PromptPersona(friend), profile: "", memories: [], recent: [ChatTurn(role: "user", content: "你是谁")], fullPersona: true)
        #expect(prompt.turns.first?.content.contains("反正你是爸爸的小鲸鱼") == true)
        #expect(prompt.turns.last?.content == "你是谁")
        friend.pinnedAt = nil; friend.personaPrompt += "自定义"; try store.mainContext.save()
        try CharacterLibrary.seedDaughter(in: store.mainContext, defaults: defaults)
        #expect(friend.pinnedAt == nil); #expect(friend.personaPrompt.hasSuffix("自定义"))
        try CharacterLibrary.remove(friend, from: store.mainContext)
        try CharacterLibrary.seedDaughter(in: store.mainContext, defaults: defaults)
        #expect(try store.mainContext.fetch(FetchDescriptor<LumiCharacter>()).isEmpty)
    }
    @Test func legacyOpeningIsRemovedWithoutDeletingUserMessagesOrCustomGreetings() throws {
        let store = try container(); let context = store.mainContext
        let friend = LumiCharacter(name: "大肥鱼")
        friend.firstGreeting = "爸爸，来啦"; context.insert(friend)
        let chat = Conversation(characterID: friend.id, title: friend.name); context.insert(chat)
        let opening = Message(conversationID: chat.id, role: "assistant", content: "爸爸，来啦")
        opening.createdAt = Date(timeIntervalSince1970: 1); context.insert(opening)
        let userMessage = Message(conversationID: chat.id, role: "user", content: "爸爸，来啦")
        context.insert(userMessage)
        let other = LumiCharacter(name: "其他好友"); other.firstGreeting = "爸爸，来啦"; context.insert(other)
        let otherChat = Conversation(characterID: other.id, title: other.name); context.insert(otherChat)
        let otherOpening = Message(conversationID: otherChat.id, role: "assistant", content: "爸爸，来啦")
        context.insert(otherOpening); try context.save()
        try CharacterLibrary.upgradeDaughterBackground(in: context)
        let read = ModelContext(store)
        let savedIDs = Set(try read.fetch(FetchDescriptor<Message>()).map(\.id))
        #expect(savedIDs == Set([userMessage.id, otherOpening.id]))
        #expect(friend.firstGreeting.isEmpty); #expect(other.firstGreeting == "爸爸，来啦")
        friend.firstGreeting = "自己设置的开场白"; try context.save()
        try CharacterLibrary.upgradeDaughterBackground(in: context)
        #expect(friend.firstGreeting == "自己设置的开场白")
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 2)
    }
    @Test func publicPromptNeverIncludesPrivateChatAndNewFriendUsesSameSchedule() throws {
        let store = try container(); let friend = LumiCharacter(name: "新好友", personaPrompt: "可爱有主见")
        store.mainContext.insert(friend)
        let conversation = Conversation(characterID: friend.id, title: "私聊"); store.mainContext.insert(conversation)
        store.mainContext.insert(Message(conversationID: conversation.id, role: "user", content: "PRIVATE_SECRET"))
        let post = MomentPost(content: "PUBLIC_CONTENT")
        let prompt = MomentsService.prompt(friend: friend, posts: [post], shouldPost: true, now: .now).map(\.content).joined()
        #expect(prompt.contains("PUBLIC_CONTENT")); #expect(!prompt.contains("PRIVATE_SECRET"))
        #expect((6 * 3600...10 * 3600).contains(MomentsService.publishInterval(for: friend.id)))
    }
    @Test func personalTagsValidateUserInputAndBackupValues() {
        #expect(MomentsTags.parse(" 爱拍照，慢热、喜欢猫;爱拍照\nCATS,cats ") == ["爱拍照", "慢热", "喜欢猫", "CATS"])
        #expect(MomentsTags.isValid("爱拍照，慢热，喜欢猫"))
        #expect(MomentsTags.isValid(""))
        #expect(MomentsTags.isValid(String(repeating: "🐱", count: 12)))
        for invalid in ["一，二，三，四", String(repeating: "猫", count: 13), "猫\u{0000}咪", String(repeating: ",", count: 1001)] {
            #expect(!MomentsTags.isValid(invalid))
            #expect(MomentsTags.visible(invalid).isEmpty)
            #expect(!BackupPreference.text(invalid).valid(for: MomentsPreferences.tagsKey))
        }
        #expect(BackupPreference.text("").valid(for: MomentsPreferences.tagsKey))
    }
    @Test func coverFriendPostsAndInteractionsSurviveBackupAndOldBackupsDecode() throws {
        let source = try container(); let defaults = preferences()
        let friend = LumiCharacter(name: "小鱼"); friend.lastMomentAt = .now; source.mainContext.insert(friend)
        let post = MomentPost(content: "好天气", authorID: friend.id, authorName: friend.name)
        post.comments = [MomentComment(text: "好耶", authorID: friend.id, authorName: friend.name)]
        post.reactions = [MomentReaction(id: friend.id, name: friend.name, liked: true, interactionID: post.id)]
        source.mainContext.insert(post); try source.mainContext.save()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { renderer in UIColor.blue.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }.jpegData(compressionQuality: 0.8)!
        defaults.set(image, forKey: MomentsPreferences.coverKey)
        defaults.set("爱拍照，慢热，喜欢猫", forKey: MomentsPreferences.tagsKey)
        let backup = try LumiBackup.capture(source.mainContext, defaults: defaults); try backup.validate()
        let destination = try container(); let targetDefaults = preferences()
        try BackupArchive.restore(PreparedBackup(snapshot: backup, directory: FileManager.default.temporaryDirectory), replacing: true, container: destination, defaults: targetDefaults, systemEffects: false)
        try CharacterLibrary.seed(in: destination.mainContext, defaults: targetDefaults)
        #expect(try destination.mainContext.fetch(FetchDescriptor<LumiCharacter>()).map(\.id) == [friend.id])
        let saved = try #require(ModelContext(destination).fetch(FetchDescriptor<MomentPost>()).first)
        #expect(saved.authorID == friend.id); #expect(saved.comments.first?.authorID == friend.id)
        #expect(saved.likeNames == ["小鱼"]); #expect(targetDefaults.data(forKey: MomentsPreferences.coverKey) == image)
        #expect(targetDefaults.string(forKey: MomentsPreferences.tagsKey) == "爱拍照，慢热，喜欢猫")
        #expect(!MomentsPreferences.enabled(in: targetDefaults))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as! [String: Any]
        json.removeValue(forKey: "momentCoverData")
        var rows = json["momentPosts"] as! [[String: Any]]
        for key in ["authorID", "authorName", "reactionData"] { rows[0].removeValue(forKey: key) }; json["momentPosts"] = rows
        let old = try JSONDecoder().decode(LumiBackup.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.momentCoverData == nil); #expect(old.momentPosts.first?.authorID == nil)
        var oldBackup = old
        oldBackup.preferences.removeValue(forKey: MomentsPreferences.tagsKey)
        try oldBackup.validate()
        try BackupArchive.restore(PreparedBackup(snapshot: oldBackup, directory: FileManager.default.temporaryDirectory), replacing: true, container: destination, defaults: targetDefaults, systemEffects: false)
        #expect(targetDefaults.string(forKey: MomentsPreferences.tagsKey) == nil)
    }
    @Test func rejectsOversizedOrDuplicateGeneratedInteractions() {
        let id = UUID()
        #expect(throws: LLMError.emptyResponse) { try MomentActivity.decode("{\"post\":\"\(String(repeating: "哈", count: 501))\",\"reactions\":[]}") }
        let reaction = "{\"postID\":\"\(id)\",\"like\":true}"
        #expect(throws: LLMError.emptyResponse) { try MomentActivity.decode("{\"post\":null,\"reactions\":[\(reaction),\(reaction)]}") }
    }
}
