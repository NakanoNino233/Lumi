import Foundation
import SwiftData
import UIKit

@MainActor enum GroupMentionNotifier {
    static func eligible(text: String, enabled: Bool, preferences: CompanionPreferences, now: Date, occupiedDates: [Date], calendar: Calendar = .current) -> Bool {
        guard enabled, preferences.enabled, !preferences.isQuiet(now, calendar: calendar),
              text.range(of: "[@＠](我|用户)(?=$|[\\s，。！？、,:：!?.])", options: .regularExpression) != nil else { return false }
        return occupiedDates.filter { calendar.isDate($0, inSameDayAs: now) }.count < preferences.dailyLimit
    }
    static func deliverIfNeeded(message: GroupMessage, group: GroupChat, friend: LumiCharacter, context: ModelContext) async {
        guard UIApplication.shared.applicationState != .active else { return }
        let driver = LocalNotificationDriver()
        guard await driver.authorized() else { return }
        do {
            let greetings = try context.fetch(FetchDescriptor<ScheduledGreeting>()).filter { $0.stateRaw == "scheduled" || $0.stateRaw == "elapsed" }.map(\.fireDate)
            let mentions = try context.fetch(FetchDescriptor<GroupMessage>()).compactMap(\.notificationAt)
            let now = Date.now
            guard eligible(text: message.text, enabled: group.mentionNotifications, preferences: .current, now: now, occupiedDates: greetings + mentions) else { return }
            // Reserve before awaiting system delivery so concurrent producers see the quota.
            message.notificationAt = now; try context.save()
            do {
                try await driver.add(CompanionNotification(id: message.id, characterID: friend.id, title: group.name, text: "\(friend.name) 在群里 @ 了你：\(String(message.text.prefix(80)))", date: now.addingTimeInterval(1), avatar: friend.avatarData, groupID: group.id))
            } catch { message.notificationAt = nil; try context.save() }
        } catch { /* A notification failure must not discard a saved group message. */ }
    }
}
