import Foundation
import Observation
import SwiftData

@MainActor @Observable final class ChatModel {
    private(set) var messages: [Message] = []
    private(set) var isGenerating = false
    private(set) var queuedIDs: [UUID] = []
    var errorMessage: String?
    private(set) var conversation: Conversation?
    private(set) var character: LumiCharacter?
    private var context: ModelContext?
    private var provider: ProviderConfig?
    private let client: any ChatClient
    private let keychain: KeychainStore
    private let automaticMaintenance: Bool
    private let simulatesTyping: Bool
    private let toolRunner: ChatToolRunner
    private var task: Task<Void, Never>?
    private var generationID: UUID?
    private var activeReply: Message?
    private var activeUserID: UUID?
    private var isConfigured = false
    private var restoring = false

    init(client: any ChatClient = LLMClient(), keychain: KeychainStore = KeychainStore(), automaticMaintenance: Bool = true, simulatesTyping: Bool? = nil, toolSystem: any ToolSystemActions = SystemToolActions()) {
        self.client = client; self.keychain = keychain; self.automaticMaintenance = automaticMaintenance
        self.simulatesTyping = simulatesTyping ?? automaticMaintenance
        self.toolRunner = ChatToolRunner(system: toolSystem)
    }
    func configure(context: ModelContext, provider: ProviderConfig, character selected: LumiCharacter? = nil) {
        guard !isConfigured else { self.provider = provider; reloadExternalMessages(); return }
        self.context = context; self.provider = provider
        do {
            let saved = try context.fetch(FetchDescriptor<LumiCharacter>(sortBy: [SortDescriptor(\.createdAt)])).first
            let character = selected ?? saved ?? LumiCharacter()
            if selected == nil && saved == nil { context.insert(character) }
            self.character = character
            let cid = character.id
            let fetch = FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == cid }, sortBy: [SortDescriptor(\.createdAt)])
            if let saved = try context.fetch(fetch).first { conversation = saved }
            else {
                let new = Conversation(characterID: character.id, title: character.name)
                context.insert(new); conversation = new
            }
            guard let id = conversation?.id else { throw LLMError.storage }
            messages = try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.conversationID == id }, sortBy: [SortDescriptor(\.createdAt)]))
            if AppPreferences.isUITesting, CommandLine.arguments.contains("-lumiUITestsHistory"), messages.isEmpty {
                // Local fixture gives scrolling tests actual history without contacting a provider.
                for index in 0..<20 {
                    let message = Message(conversationID: id, role: index.isMultiple(of: 2) ? "user" : "assistant", content: "历史消息 \(index)：今天一起聊聊最近的生活，慢慢说就好。")
                    message.createdAt = Date(timeIntervalSinceNow: Double(index - 100))
                    context.insert(message); messages.append(message)
                }
            }
            for message in messages where message.status == .generating || message.status == .queued {
                message.status = .interrupted
                message.toolActivities = message.toolActivities.map { item in
                    var item = item
                    if item.status == "pending" || item.status == "running" { item.status = "cancelled"; item.result = ToolError.cancelled.localizedDescription }
                    return item
                }
            }
            if selected != nil && messages.isEmpty && !character.firstGreeting.isEmpty {
                let greeting = Message(conversationID: id, role: "assistant", content: character.firstGreeting)
                context.insert(greeting); messages.append(greeting)
            }
            try context.save(); isConfigured = true
        } catch { errorMessage = LLMError.storage.localizedDescription }
    }
    func reloadExternalMessages() {
        guard !isGenerating, let context, let conversation else { return }
        let id = conversation.id
        do { messages = try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.conversationID == id }, sortBy: [SortDescriptor(\.createdAt)])) }
        catch { errorMessage = LLMError.storage.localizedDescription }
    }
    func maintain(force: Bool = false) {
        guard !restoring, automaticMaintenance, !AppPreferences.isUITesting,
              let context, let provider, let character else { return }
        let automaticMemory = AppPreferences.defaults.object(forKey: "automaticMemory") as? Bool ?? true
        let automaticDiary = AppPreferences.defaults.object(forKey: "automaticDiary") as? Bool ?? true
        guard automaticMemory || automaticDiary else { return }
        MemoryService.shared.schedule(characterID: character.id, provider: provider, container: context.container, force: force, extractMemory: automaticMemory)
    }
    func pauseForRestore() { restoring = true; stop() }
    func endSession() { if !restoring && !isGenerating { maintain(force: true) } }
    @discardableResult func send(_ text: String, attachments: [ChatAttachment] = [], memes: [SentMeme] = [], mountedSkills: Set<UUID> = [], requestReply: Bool = true, voice: RecordedVoice? = nil) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !attachments.isEmpty || !memes.isEmpty || voice != nil, let context, let conversation else { return false }
        do { try ChatAttachment.validate(attachments, supportsVision: provider?.supportsVision == true) }
        catch { errorMessage = error.localizedDescription; return false }
        let message = Message(conversationID: conversation.id, role: "user", content: clean.isEmpty && !memes.isEmpty ? "[表情] " + memes.map(\.caption).joined(separator: "、") : clean, status: requestReply ? .queued : .sent)
        message.voiceData = voice?.data; message.voiceDuration = voice?.duration ?? 0
        message.attachments = attachments; message.memes = Array(memes.prefix(2))
        message.mountedSkillIDs = Array(mountedSkills)
        context.insert(message); messages.append(message); if requestReply { queuedIDs.append(message.id) }
        conversation.lastMessageAt = .now
        guard persist() else { return false }
        if let character { AppPreferences.defaults.set(Date(), forKey: "proactive.lastReply.\(character.id)") }
        if requestReply && !isGenerating { processNext() }
        if !requestReply && voice == nil { errorMessage = String(localized: "表情已保存在聊天中。配置 API 后，可让好友回复。", locale: AppLocale.current) }
        return true
    }
    func sendImmediately(_ id: UUID) {
        guard queuedIDs.contains(id) else { return }
        stop(continueQueue: false)
        // Include all earlier queued user turns in this request, retaining conversational order.
        guard let index = queuedIDs.firstIndex(of: id) else { return }
        let included = Array(queuedIDs.prefix(index + 1))
        for message in messages where included.contains(message.id) { message.status = .sent }
        queuedIDs.removeFirst(index + 1)
        if let message = messages.first(where: { $0.id == id }) { beginReply(to: message) }
    }
    func stop(continueQueue: Bool = false) {
        toolRunner.cancel()
        generationID = nil; task?.cancel(); task = nil
        if let reply = activeReply, reply.status == .generating {
            reply.status = .interrupted
            reply.toolActivities = reply.toolActivities.map { item in
                var item = item
                if item.status == "pending" || item.status == "running" { item.status = "cancelled"; item.result = ToolError.cancelled.localizedDescription }
                return item
            }
        }
        activeReply = nil; activeUserID = nil; isGenerating = false
        _ = persist()
        if continueQueue { processNext() }
    }
    func resumeQueue() { if !isGenerating { processNext() } }
    func regenerate(_ message: Message) {
        guard !isGenerating, let context else { return }
        let userID = message.role == "user" ? message.id : message.replyToID
        guard let user = messages.first(where: { $0.id == userID }) else { return }
        // Re-generation forks from the selected user turn; later history is preserved locally.
        if message.role == "assistant" {
            let replaced = messages.filter { $0.role == "assistant" && $0.replyToID == user.id }
            for bubble in replaced { context.delete(bubble) }
            messages.removeAll { bubble in replaced.contains(where: { $0.id == bubble.id }) }
        }
        user.status = .sent
        beginReply(to: user, cutoff: user.createdAt)
    }
    func delete(_ message: Message) {
        guard let context else { return }
        if activeReply?.id == message.id || activeUserID == message.id { stop() }
        queuedIDs.removeAll { $0 == message.id }
        context.delete(message); messages.removeAll { $0.id == message.id }; _ = persist()
    }
    func dismissError() { errorMessage = nil }
    func approveTool(_ id: UUID, choice: ToolApprovalChoice) { toolRunner.decide(id, choice: choice) }
    private func processNext() {
        guard !isGenerating, let id = queuedIDs.first,
              let user = messages.first(where: { $0.id == id }) else { return }
        queuedIDs.removeFirst(); user.status = .sent
        beginReply(to: user)
    }
    private func beginReply(to user: Message, cutoff: Date? = nil) {
        guard let context, let provider, let conversation else { return }
        do { try ChatAttachment.validate(user.attachments, supportsVision: provider.supportsVision) }
        catch { errorMessage = error.localizedDescription; return }
        errorMessage = nil
        let reply = Message(conversationID: conversation.id, role: "assistant", content: "", status: .generating, replyToID: user.id)
        context.insert(reply); messages.append(reply)
        activeReply = reply; activeUserID = user.id
        isGenerating = true
        let runID = UUID(); generationID = runID
        guard persist() else { stop(); return }
        let endpoint = provider.endpoint.function(.chat).attributed(to: character.map { [TokenOwner(id: $0.id, name: $0.name)] } ?? [])
        let providerID = provider.id
        let available = (try? MemeStore.enabled(in: context)) ?? []
        let cooldown = character?.lastMemeAt.map { Date().timeIntervalSince($0) >= 60 } ?? true
        let memeAllowed = !SafetyGuard.isCrisis(user.content) && cooldown && MemePreferences.allows(roll: Int.random(in: 0..<100))
        let memeContext = MemePreferences.prompt(enabled: memeAllowed, candidates: available.map(MemeCandidate.init))
        let nativeTools = provider.supportsTools
        let history = requestHistory(cutoff: cutoff, excluding: reply.id, memeContext: memeContext)
        let allowedMemories = Set(recalledForRequest.map(\.id))
        task = Task { [weak self] in
            guard let self else { return }
            var succeeded = false
            do {
                let safetyKey = SafetyGuard.needsAssessment(user.content) ? ((try? self.keychain.read(for: providerID)) ?? "") : ""
                let crisis = try await SafetyGuard.assess(user.content, client: self.client, endpoint: endpoint, key: safetyKey)
                try Task.checkCancellation()
                if crisis {
                    reply.content = SafetyGuard.support
                } else {
                    guard let key = try self.keychain.read(for: providerID), !key.isEmpty else { throw LLMError.missingKey }
                    var request = history
                    if !AppPreferences.isUITesting, self.automaticMaintenance {
                        let snapshot = await ContextService.shared.snapshot(preferences: .current, foreground: true)
                        try Task.checkCancellation()
                        if !request.isEmpty { request[0].content += "\n" + snapshot.prompt(using: .current) }
                    }
                    guard let character = self.character else { throw LLMError.storage }
                    let skills = try context.fetch(FetchDescriptor<InstalledSkill>()).filter(\.enabled).map(\.document)
                    let generated = try await self.toolRunner.run(client: self.client, endpoint: endpoint, key: key, history: request, native: nativeTools,
                        context: context, character: character, user: user, reply: reply, skills: skills, memeAllowed: memeAllowed,
                        partial: { raw in
                            guard self.generationID == runID else { throw CancellationError() }
                            if !self.simulatesTyping { reply.content = MemeReplyParser.parse(ReplyParser.parse(raw).text, final: false).text }
                            guard self.persist() else { throw LLMError.storage }
                        }, persist: { guard self.generationID == runID else { throw CancellationError() }; guard self.persist() else { throw LLMError.storage } })
                    let raw = generated.raw; let toolRequests = generated.memes
                    try Task.checkCancellation()
                    guard self.generationID == runID else { return }
                    let parsed = ReplyParser.parse(raw)
                    let currentMemes = memeAllowed && MemePreferences.aiEnabled ? (try MemeStore.enabled(in: context)) : []
                    let candidates = currentMemes.map(MemeCandidate.init)
                    var chosen = Set<UUID>(); var sent: [SentMeme] = []; var used: [Meme] = []
                    @MainActor func choose(keyword: String, mood: String) -> Bool {
                        guard sent.count < 2, let match = MemeMatcher.best(keyword: keyword, mood: mood, candidates: candidates, excluding: chosen),
                              let meme = currentMemes.first(where: { $0.id == match.id }), let snapshot = try? MemeStore.snapshot(meme) else { return false }
                        chosen.insert(match.id); sent.append(snapshot); used.append(meme); return true
                    }
                    let requests = MemeReplyParser.parse(parsed.text, final: true).requests
                    var matched = Set<String>()
                    for request in requests where !matched.contains(request.keyword) {
                        if choose(keyword: request.keyword, mood: parsed.mood ?? "") { matched.insert(request.keyword) }
                    }
                    let parsedMemes = MemeReplyParser.parse(parsed.text, final: true) { matched.contains($0) ? "" : $0 }
                    var text = parsedMemes.text
                    for request in toolRequests {
                        if !choose(keyword: request.keyword, mood: request.mood) { text += (text.isEmpty ? "" : "\n") + request.keyword }
                    }
                    if parsedMemes.requests.isEmpty && toolRequests.isEmpty, let mood = parsed.mood, !mood.isEmpty {
                        _ = choose(keyword: "", mood: mood)
                    }
                    guard !text.isEmpty || !sent.isEmpty else { throw LLMError.emptyResponse }
                    let parts = ReplyDelivery.parts(text)
                    for (index, part) in (parts.isEmpty ? [""] : parts).enumerated() {
                        if self.simulatesTyping { try await Task.sleep(for: ReplyDelivery.delay(for: part)) }
                        try Task.checkCancellation()
                        guard self.generationID == runID else { throw CancellationError() }
                        let bubble: Message
                        if index == 0 { bubble = reply }
                        else {
                            bubble = Message(conversationID: conversation.id, role: "assistant", content: part, replyToID: user.id)
                            context.insert(bubble); self.messages.append(bubble)
                        }
                        bubble.content = part; bubble.createdAt = .now; bubble.status = .complete
                        if index == max(0, parts.count - 1) { bubble.memes = sent }
                        self.messages.sort { $0.createdAt < $1.createdAt }
                        conversation.lastMessageAt = bubble.createdAt
                        if let character = self.character { ChatReadState.shared.received(in: character.id) }
                        guard self.persist() else { throw LLMError.storage }
                    }
                    if let character = self.character {
                        let cid = character.id
                        let facts = try context.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == cid }))
                        let recalled = facts.filter { allowedMemories.contains($0.id) && parsed.memoryIDs.contains($0.id) }
                        reply.recalledMemoryIDs = recalled.map(\.id); reply.recalledMemoryTexts = recalled.map(\.text)
                        for fact in recalled { fact.lastMentionedAt = .now }
                        if try RelationshipEngine.apply(delta: parsed.affectionDelta, mood: parsed.mood, user: user, character: character, context: context) {
                            let stage = RelationshipEngine.stageText(character.stageIndex)
                            let event = Message(conversationID: conversation.id, role: "system", content: String(localized: "关系进入新阶段：\(stage)", locale: AppLocale.current))
                            context.insert(event); self.messages.append(event)
                        }
                    }
                    for meme in used { meme.usageCount += 1 }
                    if !sent.isEmpty { self.character?.lastMemeAt = .now }
                }
                guard self.generationID == runID else { return }
                reply.status = .complete
                if let character = self.character { ChatReadState.shared.received(in: character.id) }
                succeeded = true
            } catch {
                guard self.generationID == runID else { return }
                if Task.isCancelled { if reply.status == .generating { reply.status = .interrupted } }
                else {
                    if reply.status == .generating { reply.status = .failed }
                    self.errorMessage = LLMError.sanitized(error).localizedDescription
                }
            }
            guard self.generationID == runID else { return }
            self.generationID = nil; self.activeReply = nil; self.activeUserID = nil
            self.isGenerating = false; self.task = nil
            _ = self.persist()
            if succeeded, !AppPreferences.isUITesting, let character = self.character { await CompanionActivity.update(character: character, context: context) }
            // Pause a failed queue to avoid repeating paid requests against a broken provider.
            if succeeded { self.processNext(); if !self.isGenerating { self.maintain() } }
        }
    }
    private var recalledForRequest: [MemorySnapshot] = []
    func requestHistory(cutoff: Date? = nil, excluding: UUID? = nil, memeContext: String = "") -> [ChatTurn] {
        guard let character else { return [] }
        let cid = character.id
        let readContext = context.map { ModelContext($0.container) }
        let profile = try? readContext?.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == cid })).first
        let facts = (try? readContext?.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == cid }))) ?? []
        let eligible = messages.filter {
            $0.id != excluding && (!$0.content.isEmpty || $0.attachmentData != nil || $0.memeData != nil) && $0.status != .queued &&
            ($0.role == "user" || $0.role == "assistant" && $0.status == .complete) &&
            (cutoff == nil || $0.createdAt <= cutoff!) &&
            (profile?.compactedBefore == nil || $0.createdAt > profile!.compactedBefore!)
        }
        let query = eligible.last(where: { $0.role == "user" })?.content ?? ""
        recalledForRequest = KeywordMemoryRetriever().recall(query: query, facts: facts.map(MemorySnapshot.init), limit: 6, now: .now)
        let latestUser = eligible.last(where: { $0.role == "user" })?.id
        let recent = eligible.suffix(40).map { message in
            let content = message.content.isEmpty && message.memeData != nil ? "[表情] " + message.memes.map(\.caption).joined(separator: "、") : message.content
            return ChatAttachment.turn(role: message.role, content: content, attachments: message.attachments, supportsVision: provider?.supportsVision == true && message.id == latestUser)
        }
        let sharedGroupMemory = readContext.flatMap { try? GroupStore.privateContext(characterID: character.id, context: $0) } ?? ""
        let groupContext = sharedGroupMemory.isEmpty ? "" : "\n【已开启互通的群聊回忆资料】\n" + PromptBuilder.dataBlock(PromptBuilder.clip(sharedGroupMemory, budget: 1500))
        var built = PromptBuilder.build(persona: PromptPersona(character), profile: profile?.summary ?? "", memories: recalledForRequest, recent: recent,
                                        personalProfile: PersonalProfile.load(),
                                        budget: max(3000, 12_000 - PromptBuilder.estimate(memeContext + groupContext)), fullPersona: true).turns
        PromptBuilder.appendContext(memeContext + groupContext, to: &built)
        return built
    }
    private func persist() -> Bool {
        do { try context?.save(); return true }
        catch { errorMessage = LLMError.storage.localizedDescription; return false }
    }
}
