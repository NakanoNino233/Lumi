import Foundation
import SwiftData
import Observation

/// Provider-reported usage only. Cached input is a subset of input, never an extra cost.
struct ReportedTokenUsage: Decodable, Sendable, Equatable {
    let input: Int64
    let output: Int64
    let cached: Int64?
    var total: Int64 { input + output }
    private enum CodingKeys: String, CodingKey {
        case prompt_tokens, completion_tokens, prompt_cache_hit_tokens, prompt_tokens_details
    }
    private struct Details: Decodable { var cached_tokens: Int64? }
    init(input: Int64, output: Int64, cached: Int64? = nil) {
        self.input = input; self.output = output; self.cached = cached
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let input = try values.decode(Int64.self, forKey: .prompt_tokens)
        let output = try values.decode(Int64.self, forKey: .completion_tokens)
        let cached = try values.decodeIfPresent(Int64.self, forKey: .prompt_cache_hit_tokens)
            ?? values.decodeIfPresent(Details.self, forKey: .prompt_tokens_details)?.cached_tokens
        guard input >= 0, output >= 0, !input.addingReportingOverflow(output).overflow,
              cached.map({ $0 >= 0 && $0 <= input }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid usage counts"))
        }
        self.init(input: input, output: output, cached: cached)
    }
    static func decode(_ data: Data) -> Self? {
        struct Envelope: Decodable { var usage: ReportedTokenUsage? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.usage
    }
}

struct TokenOwner: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
}

@Model final class TokenUsageRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var model: String
    var ownersJSON: String
    var functionRaw: String?
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var hasUsage: Bool = false
    var hasCacheUsage: Bool = false
    init(id: UUID, endpoint: ProviderEndpoint) {
        self.id = id; createdAt = .now; model = endpoint.model; functionRaw = endpoint.tokenFunction.rawValue
        let owners = endpoint.tokenOwners.sorted { $0.id.uuidString < $1.id.uuidString }
        ownersJSON = PromptBuilder.dataBlock(owners)
    }
    var function: TokenFunction { functionRaw.flatMap(TokenFunction.init(rawValue:)) ?? .unclassified }
    var owners: [TokenOwner] { (try? JSONDecoder().decode([TokenOwner].self, from: Data(ownersJSON.utf8))) ?? [] }
    var total: Int64 { TokenMath.add(input, output) }
}

