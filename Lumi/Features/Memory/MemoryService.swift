import Foundation
import SwiftData
import Observation
import UIKit

struct MemoryPayload: Decodable, Sendable {
    struct NewFact: Decodable, Sendable { var category: String; var text: String; var importance: Int }
    struct Update: Decodable, Sendable { var id: UUID; var text: String }
    var new_facts: [NewFact]
    var update_facts: [Update]
    var obsolete_fact_ids: [UUID]
    var profile_summary_patch: String

    static func parse(_ raw: String, knownIDs: Set<UUID>) throws -> Self {
        guard raw.utf8.count <= 64_000 else { throw LLMError.invalidResponse }
        let payload: Self
        do { payload = try JSONDecoder().decode(Self.self, from: Data(raw.utf8)) }
        catch { throw LLMError.invalidResponse }
        let categories = Set(["生日", "喜好", "经历", "计划", "情绪", "关系", "其他"])
        guard payload.new_facts.count <= 30, payload.update_facts.count <= 30, payload.obsolete_fact_ids.count <= 30,
              payload.profile_summary_patch.count <= 1200,
              payload.new_facts.allSatisfy({ categories.contains($0.category) && validText($0.text) && (1...5).contains($0.importance) }),
              payload.update_facts.allSatisfy({ knownIDs.contains($0.id) && validText($0.text) }),
              Set(payload.update_facts.map(\.id)).count == payload.update_facts.count,
              Set(payload.obsolete_fact_ids).isSubset(of: knownIDs),
              Set(payload.update_facts.map(\.id)).isDisjoint(with: payload.obsolete_fact_ids),
              !sensitive(payload.profile_summary_patch) else { throw LLMError.invalidResponse }
        return payload
    }
    static func validText(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 400 && !sensitive(text) }
    static func sensitive(_ text: String) -> Bool {
        text.range(of: #"\b\d{12,19}\b|(?i)(password|api[_ -]?key|密码|证件号|银行卡)\s*[:：=]\s*\S+"#, options: .regularExpression) != nil
    }
}

@MainActor @Observable final class MemoryService {
    static let shared = MemoryService()
    private(set) var busyCharacterIDs: Set<UUID> = []
    private(set) var notices: [UUID: String] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]
    private let client: any ChatClient
    private let keychain: KeychainStore
    init(client: any ChatClient = LLMClient(), keychain: KeychainStore = KeychainStore()) { self.client = client; self.keychain = keychain }

