import Foundation
import UserNotifications
import UIKit

struct CompanionNotification: Sendable {
    var id: UUID
    var characterID: UUID
    var title: String
    var text: String
    var date: Date
    var avatar: Data?
    var groupID: UUID? = nil
    var requestID: String { "lumi.greeting." + id.uuidString }
}

@MainActor protocol NotificationDriver {
    func authorized() async -> Bool
    func pendingIDs() async -> [String]
    func remove(_ ids: [String])
    func add(_ item: CompanionNotification) async throws
}

@MainActor final class LocalNotificationDriver: NotificationDriver {
    private let center = UNUserNotificationCenter.current()
    private static var addition: Task<Void, Error>?
    func authorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func remove(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func add(_ item: CompanionNotification) async throws {
        let predecessor = Self.addition
        let work = Task { @MainActor in
            _ = try? await predecessor?.value
            try Task.checkCancellation()
            let pending = await center.pendingNotificationRequests()
            guard pending.count < 64 || pending.contains(where: { $0.identifier == item.requestID }) else { throw LLMError.rateLimited }
            try await addRequest(item)
        }
        Self.addition = work
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    private func addRequest(_ item: CompanionNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = item.title; content.body = item.text; content.sound = .default
        content.categoryIdentifier = "lumi.chat"; content.threadIdentifier = item.characterID.uuidString
        content.userInfo = ["greetingID": item.id.uuidString, "characterID": item.characterID.uuidString]
        if let groupID = item.groupID {
            content.categoryIdentifier = "lumi.group"
            content.threadIdentifier = groupID.uuidString
            content.userInfo = ["groupID": groupID.uuidString]
        }
        // The system copies an attachment on add. Remove our temporary source afterwards.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lumi-\(item.id).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let image = item.avatar.flatMap { UIImage(data: $0) } ?? UIImage(named: "LumiLogo")
        if let data = image?.jpegData(compressionQuality: 0.7) {
            try? data.write(to: file, options: .atomic)
            if let attachment = try? UNNotificationAttachment(identifier: "avatar", url: file) { content.attachments = [attachment] }
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: item.requestID, content: content, trigger: trigger))
    }
    static func registerCategories() {
        let reply = UNTextInputNotificationAction(identifier: "lumi.reply", title: String(localized: "回复", locale: AppLocale.current), options: [],
                                                   textInputButtonTitle: String(localized: "发送", locale: AppLocale.current), textInputPlaceholder: String(localized: "说点什么…", locale: AppLocale.current))
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "lumi.chat", actions: [reply], intentIdentifiers: [], options: []), UNNotificationCategory(identifier: "lumi.group", actions: [], intentIdentifiers: [], options: [])])
    }
}
