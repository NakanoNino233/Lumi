import Foundation
import Observation
import SwiftData

@MainActor @Observable final class GroupChatModel {
    private(set) var messages: [GroupMessage] = []
    private(set) var isGenerating = false
    private(set) var waitingForAutomatic = false
    private(set) var typingName: String?
    var errorMessage: String?
    private var group: GroupChat?
    private var context: ModelContext?
    private var provider: ProviderConfig?
    private var friends: [LumiCharacter] = []
    private let client: any ChatClient
    private let keychain: KeychainStore
    private let typingDelay: Duration?
    private let idleDelay: Duration
    private var task: Task<Void, Never>?
    private var runID: UUID?
    init(client: any ChatClient = LLMClient(), keychain: KeychainStore = KeychainStore(), typingDelay: Duration? = nil, idleDelay: Duration = .seconds(8)) {
        self.client = client; self.keychain = keychain; self.typingDelay = typingDelay; self.idleDelay = idleDelay
    }
    func configure(group: GroupChat, provider: ProviderConfig, context: ModelContext) {
        self.group = group; self.provider = provider; self.context = context
        do {
            let id = group.id
            messages = try context.fetch(FetchDescriptor<GroupMessage>(predicate: #Predicate { $0.groupID == id }, sortBy: [SortDescriptor(\.createdAt)]))
            friends = try context.fetch(FetchDescriptor<LumiCharacter>()).filter { group.memberIDs.contains($0.id) }
        } catch { errorMessage = LLMError.storage.localizedDescription }
    }
    @discardableResult func send(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 4000, let group, let context, !isGenerating else { return false }
        stop(notice: false); errorMessage = nil
        let actors = friends.map { GroupActor($0, group: group) }
        let user = GroupMessage(groupID: group.id, role: "user", text: clean, mentionedIDs: Array(GroupDirector.mentions(in: clean, actors: actors)))
        context.insert(user); messages.append(user); group.lastMessageAt = user.createdAt
        do { try context.save() } catch { context.delete(user); messages.removeAll { $0.id == user.id }; errorMessage = LLMError.storage.localizedDescription; return false }
        launch(user: user, automatic: group.automaticChat)
        return true
    }
    func retry() {
        guard !isGenerating, let user = messages.last(where: { $0.role == "user" }) else { return }
        stop(notice: false); errorMessage = nil; launch(user: user, automatic: false)
    }
    func stop(notice: Bool = true) {
        let wasAutomatic = waitingForAutomatic
        task?.cancel(); task = nil; runID = nil; isGenerating = false; waitingForAutomatic = false; typingName = nil
        if notice && wasAutomatic { appendNotice(String(localized: "自动闲聊已停止。", locale: AppLocale.current)) }
    }
    private func launch(user: GroupMessage, automatic: Bool) {
        guard let provider, let group, context != nil else { return }
        let run = UUID(); runID = run; isGenerating = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.runID == run { self.isGenerating = false; self.waitingForAutomatic = false; self.typingName = nil; self.task = nil; self.runID = nil } }
            do {
                let key = (try self.keychain.read(for: provider.id)) ?? ""
                if try await SafetyGuard.assess(user.text, client: self.client, endpoint: provider.endpoint.function(.safety), key: key) {
                    try Task.checkCancellation()
                    self.appendNotice(SafetyGuard.support); return
                }
                guard !key.isEmpty else { throw LLMError.missingKey }
                try GroupStore.validate(name: group.name, members: self.friends)
                var manualBudget = GroupRunBudget(maximum: 240_000)
                try await self.reply(user: user, key: key, automatic: false, budget: &manualBudget)
                try Task.checkCancellation()
                guard self.runID == run else { return }
                self.isGenerating = false
                guard automatic, group.automaticChat else { return }
                self.waitingForAutomatic = true
                var budget = GroupRunBudget(maximum: min(100_000, max(10_000, group.automaticBudget)))
                let maximumRounds = min(5, max(1, group.automaticRounds))
                for _ in 0..<maximumRounds {
                    try await Task.sleep(for: self.idleDelay)
                    try Task.checkCancellation()
                    guard group.automaticChat else { return }
                    self.isGenerating = true
                    try await self.reply(user: user, key: key, automatic: true, budget: &budget)
                    try Task.checkCancellation()
                    guard self.runID == run else { return }
                    self.isGenerating = false
                }
                self.appendNotice(String(localized: "自动闲聊已达到轮数上限，已停止。", locale: AppLocale.current))
            } catch is CancellationError { /* Explicit stop, deletion or restore ends the run. */ }
            catch {
                guard self.runID == run else { return }
                if case GroupError.budget = error { self.appendNotice(error.localizedDescription) }
                else { self.errorMessage = (error as? GroupError)?.localizedDescription ?? LLMError.sanitized(error).localizedDescription }
            }
        }
    }
    private func reply(user: GroupMessage, key: String, automatic: Bool, budget: inout GroupRunBudget) async throws {
        guard let group, let context, let provider else { throw LLMError.storage }
        friends = try context.fetch(FetchDescriptor<LumiCharacter>()).filter { group.memberIDs.contains($0.id) }
        try GroupStore.validate(name: group.name, members: friends)
        let actors = friends.map { GroupActor($0, group: group) }
        let prior = messages.filter { $0.replyToID == user.id && $0.role == "assistant" }.compactMap(\.speakerID)
        let mentioned = automatic ? Set<UUID>() : Set(user.mentionedIDs).subtracting(prior)
        // Retry only missing replies, so a partial failure cannot duplicate already saved speakers.
        let available = automatic ? actors : actors.filter { !prior.contains($0.id) }
        guard !available.isEmpty else { return }
        let selected = GroupDirector.select(actors: available, mentioned: mentioned, recentSpeakers: messages.compactMap(\.speakerID), round: messages.filter { $0.role == "user" }.count)
        let groupID = group.id
        let perspectives = try context.fetch(FetchDescriptor<GroupPerspective>(predicate: #Predicate { $0.groupID == groupID }))
        let privateMemories = group.sharesMemory ? try context.fetch(FetchDescriptor<MemoryFact>()) : []
        var output: [GroupLine] = []
        typingName = selected.map(\.name).joined(separator: "、")
        if !group.independentReplies {
            let prompt = GroupPrompt.build(group: group, actors: actors, selected: selected, history: messages, perspectives: perspectives, privateMemories: privateMemories, automatic: automatic, required: mentioned, personalProfile: PersonalProfile.load())
            for attempt in 0..<2 {
                var request = prompt
                if attempt == 1 { request.append(ChatTurn(role: "user", content: "上一条输出格式无效。请严格输出合法 JSON 数组，被提及的成员必须回应，其他成员可选择性接话，不得加入名单之外的说话者。")) }
                try budget.reserve(request)
                let raw = try await client.complete(endpoint: provider.endpoint.function(.group).attributed(to: selected.map { TokenOwner(id: $0.id, name: $0.name) }), key: key, messages: request, limit: 1000)
                try Task.checkCancellation()
                guard raw.utf8.count <= 12_000 else { throw LLMError.responseTooLarge }
                do { output = try GroupDirector.parse(raw, selected: selected, required: mentioned); break }
                catch { if attempt == 1 { output = [] } }
            }
        }
        if output.isEmpty {
            for actor in selected {
                let prompt = GroupPrompt.build(group: group, actors: actors, selected: [actor], history: messages, perspectives: perspectives, privateMemories: privateMemories, single: true, automatic: automatic, personalProfile: PersonalProfile.load())
                try budget.reserve(prompt)
                let raw = try await client.complete(endpoint: provider.endpoint.function(.group).attributed(to: [TokenOwner(id: actor.id, name: actor.name)]), key: key, messages: prompt, limit: 400)
                try Task.checkCancellation()
                guard raw.utf8.count <= 12_000 else { throw LLMError.responseTooLarge }
                output.append(try GroupDirector.single(raw, actor: actor, all: actors))
            }
        }
        let deliveries = output.flatMap { line in ReplyDelivery.parts(line.text).map { GroupLine(speaker: line.speaker, text: $0) } }
        for line in deliveries {
            try Task.checkCancellation()
            guard let actor = selected.first(where: { $0.name == line.speaker }), let friend = friends.first(where: { $0.id == actor.id }) else { throw GroupError.format }
            typingName = actor.name
            try await Task.sleep(for: typingDelay ?? ReplyDelivery.delay(for: line.text))
            try Task.checkCancellation()
            let message = GroupMessage(groupID: group.id, role: "assistant", text: line.text, speakerID: actor.id, speakerName: actor.name, replyToID: automatic ? nil : user.id)
            context.insert(message); messages.append(message); group.lastMessageAt = message.createdAt
            do {
                try updatePerspective(for: friend, user: user, line: line, automatic: automatic)
                if !automatic {
                    let proxy = Message(conversationID: group.id, role: "user", content: user.text)
                    proxy.id = user.id
                    _ = try RelationshipEngine.apply(delta: 1, mood: nil, user: proxy, character: friend, context: context)
                }
                try context.save()
                ChatReadState.shared.received(in: group.id)
            } catch { context.rollback(); messages.removeAll { $0.id == message.id }; throw LLMError.storage }
            await GroupMentionNotifier.deliverIfNeeded(message: message, group: group, friend: friend, context: context)
        }
        try Task.checkCancellation()
        typingName = nil
    }
    private func updatePerspective(for friend: LumiCharacter, user: GroupMessage, line: GroupLine, automatic: Bool) throws {
        guard let group, let context else { return }
        let gid = group.id; let cid = friend.id
        let saved = try context.fetch(FetchDescriptor<GroupPerspective>(predicate: #Predicate { $0.groupID == gid && $0.characterID == cid })).first
        let perspective = saved ?? GroupPerspective(groupID: gid, characterID: cid)
        if saved == nil { context.insert(perspective) }
        let excerpt = automatic ? "我在群里说：\(line.text)" : "用户在群里说：\(PromptBuilder.clip(user.text, budget: 180))\n我回应：\(line.text)"
        // A bounded factual excerpt in this member's voice; no unverified inferred memories.
        let entries = (perspective.summary.components(separatedBy: "\n—\n") + [excerpt]).suffix(3)
        perspective.summary = String(entries.joined(separator: "\n—\n").suffix(600)); perspective.updatedAt = .now
    }
    private func appendNotice(_ text: String) {
        guard let group, let context else { return }
        let note = GroupMessage(groupID: group.id, role: "system", text: text)
        context.insert(note); messages.append(note)
        do { try context.save() } catch { context.delete(note); messages.removeAll { $0.id == note.id }; errorMessage = LLMError.storage.localizedDescription }
    }
    func waitUntilIdle() async { await task?.value }
}
