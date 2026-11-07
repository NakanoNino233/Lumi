import Foundation
import Testing
import SwiftData
@testable import Lumi

struct GreetingPlannerTests {
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    func date(_ day: Int, hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
    func candidates(days: Int = 40) -> [GreetingCandidate] {
        (0..<days).flatMap { offset in
            [9, 12, 18, 21].map { hour in
                let base = calendar.date(byAdding: .day, value: offset, to: date(1, hour: hour))!
                return GreetingCandidate(id: UUID(), date: base, text: "Hello", scenario: "关心")
            }
        }
    }
    @Test func nearestFirstAndSystemCapWithOtherRequests() {
        let all = candidates(days: 100)
        let prefs = CompanionPreferences(enabled: true, dailyLimit: 2, quietStart: 0, quietEnd: 0)
        // A recent reply in the future prevents downshifting for this capacity-only case.
        let selected = GreetingPlanner.select(all.reversed(), preferences: prefs, now: date(1, hour: 0), lastReply: date(1).addingTimeInterval(200 * 86400), occupiedSlots: 3, calendar: calendar)
        #expect(selected.count == 61)
        #expect(selected.map(\.date) == selected.map(\.date).sorted())
        #expect(selected.first?.date == date(1, hour: 9))
        #expect(GreetingPlanner.select(all, preferences: prefs, now: date(1), lastReply: date(1), occupiedSlots: 64, calendar: calendar).isEmpty)
    }
    @Test(arguments: [-2000, -900, -300, 0, 300, 900, 2000]) func jitterNeverExceedsFifteenMinutes(seconds: Int) {
        let base = date(1)
        let delta = GreetingPlanner.jitter(base, seconds: seconds).timeIntervalSince(base)
        #expect(abs(delta) <= 900); #expect(delta == Double(min(900, max(-900, seconds))))
    }
    @Test(arguments: [(22, 8), (10, 19), (0, 0)]) func respectsQuietHoursAndDailyLimit(hours: (Int, Int)) {
        let prefs = CompanionPreferences(enabled: true, dailyLimit: 1, quietStart: hours.0, quietEnd: hours.1)
        let selected = GreetingPlanner.select(candidates(), preferences: prefs, now: date(1, hour: 0), lastReply: date(1), sentDates: [date(1, hour: 8)], calendar: calendar)
        #expect(selected.allSatisfy { !prefs.isQuiet($0.date, calendar: calendar) })
        #expect(!selected.contains { calendar.isDate($0.date, inSameDayAs: date(1)) })
        let groups = Dictionary(grouping: selected, by: { calendar.startOfDay(for: $0.date) })
        #expect(groups.values.allSatisfy { $0.count <= 1 })
    }
    @Test(arguments: [(1, 1), (3, 3), (7, 7), (20, 7)]) func downshiftsAfterNoReply(day: (Int, Int)) {
        #expect(GreetingPlanner.interval(lastReply: date(1), now: date(day.0 + 1), calendar: calendar) == day.1)
    }
    @Test func downshiftDoesNotDropFinalClosureOrDuplicateIDs() {
        let closure = GreetingCandidate(id: UUID(), date: date(9), text: "Take care", scenario: "其他", isClosure: true)
        let prefs = CompanionPreferences(enabled: true)
        let selected = GreetingPlanner.select([closure, closure], preferences: prefs, now: date(8), lastReply: date(1), calendar: calendar)
        #expect(selected.count == 1); #expect(selected.first?.isClosure == true)
        #expect(GreetingPlanner.select([closure], preferences: CompanionPreferences(), now: date(8), lastReply: date(1), calendar: calendar).isEmpty)
    }
    @Test func strictJSONDatesAndTextBoundaries() throws {
        let raw = #"[{"date":"2026-11-01","slot":"morning","scenario":"早安","text":"早安。"},{"date":"2026-11-02","slot":"evening","scenario":"关心","text":"今天辛苦了。"},{"date":"2026-11-03","slot":"night","scenario":"晚安","text":"晚安。"}]"#
        let parsed = try GreetingJSON.parse(raw, now: date(1, hour: 0), calendar: calendar, offset: { 900 })
        #expect(parsed.count == 3); #expect(parsed[0].date == date(1, hour: 9).addingTimeInterval(900))
        for invalid in ["```json\n" + raw + "\n```", raw.replacingOccurrences(of: "2026-11-01", with: "2026-11-31"), raw.replacingOccurrences(of: "morning", with: "midnight"), raw.replacingOccurrences(of: "早安。", with: String(repeating: "好", count: 41)), raw.replacingOccurrences(of: "\"text\":\"晚安。\"", with: "\"text\":\"晚安。\",\"extra\":true")] {
            #expect(throws: (any Error).self) { try GreetingJSON.parse(invalid, now: date(1, hour: 0), calendar: calendar) }
        }
    }
    @Test(arguments: [0, 1, 2, 3, 4, 5, 6, 7]) func disabledContextsCannotEnterPrompts(mask: Int) {
        let snapshot = ContextSnapshot(weather: "weather-private", calendar: "calendar-private", battery: "battery-private")
        let prefs = CompanionPreferences(weather: mask & 1 != 0, calendar: mask & 2 != 0, battery: mask & 4 != 0)
        let prompt = snapshot.prompt(using: prefs)
        #expect(prompt.contains("weather-private") == prefs.weather)
        #expect(prompt.contains("calendar-private") == prefs.calendar)
        #expect(prompt.contains("battery-private") == prefs.battery)
    }
}

@MainActor final class RecordingNotifications: NotificationDriver {
    var items: [CompanionNotification] = []
    var failNext = false
    func authorized() async -> Bool { true }
    func pendingIDs() async -> [String] { items.map(\.requestID) }
    func remove(_ ids: [String]) { items.removeAll { ids.contains($0.requestID) } }
    func add(_ item: CompanionNotification) async throws {
        if failNext { failNext = false; throw LLMError.network }
        items.removeAll { $0.id == item.id }; items.append(item)
    }
}
@MainActor struct Stage3IntegrationTests {
    @Test func notificationCompletionReturnsToMainAfterSuspension() async {
        let onMain = await withCheckedContinuation { continuation in
            LumiAppDelegate.finishResponse({ await Task.yield() }, completion: { continuation.resume(returning: Thread.isMainThread) })
        }
        #expect(onMain)
    }
    func container() throws -> ModelContainer { try ModelContainer(for: LumiSchema.schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]) }
    @Test func notificationTapPersistsOnceRoutesAndRespectsDeletion() throws {
        let store = try container(); let context = store.mainContext
        let character = LumiCharacter(name: "小夏"); context.insert(character)
        let greeting = ScheduledGreeting(characterID: character.id, fireDate: .now, text: "今天辛苦啦", scenario: "关心")
        context.insert(greeting); try context.save()
        let service = ProactiveService(context: context, notifications: RecordingNotifications(), readSystemContext: false)
        try service.openGreeting(greeting.id); try service.openGreeting(greeting.id)
        let messages = try context.fetch(FetchDescriptor<Message>())
        #expect(messages.count == 1); #expect(messages.first?.isProactive == true)
        #expect(AppPreferences.defaults.string(forKey: "selectedCharacter") == character.id.uuidString)
        context.delete(messages[0]); try context.save(); try service.openGreeting(greeting.id)
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 0)
        try CharacterLibrary.remove(character, from: context)
        #expect(try context.fetchCount(FetchDescriptor<ScheduledGreeting>()) == 0)
        #expect(try service.importGreeting(greeting.id) == nil)
    }
    @Test func replyRoundTripAndRepeatedDeliveryAreIdempotent() async throws {
        let store = try container(); let context = store.mainContext
        let character = LumiCharacter(name: "小夏"); let provider = ProviderConfig()
        context.insert(character); context.insert(provider)
        let greeting = ScheduledGreeting(characterID: character.id, fireDate: .now, text: "你好呀", scenario: "关心")
        context.insert(greeting); try context.save()
        let keychain = KeychainStore(service: "app.lumi.stage3.\(UUID())")
        try keychain.save("mock-key", for: provider.id); defer { try? keychain.delete(for: provider.id) }
        let client = SequenceCompletionClient(["我在呢。<meta affection_delta=\"1\" mood=\"开心\"/>"])
        let driver = RecordingNotifications()
        let service = ProactiveService(context: context, client: client, notifications: driver, keychain: keychain, readSystemContext: false)
        await service.handleReply(greetingID: greeting.id, text: "我回来啦")
        await service.handleReply(greetingID: greeting.id, text: "我回来啦")
        #expect(client.count == 1); #expect(driver.items.count == 1)
        #expect(driver.items.first?.title == "小夏"); #expect(driver.items.first?.text == "我在呢。")
        let output = try #require(driver.items.first)
        try service.openGreeting(output.id)
        let messages = try context.fetch(FetchDescriptor<Message>())
        #expect(messages.count == 3); #expect(messages.filter { $0.role == "user" }.count == 1)
        #expect(messages.filter { $0.content == "我在呢。" }.count == 1)
    }
    @Test func crisisShortcutDoesNotCallModelEvenWithoutKey() async throws {
        let store = try container(); let character = LumiCharacter(); store.mainContext.insert(character); try store.mainContext.save()
        let client = SequenceCompletionClient([])
        let service = ProactiveService(context: store.mainContext, client: client, notifications: RecordingNotifications(), readSystemContext: false)
        let output = try await service.respond(characterID: character.id, text: "我想自杀", scenario: nil, token: UUID().uuidString, notify: false)
        #expect(client.count == 0); #expect(output.contains("安全"))
    }
    @Test func missingKeyKeepsIncomingUserMessageForRecovery() async throws {
        let store = try container(); let character = LumiCharacter(); let provider = ProviderConfig()
        store.mainContext.insert(character); store.mainContext.insert(provider); try store.mainContext.save()
        let service = ProactiveService(context: store.mainContext, notifications: RecordingNotifications(), readSystemContext: false)
        await #expect(throws: LLMError.missingKey) { try await service.respond(characterID: character.id, text: "你好", scenario: nil, token: UUID().uuidString, notify: false) }
        let messages = try store.mainContext.fetch(FetchDescriptor<Message>())
        #expect(messages.count == 1); #expect(messages.first?.content == "你好")
        #expect(messages.first?.status == .failed)
    }
    @Test func notificationFailureCanRetrySavedOutputWithoutAnotherModelCall() async throws {
        let store = try container(); let context = store.mainContext
        let character = LumiCharacter(); let provider = ProviderConfig()
        context.insert(character); context.insert(provider); try context.save()
        let keychain = KeychainStore(service: "app.lumi.outbox.\(UUID())")
        try keychain.save("mock-key", for: provider.id); defer { try? keychain.delete(for: provider.id) }
        let client = SequenceCompletionClient(["欢迎回来。"]); let driver = RecordingNotifications(); driver.failNext = true
        let service = ProactiveService(context: context, client: client, notifications: driver, keychain: keychain, readSystemContext: false)
        let token = UUID().uuidString
        await #expect(throws: LLMError.network) { try await service.respond(characterID: character.id, text: "你好", scenario: nil, token: token, notify: true) }
        let output = try await service.respond(characterID: character.id, text: "你好", scenario: nil, token: token, notify: true)
        #expect(output == "欢迎回来。"); #expect(client.count == 1); #expect(driver.items.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<ScheduledGreeting>()) == 1)
    }
    @Test func failedNotificationReplySavesTextAndSendsOneRecoveryNotice() async throws {
        let store = try container(); let context = store.mainContext
        let character = LumiCharacter(); let provider = ProviderConfig()
        context.insert(character); context.insert(provider)
        let greeting = ScheduledGreeting(characterID: character.id, fireDate: .now, text: "你好", scenario: "关心")
        context.insert(greeting); try context.save()
        let driver = RecordingNotifications()
        let service = ProactiveService(context: context, notifications: driver, readSystemContext: false)
        await service.handleReply(greetingID: greeting.id, text: "我回来啦")
        await service.handleReply(greetingID: greeting.id, text: "我回来啦")
        #expect(driver.items.count == 1)
        #expect(driver.items.first?.text.contains("消息已保存") == true)
        #expect(try context.fetchCount(FetchDescriptor<Message>()) == 2)
    }
}
