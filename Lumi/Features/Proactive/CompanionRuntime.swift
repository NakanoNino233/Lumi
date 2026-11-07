import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import Observation

@MainActor enum CompanionRuntime {
    static let refreshIdentifier = "app.lumi.greetings.refresh"
    static let container: ModelContainer? = {
        let schema = LumiSchema.schema
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: AppPreferences.isUITesting, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [config])
    }()
    static func scheduleRefresh() {
        guard !AppPreferences.isUITesting, CompanionPreferences.current.enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        try? BGTaskScheduler.shared.submit(request)
    }
}

@MainActor @Observable final class ConversationRouter {
    static let shared = ConversationRouter()
    var revision = UUID()
    var pendingCharacterID: UUID?
    var pendingGroupID: UUID?
    func open(groupID: UUID) { pendingCharacterID = nil; pendingGroupID = groupID; revision = UUID() }
    func open(characterID: UUID) {
        pendingGroupID = nil
        pendingCharacterID = characterID
        AppPreferences.defaults.set(characterID.uuidString, forKey: "selectedCharacter")
        revision = UUID()
    }
}

@MainActor final class LumiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard !AppPreferences.isUITesting else { return true }
        UNUserNotificationCenter.current().delegate = self
        LocalNotificationDriver.registerCategories()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: CompanionRuntime.refreshIdentifier, using: .main) { task in
            Task { @MainActor in
                let worker = Task { @MainActor in
                    await ProactiveService.shared?.refresh(foreground: false)
                    CompanionRuntime.scheduleRefresh()
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = { worker.cancel() }
            }
        }
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                          withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .sound, .list]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                          withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let info = response.notification.request.content.userInfo
        if let value = info["groupID"] as? String, let groupID = UUID(uuidString: value) {
            let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            Self.finishResponse({ if isTap { ConversationRouter.shared.open(groupID: groupID) } }, completion: completionHandler)
            return
        }
        if info["toolReminder"] as? Bool == true, let value = info["characterID"] as? String, let characterID = UUID(uuidString: value) {
            let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            Self.finishResponse({ if isTap { ConversationRouter.shared.open(characterID: characterID) } }, completion: completionHandler)
            return
        }
        guard let value = info["greetingID"] as? String, let id = UUID(uuidString: value) else {
            Self.finishResponse({}, completion: completionHandler); return
        }
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        // UIKit snapshots the scene when this completion runs. Always finish on main,
        // including after awaited network work, rather than using the async ObjC bridge.
        Self.finishResponse({ await Self.handle(id: id, reply: reply, open: isTap) }, completion: completionHandler)
    }
    nonisolated static func finishResponse(_ work: @escaping @MainActor @Sendable () async -> Void,
                                          completion: @escaping @Sendable () -> Void) {
        Task { @MainActor in await work(); completion() }
    }
    private static func handle(id: UUID, reply: String?, open: Bool) async {
        guard let service = ProactiveService.shared else { return }
        if let reply {
            // The user text is saved before network work, and the network is cancelled on expiration.
            let task = Task { @MainActor in await service.handleReply(greetingID: id, text: reply) }
            let deadline = Task { try? await Task.sleep(for: .seconds(20)); if !Task.isCancelled { task.cancel() } }
            await task.value; deadline.cancel()
        } else if open { try? service.openGreeting(id) }
    }
}
