import Foundation
import SwiftData
import Testing
@testable import Lumi

final class GroupTestClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [[ChatTurn]] = []
    private var capturedEndpoints: [ProviderEndpoint] = []
    var invalidCount: Int
    let delay: Duration
    init(invalidCount: Int = 0, delay: Duration = .zero) { self.invalidCount = invalidCount; self.delay = delay }
    var requests: [[ChatTurn]] { lock.withLock { captured } }
    var endpoints: [ProviderEndpoint] { lock.withLock { capturedEndpoints } }
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
    func complete(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], limit: Int) async throws -> String {
        let index = lock.withLock { let result = captured.count; captured.append(messages); capturedEndpoints.append(endpoint); return result }
        if delay != .zero { try await Task.sleep(for: delay) }
        if index < invalidCount { return "[{broken JSON" }
        let system = messages[0].content
        let marker = "指定发言成员："
        let json = String(system.components(separatedBy: marker).last ?? "[]").trimmingCharacters(in: .whitespacesAndNewlines)
        let names = try JSONDecoder().decode([String].self, from: Data(json.utf8))
        if system.contains("只以指定角色自己的口吻输出一条纯文字消息") { return "我很乐意一起聊今天的事情。" }
        return PromptBuilder.dataBlock(names.map { GroupLine(speaker: $0, text: "我很乐意一起聊今天的事情。") })
    }
}

@MainActor final class GroupHarness {
    let container: ModelContainer
    let context: ModelContext
    let provider: ProviderConfig
    let friends: [LumiCharacter]
    let group: GroupChat
    let client: GroupTestClient
    let keychain: KeychainStore
    let model: GroupChatModel
    init(count: Int = 4, client: GroupTestClient = GroupTestClient(), idle: Duration = .milliseconds(1)) throws {
        container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container); provider = ProviderConfig(); context.insert(provider)
        friends = ["小夏", "林序", "阿澈", "望舒"].prefix(count).map { LumiCharacter(name: $0, personaPrompt: "独立人设：\($0)") }
        for friend in friends { context.insert(friend) }
        group = GroupChat(name: "四人夜聊", memberIDs: friends.map(\.id)); context.insert(group)
        self.client = client; keychain = KeychainStore(service: "app.lumi.group-tests.\(UUID())")
        try keychain.save("fake-local-test-key", for: provider.id); try context.save()
        model = GroupChatModel(client: client, keychain: keychain, typingDelay: .zero, idleDelay: idle)
        model.configure(group: group, provider: provider, context: context)
    }
    var everyone: String { friends.map { "@\($0.name)" }.joined(separator: " ") }
    func clean() { model.stop(notice: false); try? keychain.delete(for: provider.id) }
}

