import Foundation

enum LLMError: Error, LocalizedError, Equatable, Sendable {
    case offline, timeout, unauthorized, balance, rateLimited, modelMissing, server
    case invalidConfiguration, missingKey, invalidResponse, emptyResponse, responseTooLarge, keychain, storage, network
    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "网络已断开，请检查网络后重试。", locale: AppLocale.current)
        case .timeout: String(localized: "请求超时，请稍后重试。", locale: AppLocale.current)
        case .unauthorized: String(localized: "API Key 无效或已过期，请检查配置。", locale: AppLocale.current)
        case .balance: String(localized: "服务商余额不足，请检查账户。", locale: AppLocale.current)
        case .rateLimited: String(localized: "请求过于频繁，请稍后重试。", locale: AppLocale.current)
        case .modelMissing: String(localized: "模型不存在或不可用，请检查模型名称。", locale: AppLocale.current)
        case .server: String(localized: "模型服务暂时不可用，请稍后重试。", locale: AppLocale.current)
        case .invalidConfiguration: String(localized: "请填写有效的 HTTPS Base URL 和模型名，地址不能包含密钥、查询参数或账号信息。", locale: AppLocale.current)
        case .missingKey: String(localized: "请先在设置中保存 API Key。", locale: AppLocale.current)
        case .invalidResponse: String(localized: "服务商返回了无法识别的数据，请检查接口兼容性。", locale: AppLocale.current)
        case .emptyResponse: String(localized: "模型没有返回正文，请重试或更换模型。", locale: AppLocale.current)
        case .responseTooLarge: String(localized: "回复过长，已停止接收。", locale: AppLocale.current)
        case .keychain: String(localized: "无法访问安全钥匙串，请解锁设备后重试。", locale: AppLocale.current)
        case .storage: String(localized: "本地保存失败，请检查设备空间后重试。", locale: AppLocale.current)
        case .network: String(localized: "连接失败，请检查服务地址和网络。", locale: AppLocale.current)
        }
    }
    static func http(_ code: Int) -> LLMError {
        switch code {
        case 401, 403: .unauthorized
        case 402: .balance
        case 429: .rateLimited
        case 404: .modelMissing
        case 500...599: .server
        default: .invalidResponse
        }
    }
    static func sanitized(_ error: Error) -> LLMError {
        if let known = error as? LLMError { return known }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost: return .offline
            case .timedOut: return .timeout
            default: break
            }
        }
        // Never surface provider bodies or URLSession diagnostics, which may contain credentials.
        return .network
    }
}
