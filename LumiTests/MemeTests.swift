import Foundation
import Testing
import SwiftData
import UIKit
import ImageIO
@testable import Lumi

private final class MemeFixtureLocator: NSObject { }
private func memeFixture(_ name: String) throws -> URL {
    let bundle = Bundle(for: MemeFixtureLocator.self)
    return try #require(bundle.url(forResource: name, withExtension: "zip") ?? bundle.url(forResource: name, withExtension: "zip", subdirectory: "Fixtures"))
}
private func starter() throws -> PreparedMemePack {
    try MemeArchive.prepare(try #require(Bundle.main.url(forResource: "Lumi-Starter-Memes", withExtension: "zip")))
}

struct MemeArchiveTests {
    @Test func originalPackHasTwelveImagesAndAttribution() throws {
        let pack = try starter(); defer { try? FileManager.default.removeItem(at: pack.directory) }
        #expect(pack.memes.count == 12); #expect(pack.license == "CC0-1.0")
        #expect(pack.source.contains("Lumi")); #expect(pack.memes.allSatisfy { !$0.caption.isEmpty && !$0.keywords.isEmpty })
    }
    @Test func plainImageZIPAccepted() throws {
        let pack = try MemeArchive.prepare(memeFixture("plain")); defer { try? FileManager.default.removeItem(at: pack.directory) }
        #expect(pack.memes.count == 1); #expect(pack.memes[0].path == "folder/happy.png")
    }
    @Test(arguments: ["traversal", "absolute", "backslash", "duplicates", "symlink"])
    func unsafeZIPRejected(name: String) throws {
        #expect(throws: MemeError.unsafePath) { try MemeArchive.prepare(memeFixture(name)) }
    }
    @Test(arguments: ["bad-image", "bad-type", "bad-checksum", "malformed-checksum", "bad-crc", "declared-size", "bomb", "missing-index-image"])
    func damagedZIPRejected(name: String) throws {
        #expect(throws: (any Error).self) { try MemeArchive.prepare(memeFixture(name)) }
    }
    @Test(arguments: ["../a.png", "a/../b.png", "/tmp/a.png", "a\\b.png", "C:a.png", "a//b.png", "./a.png", "a\u{0}b.png"])
    func rejectsUnsafePaths(path: String) { #expect(throws: MemeError.unsafePath) { try MemeArchive.safePath(path) } }
    @Test func exportPreservesImageBytesMetadataAndHashes() throws {
        let source = try starter(); defer { try? FileManager.default.removeItem(at: source.directory) }
        let first = source.memes[0]; let file = source.directory.appendingPathComponent(first.path)
        let zip = try MemeArchive.export(name: "往返", summary: "描述", license: "CC0", source: "source", items: [ExportMeme(file: file, caption: "抱抱", keywords: "安慰", mood: "comfort", source: "per-image source", license: "per-image license")])
        defer { try? FileManager.default.removeItem(at: zip) }
        let result = try MemeArchive.prepare(zip); defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(result.name == "往返"); #expect(result.memes[0].caption == "抱抱"); #expect(result.memes[0].mood == "comfort")
        #expect(result.memes[0].source == "per-image source"); #expect(result.memes[0].license == "per-image license")
        #expect(try Data(contentsOf: result.directory.appendingPathComponent(result.memes[0].path)) == Data(contentsOf: file))
    }
}

struct MemeParsingTests {
    @Test func everyStreamingBoundaryHidesMarkers() {
        let full = "你好[表情 : 开心]再见［表情：抱抱］"
        for end in full.indices {
            let prefix = String(full[..<end]); let result = MemeReplyParser.parse(prefix, final: false)
            #expect(!result.text.contains("[")); #expect(!result.text.contains("［"))
            #expect(!result.text.contains("表情")); #expect(!result.text.contains("开心")); #expect(!result.text.contains("抱抱"))
        }
        let final = MemeReplyParser.parse(full, final: true) { _ in "" }
        #expect(final.text == "你好再见"); #expect(final.requests.map(\.keyword) == ["开心", "抱抱"])
    }
    @Test func missingMatchFallsBackToDescription() {
        #expect(MemeReplyParser.parse("你好[表情: 火星鲸鱼]", final: true).text == "你好火星鲸鱼")
        #expect(MemeReplyParser.parse("你好[表情: 开心", final: true).text == "你好开心")
        #expect(MemeReplyParser.parse("你好[表", final: true).text == "你好")
        #expect(MemeReplyParser.parse("[普通备注]", final: true).text == "[普通备注]")
        #expect(MemeReplyParser.parse("[表情: ]", final: true).text == "")
    }
    @MainActor @Test func matcherUsesKeywordsMoodAndExclusion() {
        let pack = UUID()
        let happy = MemeCandidate(Meme(packID: pack, fileName: "a.png", caption: "开心", keywords: "收到 好的 笑", mood: "happy"))
        let comfort = MemeCandidate(Meme(packID: pack, fileName: "b.png", caption: "抱抱", keywords: "陪伴 安慰", mood: "comfort"))
        #expect(MemeMatcher.best(keyword: "收到", candidates: [happy, comfort])?.id == happy.id)
        #expect(MemeMatcher.best(keyword: "", mood: "温柔", candidates: [happy, comfort])?.id == comfort.id)
        #expect(MemeMatcher.best(keyword: "不存在的火星飞艇", candidates: [happy, comfort]) == nil)
        #expect(MemeMatcher.best(keyword: "收到", candidates: [happy], excluding: [happy.id]) == nil)
        #expect(MemePreferences.prompt(enabled: false, candidates: [happy]).isEmpty)
        #expect(!MemePreferences.prompt(enabled: true, candidates: [happy]).isEmpty)
    }
    @Test func nativeToolFragmentsValidateAtEnd() throws {
        var accumulator = MemeToolAccumulator()
        let first = #"{"choices":[{"delta":{"reasoning_content":"hidden","tool_calls":[{"index":0,"function":{"name":"send_","arguments":"{\"keyword\":\""}}]}}]}"#
        let second = #"{"choices":[{"delta":{"content":"给你一个拥抱","tool_calls":[{"index":0,"function":{"name":"meme","arguments":"抱抱\",\"mood\":\"comfort\"}"}}]}}]}"#
        #expect(try accumulator.consume(first) == nil)
        #expect(try accumulator.consume(second) == "给你一个拥抱")
        #expect(try accumulator.finish() == [MemeRequest(keyword: "抱抱", mood: "comfort")])
    }
    @Test(arguments: ["delete_files", "send_meme"])
    func invalidToolIsRejected(name: String) throws {
        let arguments = name == "send_meme" ? #"{"keyword":"开心","path":"/tmp/private"}"# : #"{"keyword":"开心"}"#
        let object: [String: Any] = ["choices": [["delta": ["tool_calls": [["index": 0, "function": ["name": name, "arguments": arguments]]]]]]]
        var accumulator = MemeToolAccumulator()
        _ = try accumulator.consume(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self))
        #expect(throws: LLMError.invalidResponse) { try accumulator.finish() }
    }
    @Test func boundedToolArguments() throws {
        let object: [String: Any] = ["choices": [["delta": ["tool_calls": [["index": 0, "function": ["name": "send_meme", "arguments": String(repeating: "a", count: 4097)]]]]]]]
        var accumulator = MemeToolAccumulator()
        #expect(throws: LLMError.responseTooLarge) { try accumulator.consume(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)) }
    }
    @Test func toolDefinitionOmittedWhenDisabled() throws {
        let client = LLMClient(); let endpoint = ProviderEndpoint(baseURL: "https://example.com", model: "m")
        for enabled in [false, true] {
            let request = try client.request(endpoint: endpoint, key: "fake-local-key", messages: [], streaming: true, memeTool: enabled)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect((body["tools"] != nil) == enabled)
        }
    }
}

@MainActor struct MemeStorageTests {
    @Test func deleteLibraryRetainsSentSnapshotAndDisabledPackIsExcluded() throws {
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container); let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try MemeStore.install(starter(), in: context, root: root)
        #expect(try MemeStore.enabled(in: context).count == 12)
        pack.enabled = false; try context.save(); #expect(try MemeStore.enabled(in: context).isEmpty)
        let meme = try #require(context.fetch(FetchDescriptor<Meme>()).first)
        let snapshot = try MemeStore.snapshot(meme, root: root)
        let model = ChatModel(automaticMaintenance: false); let provider = ProviderConfig(); context.insert(provider)
        model.configure(context: context, provider: provider)
        #expect(model.send("", memes: [snapshot], requestReply: false)); #expect(model.queuedIDs.isEmpty)
        try MemeStore.remove(pack, context: context, root: root)
        #expect(try context.fetchCount(FetchDescriptor<Meme>()) == 0)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Message>()).first)
        #expect(saved.memes == [snapshot]); #expect(saved.status == .sent)
        #expect(!saved.memes[0].data.isEmpty)
        #expect(model.requestHistory().last?.imageURLs.isEmpty == true)
        #expect(model.requestHistory().last?.content.contains(snapshot.caption) == true)
    }
}