struct GroupDirectorTests {
    @Test func allMembersCanParticipateWithoutThreeSpeakerCap() {
        let actors = ["小夏", "林序", "阿澈", "望舒", "A", "B"].map { GroupActor(name: $0) }
        let chosen = GroupDirector.select(actors: actors, mentioned: Set(actors.map(\.id)), recentSpeakers: [], round: 0, random: { 0.99 })
        #expect(chosen.map(\.id) == actors.map(\.id))
        let ordinary = GroupDirector.select(actors: actors, mentioned: [], recentSpeakers: [], round: 0, random: { 0 })
        #expect(ordinary.count == actors.count)
    }
    @Test func mentionBoundariesAndLongerNames() {
        let actors = ["林序", "林序同学", "A+B", "小夏"].map { GroupActor(name: $0) }
        let result = GroupDirector.mentions(in: "@林序同学 ＠小夏，@A+B! @林序不是完整名字", actors: actors)
        #expect(result == Set(actors.dropFirst().map(\.id)))
    }
    @Test func previousSpeakerCanReplyAgainWithoutForcedRotation() {
        let actors = ["小夏", "林序", "阿澈", "望舒"].map { GroupActor(name: $0, participation: .quiet) }
        let selected = GroupDirector.select(actors: actors, mentioned: [], recentSpeakers: [actors[0].id], round: 10, random: { 0.99 })
        #expect(selected.count == 1)
        #expect(selected.first?.id == actors.first?.id)
        #expect(GroupDirector.select(actors: actors, mentioned: [], recentSpeakers: [], round: 0, random: { 0 }).count == actors.count)
    }
    @Test(arguments: ["", "[{broken", #"[{"speaker":"用户","text":"替用户发言"}]"#, #"[{"speaker":"小夏","text":"你好","extra":true}]"#, #"[{"speaker":"小夏","text":"用户：我同意了"}]"#, #"[{"speaker":"小夏","text":""}]"#])
    func malformedOrForgedSpeakersFail(_ raw: String) {
        #expect(throws: GroupError.format) { try GroupDirector.parse(raw, selected: [GroupActor(name: "小夏")]) }
    }
    @Test func requiredSpeakersRespondAndConversationOrderIsPreserved() throws {
        let actors = ["小夏", "林序"].map { GroupActor(name: $0) }
        let raw = #"[{"speaker":"林序","text":"好"},{"speaker":"小夏","text":"来啦"}]"#
        #expect(try GroupDirector.parse(raw, selected: actors).map(\.speaker) == ["林序", "小夏"])
        #expect(throws: GroupError.format) { try GroupDirector.parse(#"[{"speaker":"小夏","text":"好"}]"#, selected: actors) }
        #expect(throws: GroupError.format) { try GroupDirector.single(raw, actor: actors[0], all: actors) }
        #expect(throws: GroupError.format) { try GroupDirector.single("林序：我替他说", actor: actors[0], all: actors) }
    }
    @Test func optionalMembersMayStayQuietAndSpeakersCanFollowUp() throws {
        let actors = ["小夏", "林序", "阿澈"].map { GroupActor(name: $0) }
        let raw = #"[{"speaker":"小夏","text":"来啦"},{"speaker":"林序","text":"好啊"},{"speaker":"小夏","text":"那就这么定啦"}]"#
        let lines = try GroupDirector.parse(raw, selected: actors, required: [actors[0].id])
        #expect(lines.map(\.speaker) == ["小夏", "林序", "小夏"])
        #expect(throws: GroupError.format) { try GroupDirector.parse(raw, selected: actors, required: [actors[2].id]) }
    }
    @Test func budgetReservesBeforeRequest() throws {
        var budget = GroupRunBudget(maximum: 24_020)
        try budget.reserve([ChatTurn(role: "user", content: "x")]); #expect(budget.used == 12_009)
        try budget.reserve([ChatTurn(role: "user", content: "x")])
        #expect(throws: GroupError.budget) { try budget.reserve([]) }
    }
    @MainActor @Test func notificationsShareQuotaAndQuietHours() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let preferences = CompanionPreferences(enabled: true, dailyLimit: 1)
        #expect(GroupMentionNotifier.eligible(text: "@我 一起聊", enabled: true, preferences: preferences, now: now, occupiedDates: [], calendar: calendar))
        #expect(!GroupMentionNotifier.eligible(text: "@我 一起聊", enabled: true, preferences: preferences, now: now, occupiedDates: [now], calendar: calendar))
        #expect(!GroupMentionNotifier.eligible(text: "@我 一起聊", enabled: false, preferences: preferences, now: now, occupiedDates: [], calendar: calendar))
        #expect(!GroupMentionNotifier.eligible(text: "@我 一起聊", enabled: true, preferences: preferences, now: now.addingTimeInterval(11 * 3600), occupiedDates: [], calendar: calendar))
        #expect(!GroupMentionNotifier.eligible(text: "@我自己说", enabled: true, preferences: preferences, now: now, occupiedDates: [], calendar: calendar))
    }
}

@MainActor struct GroupChatTests {
    @Test func twentyRoundsKeepFourMemberIdentityAndSeparateHistory() async throws {
        let h = try GroupHarness(); defer { h.clean() }
        for round in 0..<20 {
            #expect(h.model.send("\(h.everyone) 一起聊聊今天的日常 \(round)"))
            await h.model.waitUntilIdle()
            #expect(h.model.errorMessage == nil)
            let user = try #require(h.model.messages.last { $0.role == "user" })
            let replies = h.model.messages.filter { $0.replyToID == user.id }
            #expect(replies.count == 4)
            #expect(Set(replies.compactMap(\.speakerID)) == Set(h.friends.map(\.id)))
            for reply in replies { #expect(h.friends.first { $0.id == reply.speakerID }?.name == reply.speakerName) }
        }
        #expect(h.client.requests.count == 20)
        #expect(h.client.endpoints.allSatisfy { Set($0.tokenOwners.map(\.id)) == Set(h.friends.map(\.id)) })
        #expect(h.model.messages.filter { $0.role == "user" }.count == 20)
        #expect(try h.context.fetchCount(FetchDescriptor<Message>()) == 0)
        #expect(try h.context.fetchCount(FetchDescriptor<Conversation>()) == 0)
        #expect(try h.context.fetchCount(FetchDescriptor<GroupPerspective>()) == 4)
        #expect(h.friends.allSatisfy { $0.affection <= 1 })
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<GroupMessage>()) == 100)
    }
    @Test func brokenJSONRetriesOnceThenFallsBackForEveryMention() async throws {
        let client = GroupTestClient(invalidCount: 2); let h = try GroupHarness(count: 2, client: client); defer { h.clean() }
        #expect(h.model.send("\(h.everyone) 请大家聊聊今天")); await h.model.waitUntilIdle()
        #expect(h.model.errorMessage == nil); #expect(client.requests.count == 4)
        #expect(h.model.messages.filter { $0.role == "assistant" }.count == 2)
        #expect(client.requests[1].last?.content.contains("上一条输出格式无效") == true)
        #expect(client.endpoints.prefix(2).allSatisfy { $0.tokenOwners.count == 2 })
        #expect(client.endpoints.suffix(2).allSatisfy { $0.tokenOwners.count == 1 })
    }
    @Test func fullyBrokenFallbackReportsFailureWithoutForgedMessages() async throws {
        let h = try GroupHarness(client: GroupTestClient(invalidCount: 20)); defer { h.clean() }
        h.model.send("\(h.everyone) 大家聊聊今天"); await h.model.waitUntilIdle()
        #expect(h.model.errorMessage == GroupError.format.localizedDescription)
        #expect(h.model.messages.count == 1); #expect(h.client.requests.count == 3)
    }
    @Test func independentModeMakesOneRequestPerMentionedMember() async throws {
        let h = try GroupHarness(); defer { h.clean() }; h.group.independentReplies = true
        h.model.send("\(h.everyone) 聊聊今天"); await h.model.waitUntilIdle()
        #expect(h.client.requests.count == 4); #expect(h.model.messages.count == 5)
        #expect(h.client.endpoints.allSatisfy { $0.tokenOwners.count == 1 })
        #expect(Set(h.client.endpoints.flatMap(\.tokenOwners).map(\.id)) == Set(h.friends.map(\.id)))
    }
    @Test func automaticChatStopsWithNoticeAtRoundLimit() async throws {
        let h = try GroupHarness(); defer { h.clean() }; h.group.automaticChat = true; h.group.automaticRounds = 2; h.group.automaticBudget = 100_000
        h.model.send("\(h.everyone) 一起聊聊今天"); await h.model.waitUntilIdle()
        #expect(h.model.errorMessage == nil); #expect(!h.model.waitingForAutomatic && !h.model.isGenerating)
        #expect(h.client.requests.count == 3)
        #expect(h.client.requests.dropFirst().allSatisfy { $0.first?.content.contains("用户暂时没有发言") == true })
        #expect(h.model.messages.last?.role == "system"); #expect(h.model.messages.last?.text.contains("轮数上限") == true)
        #expect(h.friends.allSatisfy { $0.affection <= 1 })
    }
    @Test func automaticBudgetStopsBeforeAdditionalRequest() async throws {
        let h = try GroupHarness(); defer { h.clean() }; h.group.automaticChat = true; h.group.automaticBudget = 10_000
        h.model.send("\(h.everyone) 聊聊今天"); await h.model.waitUntilIdle()
        #expect(h.client.requests.count == 1); #expect(h.model.messages.last?.text == GroupError.budget.localizedDescription)
    }
    @Test func explicitStopCancelsInFlightResponse() async throws {
        let h = try GroupHarness(client: GroupTestClient(delay: .seconds(5))); defer { h.clean() }
        h.model.send("\(h.everyone) 聊聊今天")
        try await Task.sleep(for: .milliseconds(30)); h.model.stop(notice: false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!h.model.isGenerating); #expect(h.model.messages.count == 1)
    }
    @Test func missingKeySavesUserMessageWithoutRequest() async throws {
        let h = try GroupHarness(); defer { h.clean() }; try h.keychain.delete(for: h.provider.id)
        h.model.send("离线先记录今天的事情"); await h.model.waitUntilIdle()
        #expect(h.model.messages.count == 1); #expect(h.client.requests.isEmpty)
        #expect(h.model.errorMessage == LLMError.missingKey.localizedDescription)
    }
    @Test func settingsAndPairRelationshipsPersistAndGroupPinSortsFirst() throws {
        let h = try GroupHarness(); defer { h.clean() }
        #expect(!h.group.automaticChat && !h.group.sharesMemory && !h.group.independentReplies && !h.group.mentionNotifications)
        h.group.relationships = [GroupRelationship(first: h.friends[0].id, second: h.friends[1].id, text: "死党")]
        h.group.memberSettings = [GroupMemberSetting(characterID: h.friends[0].id, participation: .talkative)]
        h.group.pinnedAt = .now; try h.context.save()
        let saved = try #require(ModelContext(h.container).fetch(FetchDescriptor<GroupChat>()).first)
        #expect(saved.relationships.first?.text == "死党"); #expect(saved.memberSettings.first?.participation == .talkative)
        let rows = [HomeConversation(friend: ConversationSummary(friend: h.friends[0], last: nil, date: .now)), HomeConversation(group: saved, latest: nil)].sorted(by: HomeConversation.precedes)
        #expect(rows.first?.id == saved.id)
    }
    @Test func privateAndGroupMemorySharingRequiresOptInBothDirections() throws {
        let h = try GroupHarness(); defer { h.clean() }
        let friend = h.friends[0]; let fact = MemoryFact(characterID: friend.id, category: "其他", text: "PRIVATE_SECRET")
        let perspective = GroupPerspective(groupID: h.group.id, characterID: friend.id); perspective.summary = "GROUP_SECRET"
        h.context.insert(fact); h.context.insert(perspective); try h.context.save()
        let actors = h.friends.map { GroupActor($0, group: h.group) }
        func prompt() -> String { GroupPrompt.build(group: h.group, actors: actors, selected: actors, history: [], perspectives: [perspective], privateMemories: [fact]).map(\.content).joined() }
        #expect(!prompt().contains("PRIVATE_SECRET")); #expect(try GroupStore.privateContext(characterID: friend.id, context: h.context).isEmpty)
        h.group.sharesMemory = true; try h.context.save()
        #expect(prompt().contains("PRIVATE_SECRET")); #expect(try GroupStore.privateContext(characterID: friend.id, context: h.context).contains("GROUP_SECRET"))
        let privateModel = ChatModel(client: h.client, keychain: h.keychain, automaticMaintenance: false)
        privateModel.configure(context: h.context, provider: h.provider, character: friend)
        #expect(privateModel.requestHistory().contains { $0.role == "system" && $0.content.contains("GROUP_SECRET") })
        h.group.sharesMemory = false; try h.context.save()
        #expect(!privateModel.requestHistory().contains { $0.role == "system" && $0.content.contains("GROUP_SECRET") })
    }
    @Test func deletingGroupKeepsFriendsAndPrivateMessages() async throws {
        let h = try GroupHarness(); defer { h.clean() }
        h.model.send("\(h.everyone) 聊聊今天"); await h.model.waitUntilIdle()
        let privateMessage = Message(conversationID: UUID(), role: "user", content: "私聊内容"); h.context.insert(privateMessage); try h.context.save()
        try GroupStore.delete(h.group, context: h.context)
        #expect(try h.context.fetchCount(FetchDescriptor<GroupMessage>()) == 0)
        #expect(try h.context.fetchCount(FetchDescriptor<GroupPerspective>()) == 0)
        #expect(try h.context.fetchCount(FetchDescriptor<LumiCharacter>()) == 4)
        #expect(try h.context.fetchCount(FetchDescriptor<Message>()) == 1)
    }
    @Test func rejectsMissingOrDuplicateMembersAndReservedNames() throws {
        let h = try GroupHarness(); defer { h.clean() }
        #expect(throws: GroupError.members) { try GroupStore.validate(name: "群", members: [h.friends[0]]) }
        #expect(throws: GroupError.members) { try GroupStore.validate(name: "群", members: [h.friends[0], h.friends[0]]) }
        #expect(throws: GroupError.members) { try GroupStore.validate(name: " ", members: h.friends) }
        h.friends[0].name = "用户"
        #expect(throws: GroupError.members) { try GroupStore.validate(name: "群", members: h.friends) }
    }
    @Test func removingFriendCleansGroupMembershipAndPerspective() async throws {
        let h = try GroupHarness(); defer { h.clean() }
        h.model.send("\(h.everyone) 今天一起聊聊天"); await h.model.waitUntilIdle()
        let removed = h.friends[0]; let id = removed.id
        h.group.automaticChat = true
        h.group.relationships = [GroupRelationship(first: id, second: h.friends[1].id, text: "死党")]
        try h.context.save(); h.model.stop(notice: false)
        try CharacterLibrary.remove(removed, from: h.context)
        #expect(!h.group.memberIDs.contains(id)); #expect(h.group.relationships.isEmpty); #expect(!h.group.automaticChat)
        #expect(try h.context.fetch(FetchDescriptor<GroupPerspective>()).allSatisfy { $0.characterID != id })
        #expect(try h.context.fetch(FetchDescriptor<GroupMessage>()).contains { $0.speakerID == id && $0.speakerName == "小夏" })
    }
}
