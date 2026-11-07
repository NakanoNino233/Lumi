import Foundation
import SwiftData

enum ProviderDefaults {
    static let model = "deepseek-flash"
    static let displayName = "DeepSeek V4.1 Flash"
    /// Upgrade only the old built-in preset. Custom providers and intentional changes survive.
    @MainActor static func upgrade(_ config: ProviderConfig, context: ModelContext) throws {
        guard config.defaultsVersion == nil else { return }
        let old = (config.modelName, config.supportsTools, config.supportsVision)
        if config.name == "DeepSeek", config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "https://api.deepseek.com",
           config.modelName == "deepseek-chat", !config.supportsTools, !config.supportsVision {
            config.modelName = model; config.supportsTools = true; config.supportsVision = true
        }
        config.defaultsVersion = 1
        do { try context.save() }
        catch { config.modelName = old.0; config.supportsTools = old.1; config.supportsVision = old.2; config.defaultsVersion = nil; throw error }
    }
}
