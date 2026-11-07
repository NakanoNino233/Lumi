import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications
import BackgroundTasks

func companionCompletion(client: any ChatClient, endpoint: ProviderEndpoint, key: String, messages: [ChatTurn], limit: Int = 500, seconds: Int = 18) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask { try await client.complete(endpoint: endpoint, key: key, messages: messages, limit: limit) }
        group.addTask { try await Task.sleep(for: .seconds(seconds)); throw LLMError.timeout }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw LLMError.emptyResponse }
        return result
    }
}

@MainActor @Observable final class ProactiveService {
    static let shared: ProactiveService? = CompanionRuntime.container.map { ProactiveService(context: $0.mainContext) }
    var notice: String?
    private(set) var refreshing = false
    private(set) var todayCount = 0
    let context: ModelContext
    private let client: any ChatClient
    private let notifications: any NotificationDriver
    private let keychain: KeychainStore
    private let readSystemContext: Bool
    private var refreshTask: Task<Void, Never>?
    private var operations = Set<String>()
    private var settingsRevision = UUID()
    init(context: ModelContext, client: any ChatClient = LLMClient(), notifications: (any NotificationDriver)? = nil, keychain: KeychainStore = KeychainStore(), readSystemContext: Bool = true) {
        self.context = context; self.client = client; self.notifications = notifications ?? LocalNotificationDriver(); self.keychain = keychain
        self.readSystemContext = readSystemContext
    }
    func pauseForRestore() {
        settingsRevision = UUID(); refreshTask?.cancel()
    }
    func launchRefresh(foreground: Bool) {
        guard !AppPreferences.isUITesting else { return }
        if foreground { AppPreferences.defaults.set(Date(), forKey: "proactive.lastOpen") }
        guard refreshTask == nil else { return }
        refreshTask = Task {
            var allowance = UIBackgroundTaskIdentifier.invalid
            if !foreground {
                allowance = UIApplication.shared.beginBackgroundTask(withName: "Lumi greetings") { [weak self] in self?.refreshTask?.cancel() }
            }
            defer {
                if allowance != .invalid { UIApplication.shared.endBackgroundTask(allowance) }
                refreshTask = nil
            }
            await refresh(foreground: foreground)
            CompanionRuntime.scheduleRefresh()
        }
    }
    func settingsChanged() async {
        settingsRevision = UUID(); refreshTask?.cancel()
        let all = (try? context.fetch(FetchDescriptor<ScheduledGreeting>())) ?? []
        let pending = all.filter { $0.fireDate > .now && ($0.stateRaw == "pending" || $0.stateRaw == "scheduled") }
        notifications.remove(pending.map(\.requestID))
        for item in pending { item.stateRaw = "cancelled" }
        try? context.save()
        AppPreferences.defaults.removeObject(forKey: "proactive.lastBatch")
        if !CompanionPreferences.current.enabled { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: CompanionRuntime.refreshIdentifier) }
        // Wait for a cancelled generator to relinquish its guard before rebuilding.
        await refreshTask?.value
        while refreshing {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }
        await refresh(foreground: true)
        CompanionRuntime.scheduleRefresh()
    }
    func refresh(foreground: Bool) async {
        guard !refreshing, !AppPreferences.isUITesting else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let now = Date(); let prefs = CompanionPreferences.current; let revision = settingsRevision
            let all = try context.fetch(FetchDescriptor<ScheduledGreeting>())
            for item in all where item.stateRaw == "scheduled" && item.fireDate <= now { item.stateRaw = "elapsed" }
            updateCount(all, now: now)
            guard prefs.enabled, await notifications.authorized() else {
                notifications.remove(all.filter { $0.stateRaw == "scheduled" && $0.fireDate > now }.map(\.requestID))
                return
            }
            let characters = try context.fetch(FetchDescriptor<LumiCharacter>(sortBy: [SortDescriptor(\.createdAt)]))
            let id = UUID(uuidString: prefs.characterID.isEmpty ? (AppPreferences.defaults.string(forKey: "selectedCharacter") ?? "") : prefs.characterID)
            guard let character = characters.first(where: { $0.id == id }) ?? characters.first else { return }
            let own = all.filter { $0.characterID == character.id && ($0.stateRaw == "pending" || $0.stateRaw == "scheduled") && $0.fireDate > now }
            let lastOpen = AppPreferences.defaults.object(forKey: "proactive.lastOpen") as? Date ?? now
            let mayRefill = foreground || now.timeIntervalSince(lastOpen) < 3 * 86400
            let lastBatch = AppPreferences.defaults.object(forKey: "proactive.lastBatch") as? Date ?? .distantPast
            let coverage = own.filter { !$0.isClosure }.map(\.fireDate).max() ?? .distantPast
            if mayRefill && coverage < now.addingTimeInterval(3 * 86400) && now.timeIntervalSince(lastBatch) > 6 * 3600 {
                guard let provider = try context.fetch(FetchDescriptor<ProviderConfig>()).first,
                      let key = try keychain.read(for: provider.id), !key.isEmpty else {
                    notice = LLMError.missingKey.localizedDescription
                    try context.save(); return
                }
                let snapshot = await ContextService.shared.snapshot(preferences: prefs, foreground: foreground)
                try Task.checkCancellation()
                let prompt = try batchPrompt(character: character, preferences: prefs, snapshot: snapshot, now: now)
                var candidates: [GreetingCandidate] = []
                for attempt in 0..<2 {
                    do {
                        let raw = try await companionCompletion(client: client, endpoint: provider.endpoint.function(.greeting).attributed(to: character), key: key,
                            messages: prompt + (attempt == 0 ? [] : [ChatTurn(role: "user", content: "Return a valid strict JSON array with only the four specified keys per entry.")]), limit: 1600, seconds: 12)
                        candidates = try GreetingJSON.parse(raw, now: now); break
                    } catch is CancellationError { throw CancellationError() }
                    catch { if attempt == 1 { notice = String(localized: "问候生成暂未完成，将保留已有排程。稍后打开 App 可重试。", locale: AppLocale.current) } }
                }
                try Task.checkCancellation()
                guard prefs == .current, revision == settingsRevision,
                      try characterExists(character.id) else { return }
                if !candidates.isEmpty {
                    // Replacing only future entries keeps delivered notification IDs resolvable.
                    notifications.remove(own.map(\.requestID))
                    for item in own { item.stateRaw = "cancelled" }
                    for candidate in candidates {
                        context.insert(ScheduledGreeting(id: candidate.id, characterID: character.id, fireDate: candidate.date, text: candidate.text, scenario: candidate.scenario))
                    }
                    let closureDay = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86400)
                    let closureDate = GreetingPlanner.jitter(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: closureDay) ?? closureDay, seconds: Int.random(in: -900...900))
                    let text = String(localized: "这几天的问候先放在这里。安心过自己的生活，想聊天时再来就好。", locale: AppLocale.current)
                    context.insert(ScheduledGreeting(characterID: character.id, fireDate: closureDate, text: text, scenario: "其他", isClosure: true))
                    AppPreferences.defaults.set(now, forKey: "proactive.lastBatch"); notice = nil
                }
            }
            try Task.checkCancellation()
            guard prefs == .current, revision == settingsRevision else { return }
            try context.save()
            try await schedule(preferences: prefs, character: character, now: now)
        } catch is CancellationError { }
        catch { notice = LLMError.sanitized(error).localizedDescription }
    }
    private func batchPrompt(character: LumiCharacter, preferences: CompanionPreferences, snapshot: ContextSnapshot, now: Date) throws -> [ChatTurn] {
        let id = character.id
        let profile = try context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == id })).first?.summary ?? ""
        let memories = try context.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == id }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).prefix(8).map(\.text)
        let anniversaries = try context.fetch(FetchDescriptor<Anniversary>(predicate: #Predicate { $0.characterID == id })).prefix(12).map { "\($0.title):\(GreetingPlanner.dayString($0.date)) yearly=\($0.repeatsYearly)" }
        let previous = try context.fetch(FetchDescriptor<ScheduledGreeting>(predicate: #Predicate { $0.characterID == id }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).prefix(20).map(\.text)
        let data: [String: String] = ["name": character.name, "persona": PromptBuilder.clip(character.personaPrompt, budget: 1800),
            "style": character.speechStyle, "relationship": "stage=\(character.stageIndex) affection=\(character.affection)",
            "profile": PromptBuilder.clip(profile, budget: 1000), "memories": PromptBuilder.dataBlock(memories),
            "anniversaries": PromptBuilder.dataBlock(anniversaries), "previous": PromptBuilder.dataBlock(previous),
            "today": GreetingPlanner.dayString(now), "timezone": TimeZone.current.identifier,
            "dailyLimit": String(preferences.dailyLimit), "quietHours": "\(preferences.quietStart):00–\(preferences.quietEnd):00", "language": AppLocale.current.identifier]
        return [ChatTurn(role: "system", content: PromptBuilder.resource("SafetyPrompt") + "\n" + PromptBuilder.resource("GreetingBatch")),
                ChatTurn(role: "system", content: PromptBuilder.personalProfileContext(PersonalProfile.load())),
                ChatTurn(role: "user", content: PromptBuilder.dataBlock(data) + "\n" + snapshot.prompt(using: .current))]
    }
    private func schedule(preferences: CompanionPreferences, character: LumiCharacter, now: Date) async throws {
        let all = try context.fetch(FetchDescriptor<ScheduledGreeting>())
        let future = all.filter { ($0.stateRaw == "scheduled" || $0.stateRaw == "pending") && $0.fireDate > now }
        let previousIDs = Set(future.map(\.requestID))
        let pendingIDs = await notifications.pendingIDs()
        let occupied = pendingIDs.filter { !previousIDs.contains($0) }.count
        let lastReply = AppPreferences.defaults.object(forKey: "proactive.lastReply.\(character.id)") as? Date ?? character.createdAt
        let past = all.filter { ($0.stateRaw == "elapsed" || $0.stateRaw == "scheduled") && $0.fireDate <= now }.map(\.fireDate)
        var candidates = future.filter { $0.characterID == character.id }.map { GreetingCandidate(id: $0.id, date: $0.fireDate, text: $0.text, scenario: $0.scenario, isClosure: $0.isClosure) }
        // A closure must be audible outside quiet hours, even when the usual evening slot is quiet.
        if let index = candidates.firstIndex(where: \.isClosure), preferences.isQuiet(candidates[index].date, calendar: .current),
           let adjusted = Calendar.current.date(bySettingHour: preferences.quietEnd, minute: 15, second: 0, of: candidates[index].date) {
            candidates[index].date = adjusted
            future.first(where: { $0.id == candidates[index].id })?.fireDate = adjusted
        }
        let groupNoticeDates = try context.fetch(FetchDescriptor<GroupMessage>()).compactMap(\.notificationAt)
        let selected = GreetingPlanner.select(candidates, preferences: preferences, now: now, lastReply: lastReply, sentDates: past + groupNoticeDates, occupiedSlots: occupied)
        notifications.remove(Array(previousIDs))
        for item in future { item.stateRaw = "pending" }
        for candidate in selected {
            try Task.checkCancellation()
            guard preferences == .current else { return }
            guard let item = future.first(where: { $0.id == candidate.id }) else { continue }
            try await notifications.add(notification(item, character: character))
            guard !Task.isCancelled, preferences == .current else {
                notifications.remove([item.requestID]); item.stateRaw = "cancelled"; try context.save(); return
            }
            item.stateRaw = "scheduled"
        }
        try context.save(); updateCount(all, now: now)
    }
    private func updateCount(_ all: [ScheduledGreeting], now: Date) {
        todayCount = all.filter { ["elapsed", "scheduled", "immediate"].contains($0.stateRaw) && $0.fireDate <= now && Calendar.current.isDate($0.fireDate, inSameDayAs: now) }.count
    }
    private func notification(_ greeting: ScheduledGreeting, character: LumiCharacter) -> CompanionNotification {
        CompanionNotification(id: greeting.id, characterID: character.id, title: character.name, text: greeting.text, date: greeting.fireDate, avatar: character.avatarData)
    }
    private func characterExists(_ id: UUID) throws -> Bool { try context.fetchCount(FetchDescriptor<LumiCharacter>(predicate: #Predicate { $0.id == id })) > 0 }
    private func findGreeting(_ id: UUID) throws -> ScheduledGreeting? { try context.fetch(FetchDescriptor<ScheduledGreeting>(predicate: #Predicate { $0.id == id })).first }
    func conversation(for characterID: UUID) throws -> Conversation {
        guard try characterExists(characterID) else { throw LLMError.storage }
        if let saved = try context.fetch(FetchDescriptor<Conversation>(predicate: #Predicate { $0.characterID == characterID }, sortBy: [SortDescriptor(\.createdAt)])).first { return saved }
        let conversation = Conversation(characterID: characterID, title: "Lumi"); context.insert(conversation); return conversation
    }
    @discardableResult func importGreeting(_ id: UUID) throws -> UUID? {
        guard let greeting = try findGreeting(id), try characterExists(greeting.characterID) else { return nil }
        let token = "greeting:" + id.uuidString
        let existingCount = try context.fetchCount(FetchDescriptor<Message>(predicate: #Predicate { $0.externalEventID == token || $0.id == id }))
        if greeting.importedAt == nil && existingCount == 0 {
            let conversation = try conversation(for: greeting.characterID)
            let message = Message(conversationID: conversation.id, role: "assistant", content: greeting.text)
            message.createdAt = greeting.fireDate; message.isProactive = true; message.externalEventID = token
            context.insert(message); conversation.lastMessageAt = max(conversation.lastMessageAt, greeting.fireDate)
        }
        greeting.importedAt = greeting.importedAt ?? .now
        try context.save()
        return greeting.characterID
    }
    func openGreeting(_ id: UUID) throws {
        if let characterID = try importGreeting(id) { ConversationRouter.shared.open(characterID: characterID) }
    }
    func handleReply(greetingID: UUID, text: String) async {
        let token = "notification-reply:" + greetingID.uuidString
        guard !operations.contains(token) else { return }
        do {
            guard let characterID = try importGreeting(greetingID) else { return }
            _ = try await respond(characterID: characterID, text: text, scenario: nil, token: token, notify: true)
        } catch is CancellationError { notice = String(localized: "后台时间不足，消息已保留。请打开 App 继续。", locale: AppLocale.current) }
        catch {
            notice = LLMError.sanitized(error).localizedDescription
            if let greeting = try? findGreeting(greetingID),
               let character = try? context.fetch(FetchDescriptor<LumiCharacter>()).first(where: { $0.id == greeting.characterID }) {
                let id = greeting.replyNoticeID ?? UUID(); greeting.replyNoticeID = id
                try? context.save()
                try? await sendImmediate(character: character, text: String(localized: "消息已保存，暂时无法回复。请打开 Lumi 检查 API 配置或网络后重试。", locale: AppLocale.current), id: id)
            }
        }
    }
    // A persisted input/output token plus an in-flight guard makes re-delivery idempotent.
    func respond(characterID: UUID, text: String, scenario: String?, token: String, notify: Bool) async throws -> String {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty else { throw LLMError.emptyResponse }
        let outputToken = token + ":output"
        if let saved = try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.externalEventID == outputToken })).first {
            if notify, let character = try context.fetch(FetchDescriptor<LumiCharacter>(predicate: #Predicate { $0.id == characterID })).first {
                try await sendImmediate(character: character, text: saved.content, id: saved.id)
            }
            return saved.content
        }
        guard operations.insert(token).inserted else { throw LLMError.rateLimited }
        defer { operations.remove(token) }
        guard let character = try context.fetch(FetchDescriptor<LumiCharacter>(predicate: #Predicate { $0.id == characterID })).first else { throw LLMError.storage }
        let conversation = try conversation(for: characterID)
        var user = try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.externalEventID == token })).first
        if user == nil {
            let item = Message(conversationID: conversation.id, role: scenario == nil ? "user" : "system", content: clean, status: .sent)
            item.externalEventID = token; context.insert(item); user = item
            try context.save()
        }
        var completed = false
        defer {
            if !completed, let user, user.modelContext != nil { user.status = .failed; try? context.save() }
        }
        AppPreferences.defaults.set(Date(), forKey: "proactive.lastReply.\(characterID)")
        let output: String
        if SafetyGuard.isCrisis(clean) {
            output = String(localized: "听起来你现在很难受，我很关心你的安全。请先联系身边可信的人陪着你；如果有立即的危险，请联系当地紧急服务或前往急诊。你不需要独自承受。", locale: AppLocale.current)
        } else {
            guard let provider = try context.fetch(FetchDescriptor<ProviderConfig>()).first, let key = try keychain.read(for: provider.id), !key.isEmpty else { throw LLMError.missingKey }
            let prefs = CompanionPreferences.current
            let snapshot = readSystemContext ? await ContextService.shared.snapshot(preferences: prefs, foreground: false) : ContextSnapshot()
            try Task.checkCancellation()
            let profile = try context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.characterID == characterID })).first?.summary ?? ""
            let facts = try context.fetch(FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.characterID == characterID })).map { MemorySnapshot($0) }
            let cid = conversation.id
            let history = try context.fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.conversationID == cid }, sortBy: [SortDescriptor(\.createdAt)])).suffix(16).map { ChatTurn(role: $0.role, content: $0.content) }
            var prompt = PromptBuilder.build(persona: PromptPersona(character), profile: profile, memories: KeywordMemoryRetriever().recall(query: clean, facts: facts, limit: 5, now: .now), recent: history, personalProfile: PersonalProfile.load(), fullPersona: true).turns
            PromptBuilder.appendContext("\n" + snapshot.prompt(using: .current), to: &prompt)
            if let scenario { PromptBuilder.appendContext("\n" + PromptBuilder.resource("ScenarioPrompt") + "\nscenario=" + PromptBuilder.dataBlock(scenario), to: &prompt) }
            let skills = try context.fetch(FetchDescriptor<InstalledSkill>()).filter(\.enabled).map(\.document)
            PromptBuilder.appendContext(SkillLibrary.prompt(skills, mounted: scenario.map { SkillLibrary.scenarioMountedNames($0, skills: skills) } ?? []), to: &prompt)
            PromptBuilder.appendContext("\n此快捷场景只生成问候，不执行工具；技能中的操作建议需要用户打开聊天后授权。", to: &prompt)
            let raw = try await companionCompletion(client: client, endpoint: provider.endpoint.function(.greeting).attributed(to: character), key: key, messages: prompt)
            output = String(ReplyParser.parse(raw).text.prefix(1200))
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LLMError.emptyResponse }
        }
        try Task.checkCancellation()
        guard try characterExists(characterID), user?.modelContext != nil else { throw LLMError.storage }
        let reply = Message(conversationID: conversation.id, role: "assistant", content: output, replyToID: user?.id)
        reply.externalEventID = outputToken; reply.isProactive = scenario != nil
        context.insert(reply); conversation.lastMessageAt = .now
        if let user { user.status = .complete }
        try context.save()
        completed = true
        ConversationRouter.shared.revision = UUID()
        if notify { try await sendImmediate(character: character, text: output, id: reply.id) }
        return output
    }
    private func sendImmediate(character: LumiCharacter, text: String, id: UUID) async throws {
        guard await notifications.authorized() else { return }
        let saved = try findGreeting(id)
        if saved?.stateRaw == "immediate" { return }
        let existing = await notifications.pendingIDs()
        if existing.count >= 64 {
            let all = try context.fetch(FetchDescriptor<ScheduledGreeting>(sortBy: [SortDescriptor(\.fireDate, order: .reverse)]))
            if let last = all.first(where: { existing.contains($0.requestID) && $0.fireDate > .now && !$0.isClosure }) {
                notifications.remove([last.requestID]); last.stateRaw = "pending"
            } else { throw LLMError.rateLimited }
        }
        let greeting = saved ?? ScheduledGreeting(id: id, characterID: character.id, fireDate: .now, text: text, scenario: "reply")
        if saved == nil { context.insert(greeting) }
        greeting.stateRaw = "sending"
        try context.save()
        try await notifications.add(notification(greeting, character: character))
        greeting.stateRaw = "immediate"; try context.save()
        updateCount(try context.fetch(FetchDescriptor<ScheduledGreeting>()), now: .now)
    }
    func testNotification() async {
        do {
            guard await notifications.authorized() else { notice = String(localized: "请先允许通知。", locale: AppLocale.current); return }
            let selection = CompanionPreferences.current.characterID
            let id = UUID(uuidString: selection.isEmpty ? (AppPreferences.defaults.string(forKey: "selectedCharacter") ?? "") : selection)
            let characters = try context.fetch(FetchDescriptor<LumiCharacter>(sortBy: [SortDescriptor(\.createdAt)]))
            guard let character = characters.first(where: { $0.id == id }) ?? characters.first else { return }
            try await sendImmediate(character: character, text: String(localized: "这是一条 Lumi 测试通知。点开后会回到我的聊天。", locale: AppLocale.current), id: UUID())
            notice = String(localized: "测试通知已发送。", locale: AppLocale.current)
        } catch { notice = LLMError.sanitized(error).localizedDescription }
    }
}
