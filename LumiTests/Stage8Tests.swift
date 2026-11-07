import Foundation
import SwiftData
import Testing
import UIKit
import ZIPFoundation
@testable import Lumi

@MainActor struct BackupTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "app.lumi.backup.tests." + UUID().uuidString)! }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func seed(_ context: ModelContext, root: URL) throws -> (LumiCharacter, ProviderConfig) {
        let friend = LumiCharacter(name: "Fixture", personaPrompt: "Persona"); friend.pinnedAt = .now; friend.affection = 59
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { renderer in UIColor.orange.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }.pngData()!
        friend.avatarData = image; friend.portraitData = image; context.insert(friend)
        let config = ProviderConfig(); context.insert(config)
        let conversation = Conversation(characterID: friend.id, title: friend.name); context.insert(conversation)
        let user = Message(conversationID: conversation.id, role: "user", content: "Roundtrip")
        user.attachments = [ChatAttachment(name: "notes.txt", isImage: false, data: Data("full file".utf8), text: "full file"), ChatAttachment(name: "photo.jpg", isImage: true, data: image)]
        user.voiceData = Data("local-audio-fixture".utf8); user.voiceDuration = 2.5
        user.memes = [SentMeme(caption: "snapshot", data: image)]; context.insert(user)
        let reply = Message(conversationID: conversation.id, role: "assistant", content: "Hello", replyToID: user.id); context.insert(reply)
        let memory = MemoryFact(characterID: friend.id, category: "喜好", text: "Tea", sourceMessageID: user.id); memory.pinOrder = 2; context.insert(memory)
        let profile = UserProfile(characterID: friend.id); profile.summary = "Profile"; profile.lastExtractedAt = .now; context.insert(profile)
        context.insert(Anniversary(characterID: friend.id, title: "Birthday", date: .now))
        context.insert(DiaryEntry(characterID: friend.id, day: "2026-11-01", content: "Diary"))
        context.insert(AffectionAward(characterID: friend.id, userMessageID: user.id, fingerprint: "fingerprint", delta: 2, createdAt: .now))
        context.insert(ScheduledGreeting(characterID: friend.id, fireDate: .now.addingTimeInterval(86400), text: "Hi", scenario: "早安"))
        let post = MomentPost(content: "Moment", images: user.attachments); post.comments = [MomentComment(text: "Comment")]; post.liked = true; context.insert(post)
        let pack = MemePack(name: "Pack"); context.insert(pack)
        let meme = Meme(packID: pack.id, fileName: "fixture.png", caption: "Meme"); meme.usageCount = 4; context.insert(meme)
        let target = root.appendingPathComponent(pack.id.uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); try image.write(to: target.appendingPathComponent(meme.fileName))
        let skill = InstalledSkill(SkillLibrary.examples[0]); skill.enabled = false; context.insert(skill)
        let group = GroupChat(name: "Group", memberIDs: [friend.id]); group.sharesMemory = true; context.insert(group)
        context.insert(GroupMessage(groupID: group.id, role: "user", text: "Group turn", mentionedIDs: [friend.id]))
        let perspective = GroupPerspective(groupID: group.id, characterID: friend.id); perspective.summary = "Group memory"; context.insert(perspective)
        let usage = TokenUsageRecord(id: UUID(), endpoint: config.endpoint.function(.chat).attributed(to: friend))
        usage.input = 2_000_000_000; usage.output = 400; usage.hasUsage = true; context.insert(usage)
        let data = try CharacterCard(name: friend.name, personaPrompt: "Persona").encoded()
        let item = MarketItem(id: "fixture", type: .character, name: "Fixture", author: "Tests", summary: "Test", version: "1.0.0", downloadURL: "https://example.invalid/card.json", sha256: MarketDigest.sha(data), size: data.count, license: "CC0")
        let receipt = try MarketInstallation(sourceID: "fixture", item: item, data: data); receipt.targetIDs = [friend.id]; receipt.previousItemData = receipt.itemData; receipt.previousPackageData = data; context.insert(receipt)
        try context.save(); return (friend, config)
    }
    private func canonical(_ snapshot: LumiBackup) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "createdAt")
        // SwiftData fetch order is unspecified; compare records by stable identity.
        for (key, value) in object {
            if let rows = value as? [[String: Any]] { object[key] = rows.sorted { String(describing: $0["id"]!) < String(describing: $1["id"]!) } }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    @Test func completeRoundtripAllNineteenModelsAttachmentsAndNoKey() async throws {
        let source = try container(); let sourceRoot = root(); let destinationRoot = root()
        defer { try? FileManager.default.removeItem(at: sourceRoot); try? FileManager.default.removeItem(at: destinationRoot) }
        let (_, provider) = try seed(source.mainContext, root: sourceRoot)
        let prefs = defaults(); prefs.set("rounded", forKey: "theme.font"); prefs.set(22, forKey: "theme.textSize")
        prefs.set("never-export-this-key", forKey: "apiKey"); prefs.set(true, forKey: "tools.allow.test")
        let keychain = KeychainStore(service: "app.lumi.backup.test." + UUID().uuidString)
        try keychain.save("keychain-private-marker", for: provider.id); defer { try? keychain.delete(for: provider.id) }
        let original = try LumiBackup.capture(source.mainContext, defaults: prefs)
        let zip = try await BackupArchive.export(context: source.mainContext, defaults: prefs, memeRoot: sourceRoot)
        defer { try? FileManager.default.removeItem(at: zip) }
        let prepared = try BackupArchive.prepare(zip); defer { prepared.cleanup() }
        let json = try Data(contentsOf: prepared.directory.appendingPathComponent("lumi.json"))
        #expect(!String(decoding: json, as: UTF8.self).contains("keychain-private-marker"))
        #expect(!String(decoding: json, as: UTF8.self).contains("never-export-this-key"))
        #expect(!String(decoding: json, as: UTF8.self).contains("tools.allow"))
        let destination = try container(); let restoredPrefs = defaults()
        try BackupArchive.restore(prepared, replacing: true, container: destination, defaults: restoredPrefs, memeRoot: destinationRoot, systemEffects: false)
        let restored = try LumiBackup.capture(ModelContext(destination), defaults: restoredPrefs)
        #expect(try canonical(original) == canonical(restored))
        #expect(try Data(contentsOf: MemeStore.url(try #require(destination.mainContext.fetch(FetchDescriptor<Meme>()).first), root: destinationRoot)) == Data(contentsOf: sourceRoot.appendingPathComponent(prepared.snapshot.memes[0].packID.uuidString).appendingPathComponent("fixture.png")))
        #expect(try keychain.read(for: provider.id) == "keychain-private-marker")
    }
    @Test func mergeKeepsExistingAndReplaceUpdatesThenRemovesExtra() throws {
        let source = try container(); let destination = try container()
        let friend = LumiCharacter(name: "Backup"); source.mainContext.insert(friend); try source.mainContext.save()
        let snapshot = try LumiBackup.capture(source.mainContext, defaults: defaults())
        let prepared = PreparedBackup(snapshot: snapshot, directory: root())
        let same = LumiCharacter(id: friend.id, name: "Local"); destination.mainContext.insert(same)
        let extra = LumiCharacter(name: "Keep on merge"); destination.mainContext.insert(extra); try destination.mainContext.save()
        let prefs = defaults(); prefs.set(true, forKey: "tools.allow.test")
        try BackupArchive.restore(prepared, replacing: false, container: destination, defaults: prefs, memeRoot: root(), systemEffects: false)
        var rows = try ModelContext(destination).fetch(FetchDescriptor<LumiCharacter>())
        #expect(rows.count == 2); #expect(rows.first { $0.id == friend.id }?.name == "Local")
        #expect(!prefs.bool(forKey: "tools.allow.test"))
        try BackupArchive.restore(prepared, replacing: true, container: destination, defaults: prefs, memeRoot: root(), systemEffects: false)
        rows = try ModelContext(destination).fetch(FetchDescriptor<LumiCharacter>())
        #expect(rows.count == 1); #expect(rows.first?.id == friend.id); #expect(rows.first?.name == "Backup")
    }
    @Test func missingMemeFileAbortsBeforeDatabaseChanges() async throws {
        let source = try container(); let files = root(); defer { try? FileManager.default.removeItem(at: files) }
        _ = try seed(source.mainContext, root: files)
        let zip = try await BackupArchive.export(context: source.mainContext, defaults: defaults(), memeRoot: files); defer { try? FileManager.default.removeItem(at: zip) }
        let prepared = try BackupArchive.prepare(zip); defer { prepared.cleanup() }
        let path = try #require(prepared.snapshot.files.keys.first)
        try Data("tampered".utf8).write(to: prepared.directory.appendingPathComponent(path))
        let destination = try container(); let existing = LumiCharacter(name: "Preserved"); destination.mainContext.insert(existing); try destination.mainContext.save()
        #expect(throws: (any Error).self) { try BackupArchive.restore(prepared, replacing: true, container: destination, defaults: defaults(), memeRoot: root(), systemEffects: false) }
        #expect(try destination.mainContext.fetch(FetchDescriptor<LumiCharacter>()).first?.name == "Preserved")
    }
    @Test(arguments: ["../lumi.json", "/lumi.json", "memes/not-a-uuid/x.png", "memes/ABC/../../outside", "script.js"])
    func rejectsUnsafeArchivePaths(_ path: String) throws {
        let url = root().appendingPathExtension("zip"); defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create); let data = Data("{}".utf8)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in data.subdata(in: Int(offset)..<(Int(offset) + size)) }
        #expect(throws: (any Error).self) { try BackupArchive.prepare(url) }
    }
    @Test func rejectsDuplicateIdentityBrokenGraphUnknownSettingsAndVersion() throws {
        let store = try container(); let friend = LumiCharacter(); store.mainContext.insert(friend); try store.mainContext.save()
        var snapshot = try LumiBackup.capture(store.mainContext, defaults: defaults())
        snapshot.lumiCharacters.append(snapshot.lumiCharacters[0])
        #expect(throws: BackupError.invalid) { try snapshot.validate() }
        snapshot.lumiCharacters.removeLast(); snapshot.messages = [BackupMessage(Message(conversationID: UUID(), role: "user", content: "Orphan"))]
        #expect(throws: BackupError.invalid) { try snapshot.validate() }
        snapshot.messages = []; snapshot.preferences["apiKey"] = .text("secret")
        #expect(throws: BackupError.limit) { try snapshot.validate() }
        snapshot.preferences = [:]; snapshot.version = 999
        #expect(throws: BackupError.version) { try snapshot.validate() }
    }
}

