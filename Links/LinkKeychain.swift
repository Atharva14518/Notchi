import Foundation
import Security
import LocalAuthentication

protocol LinkSecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func save(_ data: Data, account: String) throws
    func remove(_ account: String)
}
struct LinkKeychain: LinkSecretStore {
    let service = "com.notchi.links.credentials"
    func read(_ account: String) throws -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var legacy = query
            legacy[kSecAttrService as String] = BrandMigration.previousKeychain
            let context = LAContext(); context.interactionNotAllowed = true
            legacy[kSecUseAuthenticationContext as String] = context
            guard SecItemCopyMatching(legacy as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            try save(data, account: account)
            return data
        }
        guard status == errSecSuccess, let data = result as? Data else { throw LinkError.keychain }
        return data
    }
    func save(_ data: Data, account: String) throws {
        let query = base(account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw LinkError.keychain }
        } else if status != errSecSuccess { throw LinkError.keychain }
    }
    func remove(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var legacy = base(account); legacy[kSecAttrService as String] = BrandMigration.previousKeychain
        let context = LAContext(); context.interactionNotAllowed = true
        legacy[kSecUseAuthenticationContext as String] = context
        SecItemDelete(legacy as CFDictionary)
    }
    private func base(_ account: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account, kSecAttrSynchronizable as String:false]
    }
}
