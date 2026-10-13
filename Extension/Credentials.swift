// Shared by the app and its tunnel extension. Secrets never enter preferences.
import Foundation
import Security

enum Credentials {
    static let sharedKey = "shared-key"
    static let password = "legacy-password"

    private static func query(_ account: String) -> [String: Any] {
        var request: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "iodine.credentials",
         kSecAttrAccount as String: account]
        if let group = Bundle.main.object(forInfoDictionaryKey: "CredentialAccessGroup") as? String {
            request[kSecAttrAccessGroup as String] = group
        }
        return request
    }

    static func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return result as? Data
    }

    static func save(_ data: Data, account: String) throws {
        let request = query(account)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(request.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw failure(status) }
        } else if status != errSecSuccess {
            throw failure(status)
        }
    }

    static func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Cannot access tunnel credentials in Keychain (\(status))."])
    }
}