@MainActor struct Stage8ExperienceTests {
    @Test func periodsRespectLocalMidnightAndMonthBoundariesAndClassifyOldRecords() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = ISO8601DateFormatter().date(from: "2026-11-02T00:30:00+08:00")!
        func row(_ date: String, amount: Int64, category: TokenFunction?) -> TokenUsageRecord {
            let record = TokenUsageRecord(id: UUID(), endpoint: ProviderEndpoint(baseURL: "https://example.invalid", model: "test"))
            record.createdAt = ISO8601DateFormatter().date(from: date)!; record.input = amount; record.hasUsage = true; record.functionRaw = category?.rawValue; return record
        }
        let records = [row("2026-11-02T00:00:00+08:00", amount: 10, category: .chat),
                       row("2026-11-01T23:59:59+08:00", amount: 20, category: .memory),
                       row("2026-10-31T23:59:59+08:00", amount: 100, category: .chat),
                       row("2026-12-01T00:00:00+08:00", amount: 1000, category: .chat),
                       row("2026-11-01T00:00:00+08:00", amount: 5, category: nil)]
        let totals = UsagePeriodTotals(records: records, now: now, calendar: calendar)
        #expect(totals.today == 10); #expect(totals.month == 35)
        #expect(totals.categories[.chat] == 10); #expect(totals.categories[.memory] == 20); #expect(totals.categories[.unclassified] == 5)
        #expect(UsagePeriodTotals(records: records, now: now, calendar: calendar, monthly: false).categories == [.chat: 10])
    }
    @Test func readsEmbeddedProfileAndHandlesFallbackAndLateReminder() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": date], format: .xml, options: 0)
        let profile = Data([0, 0xFF, 2]) + plist + Data([0xFF])
        #expect(SigningExpiry.expiration(profile: profile) == date)
        #expect(SigningExpiry.expiration(profile: Data("invalid".utf8)) == nil)
        let now = date.addingTimeInterval(-3 * 86400)
        #expect(SigningExpiry.reminderDate(expiration: date, now: now) == date.addingTimeInterval(-2 * 86400))
        #expect(SigningExpiry.reminderDate(expiration: date, now: date.addingTimeInterval(-3600)) == date.addingTimeInterval(-3595))
        #expect(SigningExpiry.reminderDate(expiration: date, now: date) == nil)
        #expect(SigningExpiry.estimatedExpiration(installed: now) == now.addingTimeInterval(7 * 86400))
    }
    @Test func conversationExportsEscapeHTMLAndKeepJSONAttachments() throws {
        let message = Message(conversationID: UUID(), role: "user", content: "<script>alert('private')</script> & \"hello\"")
        message.attachments = [ChatAttachment(name: "<file>.txt", isImage: false, data: Data("original".utf8), text: "<iframe>bad</iframe>")]
        let line = SharedChatLine(message, friend: "Friend")
        let html = String(decoding: ConversationExport.html([line], title: "<title>"), as: UTF8.self)
        #expect(!html.contains("<script>")); #expect(!html.contains("<iframe>")); #expect(html.contains("&lt;script&gt;"))
        #expect(html.contains("default-src 'none'")); #expect(!html.contains("<title><title>"))
        let object = try #require(JSONSerialization.jsonObject(with: ConversationExport.json([line], title: "Friend")) as? [String: Any])
        let rows = try #require(object["messages"] as? [[String: Any]])
        #expect(rows.count == 1); #expect(rows[0]["text"] as? String == message.content)
        let attachments = try #require(rows[0]["attachments"] as? [[String: Any]])
        #expect(attachments[0]["data"] as? String == Data("original".utf8).base64EncodedString())
    }
    @Test func audioAndIconAssetsAreIncluded() throws {
        #expect(UIImage(named: "LumiLogo") != nil)
        let data = SleepSession.ambience()
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(data.count == 44 + 22_050 * 6 * 2)
        let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let alternate = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        #expect(Set(alternate.keys) == ["AppIconDawn", "AppIconOcean", "AppIconNight"])
        #expect(!PromptBuilder.resource("SafetyAssessment").isEmpty)
    }
}