struct MemeLearningTests {
    @Test func rejectsInvalidDescription() throws {
        let valid = #"{"caption":"开心的星星","keywords":["开心","收到"],"mood":"happy"}"#
        #expect(try LearnedMeme.parse(valid).caption == "开心的星星")
        #expect(throws: MemeError.metadata) { try LearnedMeme.parse(#"{"caption":"","keywords":[],"mood":"happy"}"#) }
        #expect(throws: MemeError.metadata) { try LearnedMeme.parse(#"{"caption":"a","keywords":[],"mood":"unsupported"}"#) }
    }
    @Test func visionGatePreventsRequests() async throws {
        let client = SequenceCompletionClient([])
        do {
            _ = try await MemeLearning.learn(preview: MemeLearningPreview(jpeg: Data(), frameCount: 1, estimatedTokens: 1000), endpoint: ProviderEndpoint(baseURL: "https://example.com", model: "m"), supportsVision: false, key: "fake-local-key", client: client)
            Issue.record("Expected vision gate")
        } catch { #expect(error as? AttachmentError == .vision) }
        #expect(client.count == 0)
    }
    @Test func singleImagePreviewAndConfirmedLearning() async throws {
        let pack = try starter(); defer { try? FileManager.default.removeItem(at: pack.directory) }
        let preview = try MemeLearning.preview(Data(contentsOf: pack.directory.appendingPathComponent(pack.memes[0].path)))
        #expect(preview.frameCount == 1); #expect(preview.estimatedTokens > 500)
        let client = SequenceCompletionClient([#"{"caption":"星星","keywords":["开心"],"mood":"happy"}"#])
        #expect(client.count == 0)
        let learned = try await MemeLearning.learn(preview: preview, endpoint: ProviderEndpoint(baseURL: "https://example.com", model: "m"), supportsVision: true, key: "fake-local-key", client: client)
        #expect(client.count == 1); #expect(learned.mood == "happy")
    }
    @Test func GIFUsesFourFilmstripFramesAndRemainsAnimated() throws {
        let pack = try starter(); defer { try? FileManager.default.removeItem(at: pack.directory) }
        let png = try Data(contentsOf: pack.directory.appendingPathComponent(pack.memes[0].path))
        let image = try #require(UIImage(data: png)?.cgImage)
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "com.compuserve.gif" as CFString, 6, nil))
        for _ in 0..<6 { CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
        let preview = try MemeLearning.preview(output as Data)
        #expect(preview.frameCount == 4)
        let strip = try #require(UIImage(data: preview.jpeg)); #expect(strip.size.width == 1024)
        #expect(MemeVisual.image(output as Data, animate: true)?.images?.isEmpty == false)
        #expect(MemeVisual.image(output as Data, animate: false)?.images == nil)
    }
}

private final class MemeReplyClient: ChatClient, @unchecked Sendable {
    private let lock = NSLock()
    let events: [MemeStreamEvent]
    private var requests: [(Bool, [ChatTurn])] = []
    init(_ events: [MemeStreamEvent]) { self.events = events }
    var calls: [(Bool, [ChatTurn])] { lock.withLock { requests } }
    func stream(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
    func streamMeme(endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], tools: Bool) -> AsyncThrowingStream<MemeStreamEvent, Error> {
        lock.withLock { requests.append((tools, messages)) }
        return AsyncThrowingStream { continuation in events.forEach { continuation.yield($0) }; continuation.finish() }
    }
}

@Suite(.serialized) @MainActor struct MemeChatIntegrationTests {
    @Test(arguments: [false, true])
    func markerAndNativeSelectionRespectDisableAndCooldown(native: Bool) async throws {
        let defaults = AppPreferences.defaults
        let oldEnabled = defaults.object(forKey: "memes.aiEnabled"); let oldChance = defaults.object(forKey: "memes.chance")
        defer { defaults.set(oldEnabled, forKey: "memes.aiEnabled"); defaults.set(oldChance, forKey: "memes.chance") }
        defaults.set(true, forKey: "memes.aiEnabled"); defaults.set(100, forKey: "memes.chance")
        let container = try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let pack = try MemeStore.install(starter(), in: context)
        defer { try? FileManager.default.removeItem(at: MemeStore.root.appendingPathComponent(pack.id.uuidString)) }
        let friend = LumiCharacter(name: "test", personaPrompt: "friendly"); context.insert(friend)
        let provider = ProviderConfig(); provider.supportsTools = native; context.insert(provider)
        let keychain = KeychainStore(service: "app.lumi.meme-tests.\(UUID())")
        try keychain.save("fake-local-key", for: provider.id); defer { try? keychain.delete(for: provider.id) }
        let client = MemeReplyClient(native ? [.meme(MemeRequest(keyword: "抱抱", mood: "comfort"))] : [.text("在这里[表"), .text("情: 抱抱][表情: 不存在的火星飞艇]")])
        let model = ChatModel(client: client, keychain: keychain, automaticMaintenance: false)
        model.configure(context: context, provider: provider, character: friend)
        #expect(model.send("今天想被安慰"))
        for _ in 0..<200 { if !model.isGenerating { break }; try await Task.sleep(for: .milliseconds(5)) }
        let reply = try #require(model.messages.last)
        #expect(reply.status == .complete); #expect(reply.memes.count == 1)
        #expect(!reply.content.contains("表情:")); #expect(!reply.content.contains("["))
        if !native { #expect(reply.content.contains("不存在的火星飞艇")) }
        #expect(client.calls.first?.0 == native); #expect(client.calls.first?.1.contains { $0.role == "system" && $0.content.contains("【本地表情】") } == true)
        #expect(friend.lastMemeAt != nil)
        #expect(model.send("再来一次"))
        for _ in 0..<200 { if !model.isGenerating { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.messages.last?.memes.isEmpty == true)
        #expect(client.calls.last?.0 == false)
        #expect(client.calls.last?.1.contains { $0.role == "system" && $0.content.contains("【本地表情】") } == false)
        friend.lastMemeAt = nil; defaults.set(false, forKey: "memes.aiEnabled")
        #expect(model.send("关闭表情后"))
        for _ in 0..<200 { if !model.isGenerating { break }; try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.messages.last?.memes.isEmpty == true)
        #expect(client.calls.last?.0 == false)
        #expect(client.calls.last?.1.contains { $0.role == "system" && $0.content.contains("【本地表情】") } == false)
    }
}
