import Foundation
import SwiftData
import Testing
@testable import Lumi

struct ReplyDeliveryTests {
    @Test func naturalParagraphsBecomeSeparateBubbles() {
        #expect(ReplyDelivery.parts("都九点半多了，晚上。\n\n怎么，自己没看时间就问我？……还是说，你在等什么事？") == ["都九点半多了，晚上。", "怎么，自己没看时间就问我？……还是说，你在等什么事？"])
        #expect(ReplyDelivery.parts("第一段。   第二段。") == ["第一段。", "第二段。"])
        #expect(ReplyDelivery.parts("第一行\n第二行") == ["第一行\n第二行"])
        #expect(ReplyDelivery.parts("```swift\nlet a = 1\n\nprint(a)\n```").count == 1)
        #expect(ReplyDelivery.parts("a\n\nb\n\nc\n\nd\n\ne").count == 4)
    }
    @Test func bottomDetectionHandlesShortContentBounceAndActualDistance() {
        #expect(TranscriptPosition.isAtBottom(bottom: 500, viewport: 700))
        #expect(TranscriptPosition.isAtBottom(bottom: 730, viewport: 700))
        #expect(!TranscriptPosition.isAtBottom(bottom: 900, viewport: 700))
    }
}

@MainActor struct ChatExperienceTests {
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        Issue.record("Chat state did not settle")
    }
    @Test func leavingPrivateChatKeepsReplyAndPersistsBothParagraphs() async throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext; let provider = ProviderConfig(); let friend = LumiCharacter(name: "Fixture")
        context.insert(provider); context.insert(friend)
        let keychain = KeychainStore(service: UUID().uuidString); try keychain.save("fake-local-test-key", for: provider.id)
        let client = GateClient(); let model = ChatModel(client: client, keychain: keychain, automaticMaintenance: false)
        defer { model.stop(); try? keychain.delete(for: provider.id); ChatReadState.shared.remove(friend.id) }
        model.configure(context: context, provider: provider, character: friend)
        ChatReadState.shared.enter(friend.id)
        #expect(model.send("今晚聊聊")); try await waitFor { client.count == 1 }
        model.endSession(); ChatReadState.shared.leave(friend.id)
        #expect(model.isGenerating)
        client.yield("都九点半多了，晚上。\n\n还是说，你在等什么事？", index: 0); client.finish(0)
        try await waitFor { !model.isGenerating }
        let replies = model.messages.filter { $0.role == "assistant" }
        #expect(replies.map(\.content) == ["都九点半多了，晚上。", "还是说，你在等什么事？"])
        #expect(replies.allSatisfy { $0.status == .complete && $0.createdAt > ChatReadState.shared.lastRead(friend.id) })
        let restored = try ModelContext(container).fetch(FetchDescriptor<Message>()).filter { $0.role == "assistant" }
        #expect(restored.count == 2)
        ChatReadState.shared.enter(friend.id)
        #expect(restored.allSatisfy { $0.createdAt <= ChatReadState.shared.lastRead(friend.id) })
    }
    @Test func bufferedReplyDoesNotLeakBeforeTypingDelayOrAfterStop() async throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext; let provider = ProviderConfig(); context.insert(provider)
        let keychain = KeychainStore(service: UUID().uuidString); try keychain.save("fake-local-test-key", for: provider.id)
        let client = GateClient(); let model = ChatModel(client: client, keychain: keychain, automaticMaintenance: false, simulatesTyping: true)
        defer { model.stop(); try? keychain.delete(for: provider.id) }
        model.configure(context: context, provider: provider)
        model.send("今天过得怎么样"); try await waitFor { client.count == 1 }
        client.yield("我刚忙完。\n\n你呢？", index: 0); client.finish(0)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.isGenerating)
        #expect(model.messages.last?.content.isEmpty == true)
        model.stop(); try await Task.sleep(for: .milliseconds(50))
        #expect(!model.messages.contains { $0.content == "我刚忙完。" || $0.content == "你呢？" })
    }
    @Test func automaticGroupChatContinuesAfterLeavingAndCreatesUnreadMessages() async throws {
        let h = try GroupHarness(idle: .milliseconds(30)); defer { h.clean(); ChatReadState.shared.remove(h.group.id) }
        h.group.automaticChat = true; h.group.automaticRounds = 1; h.group.automaticBudget = 100_000
        ChatReadState.shared.enter(h.group.id)
        h.model.send("\(h.everyone) 一起聊聊")
        ChatReadState.shared.leave(h.group.id)
        await h.model.waitUntilIdle()
        #expect(h.client.requests.count == 2)
        #expect(h.model.messages.contains { $0.role == "assistant" && $0.replyToID == nil && $0.createdAt > ChatReadState.shared.lastRead(h.group.id) })
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<GroupMessage>()) == h.model.messages.count)
    }
    @Test func sessionRegistryReusesModelsAndRemovalEndsOwnership() {
        let id = UUID(); let sessions = ChatSessions()
        let first = sessions.group(for: id)
        #expect(first === sessions.group(for: id))
        sessions.removeGroup(id)
        #expect(first !== sessions.group(for: id))
        let friend = UUID()
        #expect(sessions.chat(for: friend) === sessions.chat(for: friend))
        sessions.reset()
    }
    @Test func voicePersistsWithTranscriptAndLegacyBackupStillDecodes() throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext; let provider = ProviderConfig(); context.insert(provider)
        let model = ChatModel(automaticMaintenance: false); model.configure(context: context, provider: provider)
        let voice = RecordedVoice(data: Data("audio-fixture".utf8), duration: 2.5, transcript: "晚上好")
        #expect(model.send(voice.transcript, requestReply: false, voice: voice))
        let saved = try #require(context.fetch(FetchDescriptor<Message>()).last)
        #expect(saved.voiceData == voice.data); #expect(saved.voiceDuration == 2.5); #expect(saved.content == voice.transcript)
        let record = BackupMessage(saved)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BackupMessage.self, from: encoded)
        #expect(decoded.voiceData == voice.data)
        var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "voiceData"); old.removeValue(forKey: "voiceDuration")
        let legacy = try JSONDecoder().decode(BackupMessage.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.voiceData == nil); #expect(legacy.voiceDuration == nil)
    }
}
