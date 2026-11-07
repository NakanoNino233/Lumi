import Foundation
import ZIPFoundation
import CryptoKit
import ImageIO
import SQLite3

struct ImportedMeme: Sendable {
    var path: String
    var caption: String
    var keywords: String
    var mood: String
    var source: String? = nil
    var license: String? = nil
}
struct PreparedMemePack: Sendable {
    var directory: URL
    var name: String
    var summary: String
    var license: String
    var source: String
    var memes: [ImportedMeme]
}
struct ExportMeme: Sendable { var file: URL; var caption: String; var keywords: String; var mood: String; var source: String = ""; var license: String = "" }

enum MemeArchive {
    static let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp"]
    static func safePath(_ path: String) throws -> String {
        guard !path.isEmpty, path.utf8.count < 1000, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\\"), !path.contains(":"), path.rangeOfCharacter(from: .controlCharacters) == nil else { throw MemeError.unsafePath }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw MemeError.unsafePath }
        return path
    }
    static func validateImage(_ data: Data) throws {
        guard data.count <= 10_000_000 else { throw MemeError.size }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) as String?,
              ["public.png", "public.jpeg", "com.compuserve.gif", "org.webmproject.webp"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 20_000_000,
              CGImageSourceGetCount(source) <= 500,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) != nil else { throw MemeError.image }
        for index in 1..<CGImageSourceGetCount(source) {
            guard let info = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 20_000_000 else { throw MemeError.image }
        }
    }
    static func prepare(_ zip: URL) throws -> PreparedMemePack {
        let access = zip.startAccessingSecurityScopedResource()
        defer { if access { zip.stopAccessingSecurityScopedResource() } }
        guard (try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 200_000_000 else { throw MemeError.size }
        let archive: Archive
        do { archive = try Archive(url: zip, accessMode: .read) } catch { throw MemeError.archive }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiMemeImport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var names = Set<String>(); var total: UInt64 = 0; var imageCount = 0; var count = 0
            // Validate every central-directory entry before writing anything.
            for entry in archive {
                count += 1; guard count <= 2500 else { throw MemeError.size }
                let path = try safePath(entry.type == .directory && entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path)
                let folded = path.precomposedStringWithCanonicalMapping.lowercased()
                guard names.insert(folded).inserted, entry.type != .symlink else { throw MemeError.unsafePath }
                if entry.type == .directory { continue }
                let ext = (path as NSString).pathExtension.lowercased()
                let base = (path as NSString).lastPathComponent
                let isImage = imageExtensions.contains(ext)
                guard isImage || ["manifest.json", "index.db", "checksums.json", "LICENSE", "LICENSE.txt", "license.txt"].contains(base) else { throw MemeError.format }
                let limit: UInt64 = isImage ? 10_000_000 : (base == "index.db" ? 10_000_000 : 1_000_000)
                guard entry.uncompressedSize <= limit else { throw MemeError.size }
                total += entry.uncompressedSize; if isImage { imageCount += 1 }
                guard total <= 300_000_000, imageCount <= 1000, entry.compressedSize > 0 || entry.uncompressedSize == 0,
                      entry.uncompressedSize / max(1, entry.compressedSize) <= 200 else { throw MemeError.size }
            }
            guard imageCount > 0 else { throw MemeError.format }
            for entry in archive where entry.type == .file {
                try Task.checkCancellation()
                let destination = folder.appendingPathComponent(entry.path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
                let handle = try FileHandle(forWritingTo: destination)
                var written: UInt64 = 0
                do {
                    let crc = try archive.extract(entry, consumer: { chunk in
                        try Task.checkCancellation()
                        written += UInt64(chunk.count)
                        guard written <= entry.uncompressedSize, written <= 10_000_000 else { throw MemeError.size }
                        try handle.write(contentsOf: chunk)
                    })
                    try handle.close()
                    guard written == entry.uncompressedSize, crc == entry.checksum else { throw MemeError.checksum }
                } catch { try? handle.close(); throw error }
            }
            return try inspect(folder)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    static func inspect(_ folder: URL) throws -> PreparedMemePack {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
        let files = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let indexes = files.filter { $0.lastPathComponent == "index.db" }
        let manifests = files.filter { $0.lastPathComponent == "manifest.json" }
        guard indexes.count <= 1, manifests.count <= 1, files.filter({ $0.lastPathComponent == "checksums.json" }).count <= 1 else { throw MemeError.index }
        let root = indexes.first?.deletingLastPathComponent() ?? manifests.first?.deletingLastPathComponent() ?? folder
        guard files.allSatisfy({ $0.path.hasPrefix(root.path + "/") }) else { throw MemeError.unsafePath }
        var manifest: [String: Any] = [:]
        if let file = manifests.first {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else { throw MemeError.index }
            manifest = object
        }
        if manifest["sha256"] != nil && !(manifest["sha256"] is [String: String]) { throw MemeError.checksum }
        var checksums = manifest["sha256"] as? [String: String] ?? [:]
        if let file = files.first(where: { $0.lastPathComponent == "checksums.json" }) {
            guard let values = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String] else { throw MemeError.checksum }
            for (path, value) in values {
                if let prior = checksums[path], prior.caseInsensitiveCompare(value) != .orderedSame { throw MemeError.checksum }
                checksums[path] = value
            }
        }
        for (path, expected) in checksums {
            let relative = try safePath(path)
            let url = root.appendingPathComponent(relative)
            guard expected.count == 64, FileManager.default.fileExists(atPath: url.path), hash(try Data(contentsOf: url)).caseInsensitiveCompare(expected) == .orderedSame else { throw MemeError.checksum }
        }
        let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        for image in images { try Task.checkCancellation(); try validateImage(Data(contentsOf: image)) }
        let relativeImages = Set(images.map { String($0.path.dropFirst(root.path.count + 1)) })
        var rows: [ImportedMeme]
        if let index = indexes.first { rows = try MemeIndex.read(index) }
        else { rows = [] }
        guard rows.allSatisfy({ relativeImages.contains($0.path) }) else { throw MemeError.index }
        let indexed = Set(rows.map(\.path))
        for path in relativeImages.sorted() where !indexed.contains(path) {
            rows.append(ImportedMeme(path: path, caption: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, keywords: "", mood: URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent))
        }
        if let metadata = manifest["imageMetadata"] as? [String: [String: String]] {
            rows = rows.map { row in
                var row = row
                row.source = metadata[row.path]?["source"].map { String($0.prefix(1000)) }
                row.license = metadata[row.path]?["license"].map { String($0.prefix(1000)) }
                return row
            }
        }
        let prefix = root == folder ? "" : String(root.path.dropFirst(folder.path.count + 1)) + "/"
        rows = rows.map { var row = $0; row.path = prefix + row.path; return row }
        let name = String((manifest["name"] as? String ?? "导入的图库").prefix(120))
        return PreparedMemePack(directory: folder, name: name, summary: String((manifest["description"] as? String ?? "").prefix(1000)), license: String((manifest["license"] as? String ?? "未提供许可，请自行确认使用范围").prefix(1000)), source: String((manifest["source"] as? String ?? "本地 ZIP 导入").prefix(1000)), memes: rows)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func export(name: String, summary: String, license: String, source: String, items: [ExportMeme]) throws -> URL {
        guard !items.isEmpty, items.count <= 1000 else { throw MemeError.format }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiMemeExport-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("memes"), withIntermediateDirectories: true)
        do {
            var rows: [ImportedMeme] = []; var checksums: [String: String] = [:]; var metadata: [String: [String: String]] = [:]; var total = 0
            for item in items {
                try Task.checkCancellation()
                let data = try Data(contentsOf: item.file); try validateImage(data)
                total += data.count
                guard total <= 300_000_000 else { throw MemeError.size }
                let path = "memes/" + UUID().uuidString + "." + item.file.pathExtension.lowercased()
                try data.write(to: folder.appendingPathComponent(path), options: .atomic)
                checksums[path] = hash(data)
                metadata[path] = ["source": item.source, "license": item.license]
                rows.append(ImportedMeme(path: path, caption: item.caption, keywords: item.keywords, mood: item.mood))
            }
            try MemeIndex.write(folder.appendingPathComponent("index.db"), rows: rows)
            checksums["index.db"] = hash(try Data(contentsOf: folder.appendingPathComponent("index.db")))
            let manifest: [String: Any] = ["id": UUID().uuidString, "name": name, "description": summary, "version": "1.0.0", "license": license, "source": source, "imageMetadata": metadata]
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            guard manifestData.count <= 1_000_000 else { throw MemeError.size }
            try manifestData.write(to: folder.appendingPathComponent("manifest.json"))
            try JSONEncoder().encode(checksums).write(to: folder.appendingPathComponent("checksums.json"))
            let output = folder.appendingPathExtension("zip")
            do {
                let archive = try Archive(url: output, accessMode: .create)
                for file in rows.map(\.path) + ["index.db", "manifest.json", "checksums.json"] {
                    try archive.addEntry(with: file, relativeTo: folder, compressionMethod: .deflate)
                }
            }
            let verification = try Archive(url: output, accessMode: .read)
            guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 200_000_000,
                  verification.allSatisfy({ $0.uncompressedSize <= 10_000_000 && $0.uncompressedSize / max(1, $0.compressedSize) <= 200 }),
                  verification.reduce(UInt64(0), { $0 + $1.uncompressedSize }) <= 300_000_000 else { throw MemeError.size }
            try FileManager.default.removeItem(at: folder)
            return output
        } catch { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: folder.appendingPathExtension("zip")); throw error }
    }
}