@MainActor @Observable final class TokenUsageRecorder {
    nonisolated static let shared = TokenUsageRecorder()
    private let suppliedContainer: ModelContainer?
    private let disabled: Bool
    private(set) var saveFailed = false
    var limitNotice: String?
    nonisolated init(container: ModelContainer? = nil, disabled: Bool = false) { suppliedContainer = container; self.disabled = disabled }
    func record(id: UUID, endpoint: ProviderEndpoint, usage: ReportedTokenUsage?) {
        guard !disabled else { return }
        guard let container = suppliedContainer ?? CompanionRuntime.container else { saveFailed = true; return }
        let context = container.mainContext
        do {
            let record: TokenUsageRecord
            if let existing = try context.fetch(FetchDescriptor<TokenUsageRecord>(predicate: #Predicate { $0.id == id })).first { record = existing }
            else { record = TokenUsageRecord(id: id, endpoint: endpoint); context.insert(record) }
            if let usage {
                // Repeated SSE usage chunks update one request instead of adding another request.
                record.input = usage.input; record.output = usage.output; record.cached = usage.cached ?? 0
                record.hasUsage = true; record.hasCacheUsage = usage.cached != nil
            }
            try context.save(); saveFailed = false
            if suppliedContainer == nil, !AppPreferences.isUITesting { checkDailyLimit(context: context) }
        } catch { saveFailed = true }
    }
    private func checkDailyLimit(context: ModelContext) {
        let defaults = AppPreferences.defaults
        guard defaults.bool(forKey: "usage.limitEnabled") else { return }
        let today = RelationshipEngine.dayKey(.now)
        guard defaults.string(forKey: "usage.lastReminderDay") != today else { return }
        let limit = max(1, defaults.integer(forKey: "usage.dailyLimit"))
        let records = (try? context.fetch(FetchDescriptor<TokenUsageRecord>())) ?? []
        let total = UsagePeriodTotals(records: records).today
        if total >= limit {
            defaults.set(today, forKey: "usage.lastReminderDay")
            limitNotice = String(localized: "今天已使用 \(total.formatted()) Token，达到你设置的提醒阈值。可以休息一下，或在设置中查看用量。", locale: AppLocale.current)
        }
    }
}

enum TokenMath {
    static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let result = a.addingReportingOverflow(b); return result.overflow ? Int64.max : result.partialValue
    }
    static func share(_ amount: Int64, index: Int, count: Int) -> Int64 {
        guard count > 0 else { return amount }
        return amount / Int64(count) + (Int64(index) < amount % Int64(count) ? 1 : 0)
    }
}

struct FriendTokenTotal: Identifiable {
    var id: UUID
    var name: String
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var unknownRequests = 0
    var cacheRequests = 0
    var sharedRequests = 0
    var total: Int64 { TokenMath.add(input, output) }
}

@MainActor struct TokenUsageSummary {
    var input: Int64 = 0
    var output: Int64 = 0
    var cached: Int64 = 0
    var cacheReportedInput: Int64 = 0
    var cacheRequests = 0
    var unknownRequests = 0
    var other: Int64 = 0
    var friends: [FriendTokenTotal] = []
    var firstDate: Date?
    var total: Int64 { TokenMath.add(input, output) }
    var cacheRate: Double? { cacheReportedInput > 0 ? Double(cached) / Double(cacheReportedInput) : nil }
    init(records: [TokenUsageRecord], characters: [LumiCharacter]) {
        var rows = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, FriendTokenTotal(id: $0.id, name: $0.name)) })
        firstDate = records.map(\.createdAt).min()
        for record in records {
            input = TokenMath.add(input, record.input); output = TokenMath.add(output, record.output)
            if record.hasCacheUsage {
                cached = TokenMath.add(cached, record.cached); cacheReportedInput = TokenMath.add(cacheReportedInput, record.input); cacheRequests += 1
            }
            if !record.hasUsage { unknownRequests += 1 }
            let owners = record.owners
            if owners.isEmpty { other = TokenMath.add(other, record.total) }
            for (index, owner) in owners.enumerated() {
                var row = rows[owner.id] ?? FriendTokenTotal(id: owner.id, name: owner.name)
                // Split input and output independently; all allocations still sum exactly to the request total.
                row.input = TokenMath.add(row.input, TokenMath.share(record.input, index: index, count: owners.count))
                row.output = TokenMath.add(row.output, TokenMath.share(record.output, index: index, count: owners.count))
                row.cached = TokenMath.add(row.cached, TokenMath.share(record.cached, index: index, count: owners.count))
                if record.hasCacheUsage { row.cacheRequests += 1 }
                if !record.hasUsage { row.unknownRequests += 1 }
                if owners.count > 1 { row.sharedRequests += 1 }
                rows[owner.id] = row
            }
        }
        friends = rows.values.sorted { $0.total == $1.total ? $0.id.uuidString < $1.id.uuidString : $0.total > $1.total }
    }
}

struct TokenMilestone: Identifiable {
    let target: Int64
    let title: LocalizedStringResource
    var id: Int64 { target }
    static let all: [Self] = [
        .init(target: 100_000_000, title: "1 亿 Token"),
        .init(target: 1_000_000_000, title: "10 亿 Token"),
        .init(target: 3_000_000_000, title: "30 亿 Token"),
        .init(target: 6_000_000_000, title: "60 亿 Token"),
        .init(target: 10_000_000_000, title: "100 亿 Token")
    ]
    static func next(for total: Int64) -> Self { all.first { total < $0.target } ?? all.last! }
    static func progress(for total: Int64) -> Double { min(1, max(0, Double(total) / Double(next(for: total).target))) }
}
