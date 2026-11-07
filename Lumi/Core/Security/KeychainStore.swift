import Foundation
import Security

struct KeychainStore: Sendable {
    let service: String
    init(service: String = "app.lumi.provider-keys") { self.service = service }
    private func query(_ providerID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: providerID.uuidString]
    }
    func read(for providerID: UUID) throws -> String? {
        var request = query(providerID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw LLMError.keychain }
        return key
    }
    func save(_ key: String, for providerID: UUID) throws {
        if key.isEmpty { try delete(for: providerID); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query(providerID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(providerID)
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LLMError.keychain }
        } else if status != errSecSuccess { throw LLMError.keychain }
    }
    func delete(for providerID: UUID) throws {
        let status = SecItemDelete(query(providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LLMError.keychain }
    }
}