    func cancel(characterID: UUID) {
        generations[characterID] = nil; tasks[characterID]?.cancel(); tasks[characterID] = nil; busyCharacterIDs.remove(characterID)
    }
    func schedule(characterID: UUID, provider: ProviderConfig, container: ModelContainer, force: Bool = false, diary: Bool = false, automatic: Bool = true, extractMemory: Bool = true) {
        guard !busyCharacterIDs.contains(characterID) else { return }
        let endpoint = provider.endpoint.attributed(to: [TokenOwner(id: characterID, name: "")]); let providerID = provider.id
        let generation = UUID(); generations[characterID] = generation
        busyCharacterIDs.insert(characterID); notices[characterID] = nil
        tasks[characterID] = Task { [weak self] in
            guard let self else { return }
            var backgroundID = UIBackgroundTaskIdentifier.invalid
            backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Lumi memory") { [weak self] in
                Task { @MainActor in self?.cancel(characterID: characterID) }
            }
            defer {
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) }
                if self.generations[characterID] == generation {
                    self.busyCharacterIDs.remove(characterID); self.tasks[characterID] = nil; self.generations[characterID] = nil
                }
            }
            do {
                let context = ModelContext(container); context.autosaveEnabled = false
                let cid = characterID
                guard let character = try context.fetch(FetchDescriptor<LumiCharacter>(predicate: #Predicate { $0.id == cid })).first else { return }
                let endpoint = endpoint.attributed(to: character)
                let conversations = try context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == cid }))
                let ids = Set(conversations.map(\.id))
                let messages = try context.fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.createdAt)])).filter { ids.contains($0.conversationID) && $0.status == .complete && ($0.role == "user" || $0.role == "assistant") || ids.contains($0.conversationID) && $0.role == "user" && $0.status == .sent }
                let profile: UserProfile
                if let saved = try context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == cid })).first { profile = saved }
                else { profile = UserProfile(characterID: cid); context.insert(profile) }
                let pending = messages.filter { profile.lastExtractedAt == nil || $0.createdAt > profile.lastExtractedAt! }
                let rounds = pending.filter { $0.role == "assistant" && $0.replyToID != nil }.count
                let interval = max(2, AppPreferences.defaults.object(forKey: "memoryInterval") as? Int ?? 8)
                let shouldExtract = extractMemory && !diary && rounds > 0 && (force || rounds >= interval)
                let existingDiaries = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.characterID == cid }))
                let includeToday = diary || Calendar.current.component(.hour, from: .now) >= 21
                let pendingDiaryDays = Self.diaryDays(messages: messages, saved: existingDiaries, includeToday: includeToday, refreshToday: diary)
                let shouldDiary = diary || (automatic && (AppPreferences.defaults.object(forKey: "automaticDiary") as? Bool ?? true) && !pendingDiaryDays.isEmpty)
                guard shouldExtract || shouldDiary else {
                    if force && !automatic { self.notices[cid] = String(localized: "没有新的完整对话可整理", locale: AppLocale.current) }
                    return
                }
                guard let key = try self.keychain.read(for: providerID), !key.isEmpty else { throw LLMError.missingKey }
                if shouldExtract {
                    let facts = try context.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == cid }))
                    let snapshots = facts.map(MemorySnapshot.init)
                    let oldProfile = profile.summary
                    let uncompacted = messages.filter { profile.compactedBefore == nil || $0.createdAt > profile.compactedBefore! }
                    let needsCompaction = uncompacted.count > 80
                    let input = needsCompaction ? Array(uncompacted.dropLast(40)) : Array(pending.prefix(40))
                    let request = Self.extractionRequest(messages: input, facts: snapshots, summary: oldProfile, compress: needsCompaction)
                    let payload = try await self.extract(endpoint: endpoint, key: key, turns: request, knownIDs: Set(snapshots.map(\.id)))
                    try Task.checkCancellation()
                    guard self.generations[cid] == generation, try Self.exists(cid, container: container) else { return }
                    // Refresh into a new context after the network wait, so user edits/deletion always win.
                    let applyContext = container.mainContext
                    guard let liveProfile = try applyContext.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == cid })).first ?? Self.insertProfile(profile, into: applyContext) else { return }
                    let liveFacts = try applyContext.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == cid }))
                    let canCompact = liveProfile.summary == oldProfile
                    Self.apply(payload, characterID: cid, facts: liveFacts, original: snapshots, profile: liveProfile, originalSummary: oldProfile, compress: needsCompaction, source: input.last(where: { $0.role == "user" })?.id, context: applyContext)
                    liveProfile.lastExtractedAt = input.last?.createdAt
                    if needsCompaction && canCompact { liveProfile.compactedBefore = input.last?.createdAt }
                    liveProfile.updatedAt = .now
                    try applyContext.save()
                    self.notices[cid] = String(localized: "记忆已整理", locale: AppLocale.current)
                }
                if shouldDiary {
                    try await self.generateDiaries(character: character, messages: messages, endpoint: endpoint, key: key, container: container, includeToday: includeToday, refreshToday: diary, generation: generation)
                }
            } catch is CancellationError { }
            catch {
                if self.generations[characterID] == generation {
                    self.notices[characterID] = String(localized: "整理未完成，已有记忆已保留。可稍后重试。", locale: AppLocale.current)
                }
            }
        }
    }
    private static func exists(_ cid: UUID, container: ModelContainer) throws -> Bool {
        try !ModelContext(container).fetch(FetchDescriptor<LumiCharacter>(predicate: #Predicate { $0.id == cid })).isEmpty
    }
    private static func insertProfile(_ profile: UserProfile, into context: ModelContext) -> UserProfile? {
        let new = UserProfile(characterID: profile.characterID); new.summary = profile.summary
        new.lastExtractedAt = profile.lastExtractedAt; new.compactedBefore = profile.compactedBefore
        context.insert(new); return new
    }
    func extract(endpoint: ProviderEndpoint, key: String, turns: [ChatTurn], knownIDs: Set<UUID>) async throws -> MemoryPayload {
        for attempt in 0..<2 {
            let raw = try await client.complete(endpoint: endpoint.function(.memory), key: key, messages: turns + (attempt == 1 ? [ChatTurn(role: "user", content: "上次格式无效。仅返回完整、严格 JSON；不要 Markdown 或解释，所有字段必须存在。") ] : []), limit: 2048)
            try Task.checkCancellation()
            do { return try MemoryPayload.parse(raw, knownIDs: knownIDs) }
            catch { if attempt == 1 { throw error } }
        }
        throw LLMError.invalidResponse
    }
    static func extractionRequest(messages: [Message], facts: [MemorySnapshot], summary: String, compress: Bool) -> [ChatTurn] {
        let data = PromptBuilder.dataBlock(["profile": PromptBuilder.clip(summary, budget: 4000), "facts": PromptBuilder.dataBlock(facts.prefix(50).map { ["id": $0.id.uuidString, "text": PromptBuilder.clip($0.text, budget: 300)] }), "dialogue": PromptBuilder.dataBlock(messages.map { ["role": $0.role, "text": PromptBuilder.clip($0.content, budget: 600)] })])
        return [ChatTurn(role: "system", content: PromptBuilder.resource("MemoryExtraction") + (compress ? "\n本次压缩：profile_summary_patch 必须是整合现有档案与旧对话后的完整摘要，不超过600字，保留重要事实。" : "")), ChatTurn(role: "user", content: data)]
    }
    static func apply(_ payload: MemoryPayload, characterID: UUID, facts: [MemoryFact], original: [MemorySnapshot], profile: UserProfile, originalSummary: String, compress: Bool, source: UUID?, context: ModelContext) {
        let unchanged = facts.filter { fact in original.contains { $0.id == fact.id && $0.text == fact.text && $0.isPinned == fact.isPinned } }
        for update in payload.update_facts { unchanged.first { $0.id == update.id }?.text = update.text }
        for id in payload.obsolete_fact_ids { if let fact = unchanged.first(where: { $0.id == id && !$0.isPinned }) { context.delete(fact) } }
        var texts = Set(facts.map { CharacterCard.normalized($0.text) } + original.map { CharacterCard.normalized($0.text) })
        for new in payload.new_facts where texts.insert(CharacterCard.normalized(new.text)).inserted {
            context.insert(MemoryFact(characterID: characterID, category: new.category, text: new.text, importance: new.importance, sourceMessageID: source))
        }
        if profile.summary == originalSummary && !payload.profile_summary_patch.isEmpty {
            profile.summary = compress ? payload.profile_summary_patch : PromptBuilder.clip(profile.summary + "\n" + payload.profile_summary_patch, budget: 6000)
        }
    }
    static func diaryDays(messages: [Message], saved: [DiaryEntry], includeToday: Bool, refreshToday: Bool, now: Date = .now) -> [String] {
        let today = RelationshipEngine.dayKey(now)
        let grouped = Dictionary(grouping: messages, by: { RelationshipEngine.dayKey($0.createdAt) })
        return grouped.keys.filter { day in
            (includeToday || day != today) && (refreshToday && day == today || !saved.contains { $0.day == day }) && grouped[day]!.contains { $0.role == "user" }
        }.sorted { (grouped[$0]?.last?.createdAt ?? .distantPast) > (grouped[$1]?.last?.createdAt ?? .distantPast) }
    }
    private func generateDiaries(character: LumiCharacter, messages: [Message], endpoint: ProviderEndpoint, key: String, container: ModelContainer, includeToday: Bool, refreshToday: Bool, generation: UUID) async throws {
        let cid = character.id
        let grouped = Dictionary(grouping: messages, by: { RelationshipEngine.dayKey($0.createdAt) })
        let context = ModelContext(container)
        let saved = try context.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.characterID == cid }))
        let candidates = Self.diaryDays(messages: messages, saved: saved, includeToday: includeToday, refreshToday: refreshToday)
        for day in candidates.prefix(1) {
            guard let turns = grouped[day], turns.contains(where: { $0.role == "user" }) else { continue }
            let prompt = [ChatTurn(role: "system", content: PromptBuilder.resource("DiaryPrompt")), ChatTurn(role: "user", content: PromptBuilder.dataBlock(["character": character.name, "day": day, "dialogue": PromptBuilder.dataBlock(turns.suffix(80).map { ["role": $0.role, "text": PromptBuilder.clip($0.content, budget: 1200)] })]))]
            let raw = try await client.complete(endpoint: endpoint.function(.diary), key: key, messages: prompt, limit: 800)
            try Task.checkCancellation()
            guard generations[cid] == generation, try Self.exists(cid, container: container) else { return }
            let text = ReplyParser.parse(raw).text
            guard !text.isEmpty, text.count <= 2000, !MemoryPayload.sensitive(text) else { throw LLMError.invalidResponse }
            let fresh = container.mainContext
            if let existing = try fresh.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.characterID == cid && $0.day == day })).first { existing.content = text; existing.updatedAt = .now }
            else { fresh.insert(DiaryEntry(characterID: cid, day: day, content: text)) }
            try fresh.save(); notices[cid] = String(localized: "日记已保存", locale: AppLocale.current)
        }
    }
}
