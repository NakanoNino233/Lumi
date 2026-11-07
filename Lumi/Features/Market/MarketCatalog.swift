import Foundation
import CryptoKit

// Catalog and package data are inert. URLs never carry the configured model credentials.
enum MarketKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case character, skill, meme, theme
    var id: String { rawValue }
    var title: String {
        switch self {
        case .character: String(localized: "角色卡", locale: AppLocale.current)
        case .skill: String(localized: "技能包", locale: AppLocale.current)
        case .meme: String(localized: "表情包", locale: AppLocale.current)
        case .theme: String(localized: "主题", locale: AppLocale.current)
        }
    }
    var icon: String {
        switch self { case .character: "person.crop.square"; case .skill: "sparkles"; case .meme: "face.smiling"; case .theme: "paintpalette" }
    }
    var extensions: Set<String> {
        switch self { case .character, .theme: ["json"]; case .skill: ["md", "zip"]; case .meme: ["zip"] }
    }
    var limit: Int { switch self { case .character: 12_000_000; case .theme: 16_000; case .skill: 5_000_000; case .meme: 30_000_000 } }
}

enum MarketError: Error, LocalizedError {
    case catalog, address, integrity, size, package, version, missing, conflict, network
    var errorDescription: String? {
        switch self {
        case .catalog: String(localized: "目录格式无效或包含重复项目。", locale: AppLocale.current)
        case .address: String(localized: "请使用不含账号、密码或查询参数的 HTTPS 静态文件地址。", locale: AppLocale.current)
        case .integrity: String(localized: "文件大小或 SHA-256 校验失败，已拒绝安装。", locale: AppLocale.current)
        case .size: String(localized: "内容超过市场下载限制。", locale: AppLocale.current)
        case .package: String(localized: "内容格式或字段不受支持，已拒绝安装。", locale: AppLocale.current)
        case .version: String(localized: "版本应为三段数字，例如 1.0.0。", locale: AppLocale.current)
        case .missing: String(localized: "原内容已被移除，请卸载市场记录后重新安装。", locale: AppLocale.current)
        case .conflict: String(localized: "已有同名内容，或此内容正在由另一个来源管理。", locale: AppLocale.current)
        case .network: String(localized: "目录暂时无法连接。可重试或查看上次缓存。", locale: AppLocale.current)
        }
    }
}

