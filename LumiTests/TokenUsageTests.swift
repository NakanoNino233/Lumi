import Foundation
import SwiftData
import Testing
@testable import Lumi

struct ReportedTokenUsageTests {
    @Test func deepSeekAndCompatibleCounts() throws {
        let value = try #require(ReportedTokenUsage.decode(Data(#"{"usage":{"prompt_tokens":100,"completion_tokens":25,"total_tokens":125,"prompt_cache_hit_tokens":80,"prompt_cache_miss_tokens":20}}"#.utf8)))
        #expect(value.total == 125); #expect(value.cached == 80)
        let compatible = try #require(ReportedTokenUsage.decode(Data(#"{"usage":{"prompt_tokens":100,"completion_tokens":25,"prompt_tokens_details":{"cached_tokens":60}}}"#.utf8)))
        #expect(compatible.cached == 60)
        let noCache = try #require(ReportedTokenUsage.decode(Data(#"{"usage":{"prompt_tokens":100,"completion_tokens":25}}"#.utf8)))
        #expect(noCache.cached == nil); #expect(noCache.total == 125)
    }
    @Test(arguments: [
        #"{"usage":null}"#, #"{}"#,
        #"{"usage":{"prompt_tokens":-1,"completion_tokens":2}}"#,
        #"{"usage":{"prompt_tokens":1,"completion_tokens":-2}}"#,
        #"{"usage":{"prompt_tokens":10,"completion_tokens":2,"prompt_cache_hit_tokens":11}}"#,
        #"{"usage":{"prompt_tokens":10,"completion_tokens":2,"prompt_cache_hit_tokens":-1}}"#,
        #"{"usage":{"prompt_tokens":9223372036854775807,"completion_tokens":1}}"#,
        #"{"usage":{"prompt_tokens":1.5,"completion_tokens":2}}"#,
        #"{"usage":{"prompt_tokens":10}}"#
    ]) func invalidOrIncompleteCountsRemainUnknown(_ json: String) {
        #expect(ReportedTokenUsage.decode(Data(json.utf8)) == nil)
    }
    @Test func milestonesAndLargeTotals() {
        #expect(TokenMilestone.all.map(\.target) == [100_000_000, 1_000_000_000, 3_000_000_000, 6_000_000_000, 10_000_000_000])
        #expect(TokenMilestone.progress(for: 0) == 0)
        #expect(TokenMilestone.next(for: 99_999_999).target == 100_000_000)
        #expect(TokenMilestone.next(for: 100_000_000).target == 1_000_000_000)
        #expect(TokenMilestone.next(for: 3_000_000_000).target == 6_000_000_000)
        #expect(TokenMilestone.progress(for: 10_000_000_000) == 1)
        #expect(TokenMilestone.progress(for: Int64.max) == 1)
        #expect(TokenMath.add(Int64.max, 1) == Int64.max)
    }
    @Test func deterministicEncodingAndUsageRequestOptions() throws {
        let client = LLMClient(usageRecorder: TokenUsageRecorder(disabled: true))
        let endpoint = ProviderEndpoint(baseURL: "https://example.invalid", model: "model").attributed(to: [TokenOwner(id: UUID(), name: "Private friend")])
        let turns = [ChatTurn(role: "system", content: PromptBuilder.dataBlock(["b": "two", "a": "one"]))]
        let first = try client.request(endpoint: endpoint, key: "fake-key", messages: turns, streaming: true)
        let second = try client.request(endpoint: endpoint, key: "fake-key", messages: turns, streaming: true)
        #expect(first.httpBody == second.httpBody)
        let data = try #require(first.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["stream_options"] as? [String: Bool])?["include_usage"] == true)
        #expect(!String(decoding: data, as: UTF8.self).contains("Private friend"))
        let nonstreaming = try #require(client.request(endpoint: endpoint, key: "fake-key", messages: turns, streaming: false).httpBody)
        #expect((try JSONSerialization.jsonObject(with: nonstreaming) as? [String: Any])?["stream_options"] == nil)
        #expect(PromptBuilder.dataBlock(["b": 2, "a": 1]) == #"{"a":1,"b":2}"#)
    }
}