struct Stage8SafetyTests {
    @Test(arguments: ["我想自杀", "我 不 想 活 了", "I want to die", "I'm going to kill myself"])
    func immediateRules(_ text: String) { #expect(SafetyGuard.isCrisis(text)) }
    @Test func semanticAssessmentAndUncertaintyFailSafe() async throws {
        let endpoint = ProviderEndpoint(baseURL: "https://example.invalid", model: "test")
        #expect(try await SafetyGuard.assess("我希望永远睡着", client: SequenceCompletionClient([#"{"crisis":true}"#]), endpoint: endpoint, key: "fake"))
        #expect(try await !SafetyGuard.assess("小说人物写了最后一封信，我在分析写法", client: SequenceCompletionClient([#"{"crisis":false}"#]), endpoint: endpoint, key: "fake"))
        #expect(try await SafetyGuard.assess("我希望永远睡着", client: SequenceCompletionClient(["not json"]), endpoint: endpoint, key: "fake"))
        #expect(try await SafetyGuard.assess("我希望永远睡着", client: SequenceCompletionClient([]), endpoint: endpoint, key: ""))
        let client = SequenceCompletionClient([])
        #expect(try await !SafetyGuard.assess("今天想吃冰淇淋", client: client, endpoint: endpoint, key: "fake"))
        #expect(client.count == 0)
    }
    @MainActor @Test func crisisBypassesRoleplayToolsAndAffectionWithoutKey() async throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let provider = ProviderConfig(); let character = LumiCharacter(name: "Test", personaPrompt: "Always flirt")
        store.mainContext.insert(provider); store.mainContext.insert(character); try store.mainContext.save()
        let client = SequenceCompletionClient([]); let model = ChatModel(client: client, keychain: KeychainStore(service: UUID().uuidString), automaticMaintenance: false)
        model.configure(context: store.mainContext, provider: provider, character: character)
        model.send("我希望永远睡着")
        for _ in 0..<100 { if !model.isGenerating { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.messages.last?.content == SafetyGuard.support)
        #expect(character.affection == 0); #expect(client.count == 0); #expect(model.messages.last?.memes.isEmpty == true)
    }
}

@MainActor struct Stage8ActivityAndGroupSafetyTests {
    @Test func liveActivityHidesMessagesUntilOptInAndFindsAnniversary() throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let friend = LumiCharacter(name: "Friend"); friend.affection = 40; store.mainContext.insert(friend)
        let conversation = Conversation(characterID: friend.id, title: "Private"); store.mainContext.insert(conversation)
        store.mainContext.insert(Message(conversationID: conversation.id, role: "assistant", content: "Private reply"))
        store.mainContext.insert(Anniversary(characterID: friend.id, title: "Tomorrow", date: .now.addingTimeInterval(86400), repeatsYearly: false)); try store.mainContext.save()
        let hidden = try CompanionActivity.state(character: friend, context: store.mainContext, showMessage: false)
        #expect(hidden.latest.isEmpty); #expect(hidden.affection == 40); #expect(hidden.anniversaryTitle == "Tomorrow")
        #expect(hidden.anniversaryDate != nil)
        #expect(try CompanionActivity.state(character: friend, context: store.mainContext, showMessage: true).latest == "Private reply")
    }
    @Test func groupCrisisStopsAllRoleplayAndAutomaticRoundsWithoutKey() async throws {
        let store = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let provider = ProviderConfig(); let friends = [LumiCharacter(name: "A"), LumiCharacter(name: "B")]
        store.mainContext.insert(provider); friends.forEach { store.mainContext.insert($0) }
        let group = GroupChat(name: "Group", memberIDs: friends.map(\.id)); group.automaticChat = true; store.mainContext.insert(group); try store.mainContext.save()
        let client = SequenceCompletionClient([])
        let model = GroupChatModel(client: client, keychain: KeychainStore(service: UUID().uuidString), typingDelay: .zero, idleDelay: .milliseconds(1))
        model.configure(group: group, provider: provider, context: store.mainContext)
        model.send("我想自杀")
        for _ in 0..<100 { if !model.isGenerating { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.messages.last?.role == "system"); #expect(model.messages.last?.text == SafetyGuard.support)
        #expect(!model.waitingForAutomatic); #expect(client.count == 0); #expect(friends.allSatisfy { $0.affection == 0 })
    }
}
