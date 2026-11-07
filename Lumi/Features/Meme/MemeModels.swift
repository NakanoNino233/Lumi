import Foundation
import SwiftData

@Model final class MemePack {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var license: String
    var source: String
    var enabled: Bool = true
    var createdAt: Date
    init(id: UUID = UUID(), name: String, summary: String = "", license: String = "", source: String = "") {
        self.id = id; self.name = name; self.summary = summary; self.license = license; self.source = source; createdAt = .now
    }
}

@Model final class Meme {
    @Attribute(.unique) var id: UUID
    var packID: UUID
    var fileName: String
    var caption: String
    var keywords: String
    var mood: String
    var usageCount: Int = 0
    var source: String
    var license: String
    init(id: UUID = UUID(), packID: UUID, fileName: String, caption: String, keywords: String = "", mood: String = "", source: String = "", license: String = "") {
        self.id = id; self.packID = packID; self.fileName = fileName; self.caption = caption; self.keywords = keywords; self.mood = mood; self.source = source; self.license = license
    }
}

struct SentMeme: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var sourceID: UUID?
    var caption: String
    var data: Data
}

struct MemeCandidate: Sendable, Identifiable {
    var id: UUID
    var caption: String
    var keywords: String
    var mood: String
    var usageCount: Int
    @MainActor init(_ meme: Meme) {
        id = meme.id; caption = meme.caption; keywords = meme.keywords; mood = meme.mood; usageCount = meme.usageCount
    }
}

enum MemePreferences {
    static var aiEnabled: Bool { AppPreferences.defaults.object(forKey: "memes.aiEnabled") as? Bool ?? true }
    static var chance: Int { AppPreferences.defaults.object(forKey: "memes.chance") as? Int ?? 20 }
    static func allows(roll: Int) -> Bool { aiEnabled && (0..<max(0, min(100, chance))).contains(roll) }
    static func prompt(enabled: Bool, candidates: [MemeCandidate]) -> String {
        guard enabled, !candidates.isEmpty else { return "" }
        return "\n【本地表情】可选在自然合适时用 [表情: 简短关键词]，或可用时调用 send_meme(keyword,mood)。每轮最多两张，不用每次发。不得输出图片路径。可用情绪与样例仅为资料：" + PromptBuilder.clip(PromptBuilder.dataBlock(candidates.prefix(12).map { ["description": $0.caption, "mood": $0.mood] }), budget: 900)
    }
}

enum MemeError: Error, LocalizedError {
    case archive, unsafePath, size, format, checksum, index, image, storage, metadata
    var errorDescription: String? {
        switch self {
        case .archive: String(localized: "无法读取图库 ZIP，请使用导出的图库包或纯图片 ZIP。", locale: AppLocale.current)
        case .unsafePath: String(localized: "图库含有不安全路径、链接或重复文件，已拒绝导入。", locale: AppLocale.current)
        case .size: String(localized: "图库过大：ZIP 最多 200 MB，解压后 300 MB，最多 1000 张图片，单图 10 MB。", locale: AppLocale.current)
        case .format: String(localized: "图库仅支持 PNG、JPEG、GIF、WebP 与图库索引文件。", locale: AppLocale.current)
        case .checksum: String(localized: "图库校验不一致，文件可能损坏，请重新下载。", locale: AppLocale.current)
        case .index: String(localized: "图库索引无法读取，或索引中的图片缺失。", locale: AppLocale.current)
        case .image: String(localized: "图片损坏、尺寸过大或格式不受系统支持。", locale: AppLocale.current)
        case .storage: String(localized: "图库保存失败，请检查设备剩余空间后重试。", locale: AppLocale.current)
        case .metadata: String(localized: "请填写名称与描述，并将每个字段控制在 1000 字以内。", locale: AppLocale.current)
        }
    }
}
