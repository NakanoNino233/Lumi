import Foundation
import SwiftData

@MainActor enum MemeStore {
    static var root: URL {
        if AppPreferences.isUITesting { return FileManager.default.temporaryDirectory.appendingPathComponent("LumiUITestMemes") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LumiMemes", isDirectory: true)
    }
    static func url(_ meme: Meme, root: URL = root) -> URL {
        root.appendingPathComponent(meme.packID.uuidString).appendingPathComponent(meme.fileName)
    }
    static func enabled(in context: ModelContext) throws -> [Meme] {
        let packs = try context.fetch(FetchDescriptor<MemePack>()).filter(\.enabled)
        let ids = Set(packs.map(\.id))
        return try context.fetch(FetchDescriptor<Meme>(sortBy: [SortDescriptor(\.caption)])).filter { ids.contains($0.packID) }
    }
    static func snapshot(_ meme: Meme, root: URL = root) throws -> SentMeme {
        let data = try Data(contentsOf: url(meme, root: root)); try MemeArchive.validateImage(data)
        return SentMeme(sourceID: meme.id, caption: meme.caption, data: data)
    }
    static func install(_ prepared: PreparedMemePack, in context: ModelContext, root: URL = root) throws -> MemePack {
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        guard try context.fetchCount(FetchDescriptor<Meme>()) + prepared.memes.count <= 5000 else { throw MemeError.size }
        let pack = MemePack(name: prepared.name, summary: prepared.summary, license: prepared.license, source: prepared.source)
        let folder = root.appendingPathComponent(pack.id.uuidString)
        var inserted: [Meme] = []
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            context.insert(pack)
            for item in prepared.memes {
                let id = UUID(); let fileName = id.uuidString + "." + (item.path as NSString).pathExtension.lowercased()
                let safe = try MemeArchive.safePath(item.path)
                try FileManager.default.copyItem(at: prepared.directory.appendingPathComponent(safe), to: folder.appendingPathComponent(fileName))
                let meme = Meme(id: id, packID: pack.id, fileName: fileName, caption: item.caption, keywords: item.keywords, mood: item.mood, source: item.source ?? prepared.source, license: item.license ?? prepared.license)
                context.insert(meme); inserted.append(meme)
            }
            try context.save(); return pack
        } catch {
            inserted.forEach { context.delete($0) }; context.delete(pack)
            try? FileManager.default.removeItem(at: folder)
            throw MemeError.storage
        }
    }
    static func seed(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<MemePack>()) == 0,
              !AppPreferences.defaults.bool(forKey: "memes.seeded") || AppPreferences.isUITesting,
              let zip = Bundle.main.url(forResource: "Lumi-Starter-Memes", withExtension: "zip") else { return }
        let prepared = try MemeArchive.prepare(zip)
        _ = try install(prepared, in: context)
        AppPreferences.defaults.set(true, forKey: "memes.seeded")
    }
    static func create(name: String, in context: ModelContext) throws -> MemePack {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 120 else { throw MemeError.metadata }
        let pack = MemePack(name: clean, source: "用户创建")
        context.insert(pack)
        do { try context.save(); return pack } catch { context.delete(pack); throw MemeError.storage }
    }
    static func addImage(_ data: Data, extension ext: String, to pack: MemePack, context: ModelContext, root: URL = root) throws {
        try MemeArchive.validateImage(data)
        guard MemeArchive.imageExtensions.contains(ext.lowercased()), try context.fetchCount(FetchDescriptor<Meme>()) < 5000 else { throw MemeError.size }
        let id = UUID(); let name = id.uuidString + "." + ext.lowercased()
        let meme = Meme(id: id, packID: pack.id, fileName: name, caption: String(localized: "新表情", locale: AppLocale.current), source: pack.source, license: pack.license)
        let file = url(meme, root: root)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            context.insert(meme); try context.save()
        } catch { context.delete(meme); try? FileManager.default.removeItem(at: file); throw MemeError.storage }
    }
    static func remove(_ meme: Meme, context: ModelContext, root: URL = root) throws {
        let file = url(meme, root: root); context.delete(meme)
        do { try context.save() } catch { context.rollback(); throw MemeError.storage }
        try? FileManager.default.removeItem(at: file)
    }
    static func remove(_ pack: MemePack, context: ModelContext, root: URL = root) throws {
        let id = pack.id
        let memes = try context.fetch(FetchDescriptor<Meme>(predicate: #Predicate { $0.packID == id }))
        for meme in memes { context.delete(meme) }; context.delete(pack)
        do { try context.save() } catch { context.rollback(); throw MemeError.storage }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString))
    }
}