enum MemeIndex {
    static func read(_ url: URL) throws -> [ImportedMeme] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else { if db != nil { sqlite3_close(db) }; throw MemeError.index }
        defer { sqlite3_close(db) }
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 128_000)
        sqlite3_limit(db, SQLITE_LIMIT_COLUMN, 64)
        sqlite3_limit(db, SQLITE_LIMIT_EXPR_DEPTH, 20)
        let steps = UnsafeMutablePointer<Int>.allocate(capacity: 1); steps.initialize(to: 0)
        sqlite3_progress_handler(db, 1000, { pointer in
            guard let pointer else { return 1 }
            let steps = pointer.assumingMemoryBound(to: Int.self)
            steps.pointee += 1
            return steps.pointee > 3000 ? 1 : 0
        }, steps)
        defer { sqlite3_progress_handler(db, 0, nil, nil); steps.deinitialize(count: 1); steps.deallocate() }
        sqlite3_exec(db, "PRAGMA trusted_schema=OFF", nil, nil, nil)
        var table: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT type FROM sqlite_master WHERE name='memes'", -1, &table, nil) == SQLITE_OK else { throw MemeError.index }
        defer { sqlite3_finalize(table) }
        guard sqlite3_step(table) == SQLITE_ROW, String(cString: sqlite3_column_text(table, 0)) == "table" else { throw MemeError.index }
        var statement: OpaquePointer?
        let sql = "SELECT path, COALESCE(caption,''), COALESCE(keywords,''), COALESCE(tag,'') FROM memes LIMIT 1001"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, sqlite3_stmt_readonly(statement) == 1 else { throw MemeError.index }
        defer { sqlite3_finalize(statement) }
        var rows: [ImportedMeme] = []; var seen = Set<String>(); var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
            let path = try MemeArchive.safePath(text(0))
            guard seen.insert(path).inserted else { throw MemeError.index }
            rows.append(ImportedMeme(path: path, caption: String(text(1).prefix(1000)), keywords: String(text(2).prefix(1000)), mood: String(text(3).prefix(100))))
            guard rows.count <= 1000 else { throw MemeError.size }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw MemeError.index }
        return rows
    }
    static func write(_ url: URL, rows: [ImportedMeme]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw MemeError.index }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE memes (path TEXT PRIMARY KEY, tag TEXT, file_name TEXT, caption TEXT, keywords TEXT, mtime REAL, captioned_at REAL)", nil, nil, nil) == SQLITE_OK else { throw MemeError.index }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO memes VALUES (?,?,?,?,?,0,0)", -1, &statement, nil) == SQLITE_OK else { throw MemeError.index }
            defer { sqlite3_finalize(statement) }
            for (index, value) in [row.path, row.mood, (row.path as NSString).lastPathComponent, row.caption, row.keywords].enumerated() {
                _ = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw MemeError.index }
        }
    }
}