struct MarketVersion: Comparable, Equatable, Sendable {
    let parts: [Int]
    init(_ string: String) throws {
        let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              pieces.allSatisfy({ $0 == "0" || !$0.hasPrefix("0") }) else { throw MarketError.version }
        parts = pieces.compactMap { Int($0) }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct MarketItem: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var type: MarketKind
    var name: String
    var author: String
    var summary: String
    var version: String
    var downloadURL: String
    var sha256: String
    var size: Int
    var license: String
    var previewURL: String?
    func validate(bundled: Bool) throws {
        guard !id.isEmpty, id.count <= 80, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_") }),
              !name.isEmpty, name.count <= 120, !author.isEmpty, author.count <= 120,
              summary.count <= 2000, !license.isEmpty, license.count <= 2000,
              sha256.count == 64, sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw MarketError.catalog }
        _ = try MarketVersion(version)
        guard size > 0, size <= type.limit else { throw MarketError.size }
        if bundled {
            guard downloadURL.hasPrefix("bundle:"), Self.bundleURL(downloadURL) != nil else { throw MarketError.address }
        } else { _ = try MarketAddress.url(downloadURL) }
        guard type.extensions.contains((downloadURL as NSString).pathExtension.lowercased()) else { throw MarketError.package }
        if let previewURL { _ = try MarketAddress.url(previewURL) }
    }
    static func bundleURL(_ address: String) -> URL? {
        let name = String(address.dropFirst("bundle:".count))
        guard !name.contains("/"), !name.contains("\\"), !name.contains(".."), !name.isEmpty else { return nil }
        return Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension)
    }
    func verify(_ data: Data) throws {
        guard data.count == size, data.count <= type.limit, MarketDigest.sha(data) == sha256.lowercased() else { throw MarketError.integrity }
    }
    func isNewer(than old: MarketItem) -> Bool {
        guard type == old.type, let new = try? MarketVersion(version), let prior = try? MarketVersion(old.version) else { return false }
        return new > prior
    }
}
struct MarketIndex: Codable, Sendable {
    var schemaVersion: Int
    var items: [MarketItem]
    static func decode(_ data: Data, bundled: Bool = false) throws -> Self {
        guard data.count <= 1_000_000 else { throw MarketError.size }
        let index: Self
        do { index = try JSONDecoder().decode(Self.self, from: data) } catch { throw MarketError.catalog }
        let object = try MarketPackage.fields(data, allowed: ["schemaVersion", "items"])
        guard let entries = object["items"] as? [[String: Any]], entries.allSatisfy({ Set($0.keys).isSubset(of: ["id", "type", "name", "author", "summary", "version", "downloadURL", "sha256", "size", "license", "previewURL"]) }) else { throw MarketError.catalog }
        guard index.schemaVersion == 1, index.items.count <= 500, Set(index.items.map(\.id)).count == index.items.count else { throw MarketError.catalog }
        for item in index.items { try item.validate(bundled: bundled) }
        return index
    }
}
enum MarketDigest {
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
enum MarketAddress {
    static func url(_ text: String) throws -> URL {
        guard let c = URLComponents(string: text), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.port == nil || c.port == 443,
              !host.contains("%"), let url = c.url else { throw MarketError.address }
        return url
    }
}
struct MarketSource: Codable, Sendable, Equatable {
    var primary: String = ""
    var mirror: String = ""
    var identity: String { primary.isEmpty ? "bundled" : MarketDigest.sha(Data(primary.utf8)) }
    func validate() throws {
        guard primary.count <= 2048, mirror.count <= 2048 else { throw MarketError.address }
        if !primary.isEmpty { _ = try MarketAddress.url(primary) }
        if !mirror.isEmpty { guard !primary.isEmpty else { throw MarketError.address }; _ = try MarketAddress.url(mirror) }
    }
}

// Follow at most five HTTPS redirects with a fresh anonymous request, including signed release-asset URLs.
final class MarketRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirects = 0
    static func anonymousRequest(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.fragment == nil, c.port == nil || c.port == 443 else { return nil }
        var safe = URLRequest(url: url); safe.timeoutInterval = 25; safe.httpShouldHandleCookies = false
        return safe
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed = lock.withLock { redirects += 1; return redirects <= 5 }
        completionHandler(allowed ? Self.anonymousRequest(request) : nil)
    }
}
struct MarketHTTP: Sendable {
    func fetch(_ address: String, limit: Int, configuration: URLSessionConfiguration? = nil) async throws -> Data {
        let url = try MarketAddress.url(address)
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: MarketRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.setValue("application/json, text/markdown, text/plain, application/zip, application/octet-stream, image/png, image/jpeg, image/gif, image/webp", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw MarketError.network }
        guard response.expectedContentLength <= Int64(limit) else { throw MarketError.size }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw MarketError.size }; data.append(byte)
        }
        return data
    }
}
struct MarketCatalogResult: Sendable { var index: MarketIndex; var cached: Bool; var date: Date; var mirrored: Bool }
actor MarketCatalogLoader {
    let cacheRoot: URL
    init(cacheRoot: URL) { self.cacheRoot = cacheRoot }
    func load(source: MarketSource, fetch: @Sendable (String, Int) async throws -> Data = { try await MarketHTTP().fetch($0, limit: $1) }) async throws -> MarketCatalogResult {
        try source.validate()
        if source.primary.isEmpty {
            guard let url = Bundle.main.url(forResource: "Lumi-Market-Index", withExtension: "json") else { throw MarketError.catalog }
            return MarketCatalogResult(index: try MarketIndex.decode(Data(contentsOf: url), bundled: true), cached: false, date: .now, mirrored: false)
        }
        let cache = cacheRoot.appendingPathComponent(source.identity + ".json")
        for address in [source.primary, source.mirror].filter({ !$0.isEmpty }) {
            do {
                let data = try await fetch(address, 1_000_000)
                let index = try MarketIndex.decode(data)
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                try data.write(to: cache, options: .atomic)
                return MarketCatalogResult(index: index, cached: false, date: .now, mirrored: address != source.primary)
            } catch is CancellationError { throw CancellationError() } catch { continue }
        }
        if let data = try? Data(contentsOf: cache), let index = try? MarketIndex.decode(data) {
            let date = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return MarketCatalogResult(index: index, cached: true, date: date, mirrored: false)
        }
        throw MarketError.network
    }
    func download(_ item: MarketItem, source: MarketSource) async throws -> Data {
        try item.validate(bundled: source.primary.isEmpty)
        let data: Data
        if source.primary.isEmpty, let url = MarketItem.bundleURL(item.downloadURL) { data = try Data(contentsOf: url) }
        else { data = try await MarketHTTP().fetch(item.downloadURL, limit: item.size) }
        try Task.checkCancellation(); try item.verify(data); return data
    }
}
