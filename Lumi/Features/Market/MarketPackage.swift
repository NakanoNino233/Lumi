import Foundation
import SwiftUI

struct MarketTheme: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var accent: String
    var bubble: String
    var background: String
    var font: String = "system"
    var bubbleStyle: String = "rounded"
    func validate() throws {
        guard schemaVersion == 1, [accent, bubble].allSatisfy(Self.hex), background.isEmpty || Self.hex(background),
              ["system", "rounded", "serif", "monospaced"].contains(font), ["rounded", "soft", "square"].contains(bubbleStyle) else { throw MarketError.package }
    }
    static func hex(_ value: String) -> Bool { value.count == 6 && value.allSatisfy { $0.isASCII && $0.isHexDigit } }
    var theme: LumiTheme { LumiTheme(accentHex: accent, bubbleHex: bubble, backgroundHex: background, fontDesign: font, bubbleStyle: bubbleStyle) }
    @MainActor static func current(defaults: UserDefaults) -> Self {
        Self(accent: defaults.string(forKey: "theme.accent") ?? "287563", bubble: defaults.string(forKey: "theme.bubble") ?? "297563", background: defaults.string(forKey: "theme.background") ?? "", font: defaults.string(forKey: "theme.font") ?? "system", bubbleStyle: defaults.string(forKey: "theme.bubbleStyle") ?? "rounded")
    }
    @MainActor func apply(defaults: UserDefaults) {
        defaults.set(accent, forKey: "theme.accent"); defaults.set(bubble, forKey: "theme.bubble"); defaults.set(background, forKey: "theme.background")
        defaults.set(font, forKey: "theme.font"); defaults.set(bubbleStyle, forKey: "theme.bubbleStyle")
    }
}
enum MarketContent: Sendable {
    case character(CharacterCard, [String])
    case skills([SkillDocument])
    case memes(PreparedMemePack)
    case theme(MarketTheme)
    var permissions: [String] {
        switch self {
        case .character(_, let tools): tools
        case .skills(let docs): Array(Set(docs.flatMap { $0.permissions + $0.tools })).sorted()
        case .memes, .theme: []
        }
    }
    func cleanup() { if case .memes(let pack) = self { try? FileManager.default.removeItem(at: pack.directory) } }
}
enum MarketPackage {
    static func inspect(_ data: Data, item: MarketItem) throws -> MarketContent {
        try item.validate(bundled: item.downloadURL.hasPrefix("bundle:"))
        try item.verify(data)
        switch item.type {
        case .character:
            let object = try fields(data, allowed: ["schemaVersion", "name", "avatar", "portrait", "personaPrompt", "speechStyle", "taboos", "backgroundStory", "firstGreeting", "tools"])
            let tools = object["tools"] as? [String] ?? []
            guard object["tools"] == nil || object["tools"] is [String], tools.count <= ToolRegistry.names.count, Set(tools).count == tools.count, tools.allSatisfy(ToolRegistry.names.contains) else { throw MarketError.package }
            return .character(try CharacterCard.decode(data, existingNames: []), tools)
        case .theme:
            _ = try fields(data, allowed: ["schemaVersion", "accent", "bubble", "background", "font", "bubbleStyle"])
            let theme = try JSONDecoder().decode(MarketTheme.self, from: data); try theme.validate(); return .theme(theme)
        case .skill, .meme:
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LumiMarket-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let ext = (item.downloadURL as NSString).pathExtension.lowercased()
            let file = folder.appendingPathComponent(item.type == .skill && ext == "md" ? "SKILL.md" : "package.zip")
            try data.write(to: file, options: .atomic)
            if item.type == .skill {
                let docs = try SkillImport.read(file)
                guard Set(docs.map(\.id)).count == docs.count else { throw MarketError.conflict }
                return .skills(docs)
            }
            return .memes(try MemeArchive.prepare(file))
        }
    }
    static func fields(_ data: Data, allowed: Set<String>) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(value.keys).isSubset(of: allowed) else { throw MarketError.package }
        return value
    }
}
