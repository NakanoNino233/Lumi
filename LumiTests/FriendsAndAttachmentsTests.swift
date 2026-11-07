import Foundation
import Testing
import SwiftData
@testable import Lumi

struct FriendGenerationTests {
    let output = #"{"personaPrompt":"以直观实验理解世界，坦诚不确定性。","speechStyle":"简短、好奇，先问再解释。","taboos":"不冒充真人，不编造来源。","backgroundStory":"受物理学家启发的虚构好友。","firstGreeting":"今天有什么让你好奇？"}"#
    @Test func validatesSourceAndKeepsSpeakerInData() throws {
        let input = FriendGenerationInput(mode: .history, name: "阿云", category: "", details: "温柔", history: "我：爱喝茶\n阿云：我喜欢咖啡", speaker: "阿云")
        let prompt = try FriendGenerator.prompt(input)
        #expect(prompt.count == 2)
        let data = try #require(prompt.last?.content.data(using: .utf8))
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(fields["targetSpeaker"] == "阿云")
        #expect(fields["chatHistory"] == input.history)
        var invalid = input; invalid.speaker = " "
        #expect(throws: FriendGenerationError.input) { try invalid.validated() }
        invalid = input; invalid.history = String(repeating: "a", count: 60_001)
        #expect(throws: FriendGenerationError.input) { try invalid.validated() }
    }
    @Test func outputValidationAndHonestIdentity() throws {
        let card = try FriendGenerator.decode("```json\n" + output + "\n```", name: "费曼", existingNames: [])
        #expect(card.name == "费曼")
        #expect(card.personaPrompt.contains("不是真实本人"))
        #expect(throws: CharacterCardError.duplicate) { try FriendGenerator.decode(output, name: "费曼", existingNames: ["费曼"]) }
        #expect(throws: FriendGenerationError.output) { try FriendGenerator.decode("{\"personaPrompt\":\"hello\"}", name: "test", existingNames: []) }
    }
    @Test func generationUsesConfiguredClient() async throws {
        let client = SequenceCompletionClient([output])
        let input = FriendGenerationInput(mode: .name, name: "费曼", category: "名人", details: "科普", history: "", speaker: "")
        let card = try await FriendGenerator(client: client).generate(input: input, endpoint: ProviderEndpoint(baseURL: "https://example.com", model: "m"), key: "fake-local-key", existingNames: [])
        #expect(card.name == "费曼"); #expect(client.count == 1)
    }
}

struct AttachmentTransportTests {
    @Test func textTransportRemainsStringAndImagesUseParts() throws {
        let plain = ChatTurn(role: "user", content: "hello")
        let text = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as! [String: Any]
        #expect(text["content"] as? String == "hello")
        let image = ChatTurn(role: "user", content: "描述", imageURLs: ["data:image/jpeg;base64,dGVzdA=="])
        let data = try JSONEncoder().encode(image)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let parts = object["content"] as! [[String: Any]]
        #expect(parts.count == 2); #expect(parts[1]["type"] as? String == "image_url")
        #expect(try JSONDecoder().decode(ChatTurn.self, from: data) == image)
    }
    @Test func fileTextIsBoundedAndBinaryIsNotSent() throws {
        let attachment = try ChatAttachment.file(Data(String(repeating: "文", count: 10000).utf8), name: "notes.txt")
        #expect(attachment.truncated)
        #expect(attachment.text.utf8.count <= 20_000)
        let turn = ChatAttachment.turn(role: "user", content: "帮我读读", attachments: [attachment, attachment], supportsVision: false)
        #expect(turn.content.utf8.count < 7000)
        #expect(turn.content.contains("节选")); #expect(turn.imageURLs.isEmpty)
        #expect(throws: AttachmentError.type) { try ChatAttachment.file(Data([1, 2]), name: "program.exe") }
        #expect(throws: AttachmentError.unreadable) { try ChatAttachment.file(Data(), name: "empty.txt") }
        #expect(throws: AttachmentError.size) { try ChatAttachment.file(Data(repeating: 0, count: 5_000_001), name: "large.txt") }
    }
    @Test func imageGateAndCountLimits() {
        let image = ChatAttachment(name: "test.jpg", isImage: true, data: Data([1, 2]))
        #expect(throws: AttachmentError.vision) { try ChatAttachment.validate([image], supportsVision: false) }
        #expect(throws: AttachmentError.size) { try ChatAttachment.validate(Array(repeating: image, count: 5), supportsVision: true) }
    }
    @MainActor @Test func promptClippingPreservesCurrentImage() {
        let character = LumiCharacter(name: "test", personaPrompt: "friendly")
        let prompt = PromptBuilder.build(persona: PromptPersona(character), profile: "", memories: [], recent: [ChatTurn(role: "user", content: String(repeating: "x", count: 50_000), imageURLs: ["data:image/jpeg;base64,AA=="])])
        #expect(prompt.turns.last?.imageURLs.count == 1)
    }
}

