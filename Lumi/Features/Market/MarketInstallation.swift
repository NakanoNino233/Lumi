import Foundation
import SwiftData

@Model final class MarketInstallation {
    @Attribute(.unique) var id: String
    var sourceID: String
    var itemData: Data
    @Attribute(.externalStorage) var packageData: Data
    var previousItemData: Data?
    @Attribute(.externalStorage) var previousPackageData: Data?
    var targetIDs: [UUID]
    var baselineTheme: Data?
    var installedAt: Date
    init(sourceID: String, item: MarketItem, data: Data) throws {
        id = sourceID + "/" + item.id; self.sourceID = sourceID
        itemData = try JSONEncoder().encode(item); packageData = data; targetIDs = []; installedAt = .now
    }
    var item: MarketItem? { try? JSONDecoder().decode(MarketItem.self, from: itemData) }
    var previousItem: MarketItem? { previousItemData.flatMap { try? JSONDecoder().decode(MarketItem.self, from: $0) } }
}

@MainActor enum MarketInstaller {
    // All database mutations use their own transaction; other screens' unsaved edits cannot be rolled back.
    static func install(item: MarketItem, data: Data, sourceID: String, container: ModelContainer, defaults: UserDefaults = AppPreferences.defaults, memeRoot: URL = MemeStore.root, rollingBack: Bool = false) async throws {
        let content = try await Task.detached(priority: .userInitiated) { try MarketPackage.inspect(data, item: item) }.value
        defer { content.cleanup() }
        try Task.checkCancellation()
        let context = ModelContext(container); context.autosaveEnabled = false
        let identity = sourceID + "/" + item.id
        let existing = try context.fetch(FetchDescriptor<MarketInstallation>()).first { $0.id == identity }
        if let existing {
            guard let prior = existing.item, prior.type == item.type,
                  rollingBack || item.isNewer(than: prior) else { throw MarketError.version }
        } else if rollingBack { throw MarketError.missing }
        let record = try existing ?? MarketInstallation(sourceID: sourceID, item: item, data: data)
        let oldItem = record.itemData; let oldData = record.packageData
        let oldIDs = record.targetIDs
        var newMemeFolder: URL?; var removedMemeFolder: URL?
        var themeToApply: MarketTheme?
        do {
            switch content {
            case .character(let card, _):
                let characters = try context.fetch(FetchDescriptor<LumiCharacter>())
                let target: LumiCharacter
                if existing != nil {
                    guard let found = characters.first(where: { oldIDs.contains($0.id) }) else { throw MarketError.missing }; target = found
                } else { target = LumiCharacter(name: card.name, isBuiltIn: false); context.insert(target) }
                let checked = try card.validated(existingNames: characters.filter { $0.id != target.id }.map(\.name))
                checked.apply(to: target); record.targetIDs = [target.id]
            case .skills(let documents):
                let all = try context.fetch(FetchDescriptor<InstalledSkill>())
                let old = all.filter { oldIDs.contains($0.id) }
                guard existing == nil || old.count == oldIDs.count else { throw MarketError.missing }
                guard all.count - old.count + documents.count <= 100 else { throw SkillError.size }
                let others = Set(all.filter { !oldIDs.contains($0.id) }.map { $0.name.lowercased() })
                guard documents.allSatisfy({ !others.contains($0.id) }) else { throw MarketError.conflict }
                var ids: [UUID] = []
                for doc in documents {
                    if let skill = old.first(where: { $0.name.lowercased() == doc.id }) {
                        skill.name = doc.name; skill.summary = doc.description; skill.instructions = doc.body
                        skill.permissions = doc.permissions; skill.tools = doc.tools; ids.append(skill.id)
                    } else { let skill = InstalledSkill(doc); context.insert(skill); ids.append(skill.id) }
                }
                for skill in old where !ids.contains(skill.id) { context.delete(skill) }
                record.targetIDs = ids
            case .memes(let prepared):
                let oldPack = try context.fetch(FetchDescriptor<MemePack>()).first { oldIDs.contains($0.id) }
                guard existing == nil || oldPack != nil else { throw MarketError.missing }
                let pack = MemePack(name: prepared.name, summary: prepared.summary, license: prepared.license, source: prepared.source)
                pack.enabled = oldPack?.enabled ?? true
                let folder = memeRoot.appendingPathComponent(pack.id.uuidString); newMemeFolder = folder
                let all = try context.fetch(FetchDescriptor<Meme>())
                let oldMemes = all.filter { oldIDs.contains($0.packID) }
                guard all.count - oldMemes.count + prepared.memes.count <= 5000 else { throw MemeError.size }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                context.insert(pack)
                for meme in prepared.memes {
                    let id = UUID(); let filename = id.uuidString + "." + (meme.path as NSString).pathExtension
                    try FileManager.default.copyItem(at: prepared.directory.appendingPathComponent(try MemeArchive.safePath(meme.path)), to: folder.appendingPathComponent(filename))
                    context.insert(Meme(id: id, packID: pack.id, fileName: filename, caption: meme.caption, keywords: meme.keywords, mood: meme.mood, source: meme.source ?? prepared.source, license: meme.license ?? prepared.license))
                }
                oldMemes.forEach { context.delete($0) }
                if let oldPack { removedMemeFolder = memeRoot.appendingPathComponent(oldPack.id.uuidString); context.delete(oldPack) }
                record.targetIDs = [pack.id]
            case .theme(let theme):
                if existing == nil { record.baselineTheme = try JSONEncoder().encode(MarketTheme.current(defaults: defaults)) }
                themeToApply = theme
            }
            if existing == nil { context.insert(record) }
            else {
                record.previousItemData = rollingBack ? nil : oldItem
                record.previousPackageData = rollingBack ? nil : oldData
            }
            record.itemData = try JSONEncoder().encode(item); record.packageData = data; record.installedAt = .now
            try context.save()
        } catch {
            context.rollback()
            if let newMemeFolder { try? FileManager.default.removeItem(at: newMemeFolder) }
            throw error
        }
        if let removedMemeFolder { try? FileManager.default.removeItem(at: removedMemeFolder) }
        if let themeToApply { themeToApply.apply(defaults: defaults); defaults.set(identity, forKey: "market.activeTheme") }
    }
    static func rollback(_ record: MarketInstallation, container: ModelContainer, defaults: UserDefaults = AppPreferences.defaults, memeRoot: URL = MemeStore.root) async throws {
        guard let item = record.previousItem, let data = record.previousPackageData else { throw MarketError.missing }
        try await install(item: item, data: data, sourceID: record.sourceID, container: container, defaults: defaults, memeRoot: memeRoot, rollingBack: true)
    }
    static func uninstall(_ recordID: String, container: ModelContainer, defaults: UserDefaults = AppPreferences.defaults, memeRoot: URL = MemeStore.root) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let record = try context.fetch(FetchDescriptor<MarketInstallation>()).first(where: { $0.id == recordID }), let item = record.item else { throw MarketError.missing }
        var folder: URL?; var restoreTheme: MarketTheme?
        switch item.type {
        case .character: break // Detach management; the friend and all conversations remain available.
        case .skill:
            for skill in try context.fetch(FetchDescriptor<InstalledSkill>()) where record.targetIDs.contains(skill.id) { context.delete(skill) }
        case .meme:
            for meme in try context.fetch(FetchDescriptor<Meme>()) where record.targetIDs.contains(meme.packID) { context.delete(meme) }
            for pack in try context.fetch(FetchDescriptor<MemePack>()) where record.targetIDs.contains(pack.id) { folder = memeRoot.appendingPathComponent(pack.id.uuidString); context.delete(pack) }
        case .theme:
            if defaults.string(forKey: "market.activeTheme") == record.id,
               let installed = try? JSONDecoder().decode(MarketTheme.self, from: record.packageData), MarketTheme.current(defaults: defaults) == installed {
                restoreTheme = record.baselineTheme.flatMap { try? JSONDecoder().decode(MarketTheme.self, from: $0) }
            }
        }
        context.delete(record)
        do { try context.save() } catch { context.rollback(); throw error }
        if let folder { try? FileManager.default.removeItem(at: folder) }
        restoreTheme?.apply(defaults: defaults)
        if defaults.string(forKey: "market.activeTheme") == recordID { defaults.removeObject(forKey: "market.activeTheme") }
    }
}