@MainActor struct TokenUsageStorageTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
    @Test func duplicateChunksUnknownAndOtherUsage() throws {
        let store = try container(); let recorder = TokenUsageRecorder(container: store)
        let friend = LumiCharacter(name: "小夏"); store.mainContext.insert(friend)
        let endpoint = ProviderConfig().endpoint.attributed(to: friend); let id = UUID()
        recorder.record(id: id, endpoint: endpoint, usage: nil)
        let usage = ReportedTokenUsage(input: 100, output: 25, cached: 80)
        recorder.record(id: id, endpoint: endpoint, usage: usage)
        recorder.record(id: id, endpoint: endpoint, usage: usage)
        recorder.record(id: id, endpoint: endpoint, usage: nil)
        recorder.record(id: UUID(), endpoint: endpoint, usage: nil)
        recorder.record(id: UUID(), endpoint: ProviderConfig().endpoint, usage: .init(input: 20, output: 5))
        let records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        #expect(records.count == 3)
        let summary = TokenUsageSummary(records: records, characters: [friend])
        #expect(summary.total == 150); #expect(summary.other == 25); #expect(summary.unknownRequests == 1)
        #expect(summary.cached == 80); #expect(summary.cacheRate == 0.8)
        #expect(summary.friends.first?.total == 125)
    }
    @Test func groupAllocationsSumExactlyAndSurviveFriendDeletion() throws {
        let store = try container(); let recorder = TokenUsageRecorder(container: store)
        let friends = ["A", "B", "C"].map { LumiCharacter(name: $0) }; friends.forEach { store.mainContext.insert($0) }
        let owners = friends.map { TokenOwner(id: $0.id, name: $0.name) }
        let endpoint = ProviderConfig().endpoint.attributed(to: owners + [owners[0]])
        #expect(endpoint.tokenOwners.count == 3)
        recorder.record(id: UUID(), endpoint: endpoint, usage: .init(input: 10, output: 7, cached: 8))
        var records = try store.mainContext.fetch(FetchDescriptor<TokenUsageRecord>())
        var summary = TokenUsageSummary(records: records, characters: friends)
        #expect(summary.total == 17)
        #expect(summary.friends.reduce(Int64(0)) { $0 + $1.total } == 17)
        #expect(summary.friends.reduce(Int64(0)) { $0 + $1.cached } == 8)
        #expect(summary.friends.allSatisfy { $0.sharedRequests == 1 })
        store.mainContext.delete(friends[0]); try store.mainContext.save()
        records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        summary = TokenUsageSummary(records: records, characters: Array(friends.dropFirst()))
        #expect(summary.total == 17); #expect(summary.friends.count == 3)
        #expect(summary.friends.contains { $0.name == "A" })
    }
    @Test func tenBillionPersistsAndRanks() throws {
        let store = try container(); let recorder = TokenUsageRecorder(container: store)
        let a = LumiCharacter(name: "A"); let b = LumiCharacter(name: "B"); let zero = LumiCharacter(name: "C")
        recorder.record(id: UUID(), endpoint: ProviderConfig().endpoint.attributed(to: a), usage: .init(input: 9_000_000_000, output: 1_000_000_000, cached: 8_000_000_000))
        recorder.record(id: UUID(), endpoint: ProviderConfig().endpoint.attributed(to: b), usage: .init(input: 10, output: 5))
        let records = try ModelContext(store).fetch(FetchDescriptor<TokenUsageRecord>())
        let summary = TokenUsageSummary(records: records, characters: [zero, b, a])
        #expect(summary.total == 10_000_000_015)
        #expect(summary.friends.map(\.id) == [a.id, b.id, zero.id])
        #expect(summary.friends.first?.total == 10_000_000_000)
    }
    @Test func stablePrefixKeepsChangingContextAndFullHistory() {
        let friend = LumiCharacter(name: "A", personaPrompt: "Be friendly")
        let recent = [ChatTurn(role: "user", content: "Earlier user"), ChatTurn(role: "assistant", content: "Earlier answer"), ChatTurn(role: "user", content: "Latest user", imageURLs: ["data:image/jpeg;base64,AA=="])]
        let first = PromptBuilder.build(persona: PromptPersona(friend), profile: "Old profile", memories: [], recent: recent, now: Date(timeIntervalSince1970: 1))
        friend.affection = 3
        let second = PromptBuilder.build(persona: PromptPersona(friend), profile: "New profile", memories: [MemorySnapshot(text: "New fact")], recent: recent, now: Date(timeIntervalSince1970: 100))
        #expect(first.turns.first == second.turns.first)
        #expect(Array(first.turns.prefix(3)) == Array(second.turns.prefix(3)))
        #expect(second.turns.last == recent.last)
        #expect(second.turns.filter { $0.role == "user" || $0.role == "assistant" } == recent)
        #expect(second.turns.dropFirst().contains { $0.role == "system" && $0.content.contains("New profile") && $0.content.contains("New fact") })
        #expect(!second.turns[0].content.contains("New profile"))
    }
}