@MainActor struct FriendsStorageTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    @Test func queuedAttachmentsSurviveReloadAndDeletion() async throws {
        let container = try container(); let context = ModelContext(container)
        let provider = ProviderConfig(); provider.supportsVision = true; context.insert(provider)
        let friend = LumiCharacter(name: "附件测试", personaPrompt: "friendly"); context.insert(friend)
        let keychain = KeychainStore(service: "app.lumi.attachment-tests.\(UUID())")
        try keychain.save("fake-local-key", for: provider.id)
        let gate = GateClient(); let model = ChatModel(client: gate, keychain: keychain, automaticMaintenance: false)
        defer { model.stop(); try? keychain.delete(for: provider.id) }
        model.configure(context: context, provider: provider, character: friend)
        let attachment = try ChatAttachment.file(Data("明天去公园".utf8), name: "plan.txt")
        #expect(model.send("看看计划", attachments: [attachment]))
        for _ in 0..<100 { if gate.count > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.count == 1)
        #expect(gate.request(0).last?.content.contains("明天去公园") == true)
        let user = try #require(model.messages.first { $0.role == "user" })
        let read = ModelContext(container)
        let saved = try #require(read.fetch(FetchDescriptor<Message>()).first { $0.id == user.id })
        #expect(saved.attachments == [attachment])
        model.delete(user)
        #expect(try context.fetch(FetchDescriptor<Message>()).allSatisfy { $0.id != user.id })
    }
    @Test func unsupportedImageDoesNotCreateOrSendMessage() throws {
        let container = try container(); let context = ModelContext(container)
        let model = ChatModel(automaticMaintenance: false); let provider = ProviderConfig()
        provider.supportsVision = false
        context.insert(provider); model.configure(context: context, provider: provider)
        let image = ChatAttachment(name: "test.jpg", isImage: true, data: Data([1]))
        #expect(!model.send("", attachments: [image]))
        #expect(model.messages.isEmpty); #expect(model.errorMessage != nil)
    }
    @Test func momentsPersistLikesCommentsAndPhotos() throws {
        let container = try container(); let context = ModelContext(container)
        let image = ChatAttachment(name: "test.jpg", isImage: true, data: Data([1]))
        let post = MomentPost(content: "今天很好", images: [image]); post.liked = true
        let comment = MomentComment(text: "记住了"); post.comments.append(comment)
        context.insert(post); try context.save()
        let read = ModelContext(container); let saved = try #require(read.fetch(FetchDescriptor<MomentPost>()).first)
        #expect(saved.images == [image]); #expect(saved.liked); #expect(saved.comments.first?.id == comment.id)
        context.delete(post); try context.save(); #expect(try context.fetch(FetchDescriptor<MomentPost>()).isEmpty)
    }
    @Test func notificationHasExplicitPendingDestination() {
        let router = ConversationRouter.shared
        let old = router.pendingCharacterID
        let selection = AppPreferences.defaults.string(forKey: "selectedCharacter")
        defer { router.pendingCharacterID = old; AppPreferences.defaults.set(selection, forKey: "selectedCharacter") }
        let id = UUID(); router.open(characterID: id)
        #expect(router.pendingCharacterID == id)
        #expect(AppPreferences.defaults.string(forKey: "selectedCharacter") == id.uuidString)
        router.pendingCharacterID = nil; router.revision = UUID()
        #expect(router.pendingCharacterID == nil)
    }
}
