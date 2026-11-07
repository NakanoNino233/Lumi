import Foundation
import SwiftData
import ZIPFoundation
import UserNotifications

// A narrow list avoids exporting credentials, grants, caches, or notification delivery state.
enum BackupPreference: Codable, Sendable {
    case text(String), number(Int), flag(Bool)
    static let textKeys: Set<String> = ["appearance", "language", "theme.accent", "theme.bubble", "theme.background", "theme.font", "theme.bubbleStyle", "market.primary", "market.mirror", "market.activeTheme", "proactive.character", MomentsPreferences.tagsKey]
    static let numberKeys: Set<String> = ["memoryInterval", "memes.chance", "theme.textSize", "usage.dailyLimit", "wellbeing.minutes", "proactive.limit", "proactive.quietStart", "proactive.quietEnd", "tools.maximumCalls"]
    static let flagKeys: Set<String> = ["interaction.animations", "interaction.haptics", "automaticMemory", "automaticDiary", "memes.aiEnabled", "wellbeing.enabled", "voice.autoRead", "usage.limitEnabled", "context.battery"]
    static var keys: Set<String> { textKeys.union(numberKeys).union(flagKeys) }
    static func capture(_ defaults: UserDefaults) -> [String: Self] {
        var values: [String: Self] = [:]
        for key in textKeys { if let value = defaults.string(forKey: key) { values[key] = .text(value) } }
        for key in numberKeys { if defaults.object(forKey: key) != nil { values[key] = .number(defaults.integer(forKey: key)) } }
        for key in flagKeys { if defaults.object(forKey: key) != nil { values[key] = .flag(defaults.bool(forKey: key)) } }
        return values
    }
    func valid(for key: String) -> Bool {
        switch self {
        case .text(let value): Self.textKeys.contains(key) && value.utf8.count <= 2000 && (key != MomentsPreferences.tagsKey || MomentsTags.isValid(value))
        case .number(let value): Self.numberKeys.contains(key) && (0...1_000_000_000).contains(value)
        case .flag: Self.flagKeys.contains(key)
        }
    }
    func apply(_ key: String, defaults: UserDefaults) {
        switch self { case .text(let v): defaults.set(v, forKey: key); case .number(let v): defaults.set(v, forKey: key); case .flag(let v): defaults.set(v, forKey: key) }
    }
}
enum BackupError: LocalizedError, Equatable {
    case invalid, version, limit, changed
    var errorDescription: String? {
        switch self {
        case .invalid: String(localized: "备份校验失败：文件损坏、引用缺失或包含不安全内容。", locale: AppLocale.current)
        case .version: String(localized: "此备份版本暂不支持，请更新 Lumi 后重试。", locale: AppLocale.current)
        case .limit: String(localized: "备份超出限制：压缩包 500 MB、展开后 750 MB、最多 10 万条记录。", locale: AppLocale.current)
        case .changed: String(localized: "备份文件已改变，请重新选择并预览。", locale: AppLocale.current)
        }
    }
}
struct PreparedBackup: Sendable {
    let snapshot: LumiBackup
    let directory: URL
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
extension Notification.Name {
    static let lumiWillRestore = Notification.Name("app.lumi.willRestore")
    static let lumiDidRestore = Notification.Name("app.lumi.didRestore")
}
@MainActor enum BackupArchive {
    static func export(context: ModelContext, defaults: UserDefaults = AppPreferences.defaults, memeRoot: URL = MemeStore.root) async throws -> URL {
        try context.save()
        var snapshot = try LumiBackup.capture(context, defaults: defaults)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiBackup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for meme in snapshot.memes {
            let path = "memes/" + meme.packID.uuidString + "/" + (try MemeArchive.safePath(meme.fileName))
            guard !meme.fileName.contains("/") else { throw BackupError.invalid }
            let data = try Data(contentsOf: memeRoot.appendingPathComponent(meme.packID.uuidString).appendingPathComponent(meme.fileName))
            try MemeArchive.validateImage(data)
            snapshot.files[path] = MemeArchive.hash(data)
            let target = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 250_000_000 else { throw BackupError.limit }
        try data.write(to: folder.appendingPathComponent("lumi.json"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Lumi-Backup-" + UUID().uuidString + ".zip")
        try await Task.detached(priority: .userInitiated) {
            let archive = try Archive(url: output, accessMode: .create)
            try archive.addEntry(with: "lumi.json", relativeTo: folder, compressionMethod: .deflate)
            for path in snapshot.files.keys.sorted() { try archive.addEntry(with: path, relativeTo: folder, compressionMethod: .deflate) }
            guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 500_000_000 else { throw BackupError.limit }
        }.value
        return output
    }
    nonisolated static func prepare(_ url: URL) throws -> PreparedBackup {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 500_000_000 else { throw BackupError.limit }
        let archive = try Archive(url: url, accessMode: .read)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiRestore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var paths = Set<String>(); var total: UInt64 = 0
            for entry in archive {
                let path = try MemeArchive.safePath(entry.path)
                guard entry.type == .file, paths.insert(path.lowercased()).inserted,
                      path == "lumi.json" || validMemePath(path) else { throw BackupError.invalid }
                guard paths.count <= 5001, entry.uncompressedSize <= (path == "lumi.json" ? 250_000_000 : 10_000_000) else { throw BackupError.limit }
                total += entry.uncompressedSize; guard total <= 750_000_000 else { throw BackupError.limit }
            }
            guard paths.contains("lumi.json") else { throw BackupError.invalid }
            for entry in archive {
                try Task.checkCancellation()
                let target = folder.appendingPathComponent(entry.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = FileManager.default.createFile(atPath: target.path, contents: nil)
                let handle = try FileHandle(forWritingTo: target); var written: UInt64 = 0
                do {
                    let crc = try archive.extract(entry) { chunk in
                        written += UInt64(chunk.count)
                        guard written <= entry.uncompressedSize else { throw BackupError.limit }
                        try handle.write(contentsOf: chunk)
                    }
                    try handle.close()
                    guard written == entry.uncompressedSize, crc == entry.checksum else { throw BackupError.invalid }
                } catch { try? handle.close(); throw error }
            }
            let snapshot = try JSONDecoder().decode(LumiBackup.self, from: Data(contentsOf: folder.appendingPathComponent("lumi.json")))
            try snapshot.validate()
            guard Set(snapshot.files.keys.map { $0.lowercased() }).union(["lumi.json"]) == paths,
                  snapshot.preferences.allSatisfy({ $0.value.valid(for: $0.key) }) else { throw BackupError.invalid }
            for (path, hash) in snapshot.files {
                guard validMemePath(path) else { throw BackupError.invalid }
                let data = try Data(contentsOf: folder.appendingPathComponent(path))
                guard MemeArchive.hash(data) == hash else { throw BackupError.invalid }
                try MemeArchive.validateImage(data)
            }
            return PreparedBackup(snapshot: snapshot, directory: folder)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    nonisolated static func validMemePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.count == 3 && parts[0] == "memes" && UUID(uuidString: String(parts[1])) != nil &&
            MemeArchive.imageExtensions.contains((String(parts[2]) as NSString).pathExtension.lowercased())
    }
    static func restore(_ prepared: PreparedBackup, replacing: Bool, container: ModelContainer, defaults: UserDefaults = AppPreferences.defaults, memeRoot: URL = MemeStore.root, systemEffects: Bool = true) throws {
        let backup = prepared.snapshot; try backup.validate()
        let context = ModelContext(container); context.autosaveEnabled = false
        let existing = try context.fetch(FetchDescriptor<Meme>())
        let existingIDs = Set(existing.map(\.id))
        if systemEffects {
            NotificationCenter.default.post(name: .lumiWillRestore, object: nil)
            Task { await CompanionActivity.end() }
            ProactiveService.shared?.pauseForRestore()
            for character in try context.fetch(FetchDescriptor<LumiCharacter>()) { MemoryService.shared.cancel(characterID: character.id) }
        }
        var written: [(URL, Data?)] = []
        do {
            for meme in backup.memes where replacing || !existingIDs.contains(meme.id) {
                let path = "memes/" + meme.packID.uuidString + "/" + meme.fileName
                let data = try Data(contentsOf: prepared.directory.appendingPathComponent(path))
                guard backup.files[path] == MemeArchive.hash(data) else { throw BackupError.changed }
                let target = memeRoot.appendingPathComponent(meme.packID.uuidString).appendingPathComponent(meme.fileName)
                let prior = FileManager.default.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
                written.append((target, prior))
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            }
            try backup.restore(context: context, replacing: replacing)
            try CharacterLibrary.upgradeDaughterBackground(in: context, save: false)
            // Scheduled rows restore as data only. Old pending system notifications are removed below.
            for message in try context.fetch(FetchDescriptor<Message>()) where message.status == .queued || message.status == .generating { message.status = .interrupted }
            try context.save()
        } catch {
            context.rollback()
            for (target, prior) in written.reversed() { if let prior { try? prior.write(to: target, options: .atomic) } else { try? FileManager.default.removeItem(at: target) } }
            throw error
        }
        if replacing { for key in BackupPreference.keys { defaults.removeObject(forKey: key) } }
        for (key, value) in backup.preferences where value.valid(for: key) { value.apply(key, defaults: defaults) }
        if let profile = backup.personalProfile, replacing || defaults.data(forKey: PersonalProfile.storageKey) == nil {
            try profile.save(defaults: defaults)
        } else if replacing {
            defaults.removeObject(forKey: PersonalProfile.storageKey)
            defaults.removeObject(forKey: PersonalProfile.completedKey)
        }
        // Restoring never grants tools, location/calendar, or resumes proactive requests.
        defaults.set(false, forKey: "proactive.enabled")
        defaults.set(false, forKey: MomentsPreferences.enabledKey)
        if replacing { defaults.removeObject(forKey: MomentsPreferences.coverKey) }
        if let cover = backup.momentCoverData, replacing || defaults.data(forKey: MomentsPreferences.coverKey) == nil {
            defaults.set(cover, forKey: MomentsPreferences.coverKey)
        }
        // A backup is authoritative about the friend list, including intentional deletions.
        defaults.set(true, forKey: "characters.deepSeekDaughterSeeded")
        defaults.set(true, forKey: CharacterLibrary.singleFriendRosterKey)
        defaults.set(false, forKey: "context.weather"); defaults.set(false, forKey: "context.calendar")
        if systemEffects { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
        if replacing {
            let restoredPaths = Set(backup.memes.map { $0.packID.uuidString + "/" + $0.fileName })
            for meme in existing where !restoredPaths.contains(meme.packID.uuidString + "/" + meme.fileName) {
                try? FileManager.default.removeItem(at: MemeStore.url(meme, root: memeRoot))
            }
        }
        ToolPermissions.revokeAll(defaults: defaults)
        if systemEffects {
            ConversationRouter.shared.revision = UUID()
            NotificationCenter.default.post(name: .lumiDidRestore, object: nil)
        }
    }
}
