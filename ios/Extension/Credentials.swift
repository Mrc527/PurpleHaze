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

/// One immutable credential snapshot per configuration revision prevents partially
/// updated metadata from silently selecting a different key or authentication mode.
struct ProfileCredentials: Codable {
    let profileID: String
    let revision: String
    let encrypted: Bool
    let sharedKey: Data?
    let password: String?

    static func account(profileID: String, revision: String) throws -> String {
        guard UUID(uuidString: profileID) != nil, UUID(uuidString: revision) != nil else {
            throw credentialError("Invalid profile credential identifier.")
        }
        return "profile.\(profileID).\(revision)"
    }

    static func parseKey(_ text: String) throws -> Data? {
        let compact = text.filter { !$0.isWhitespace }
        if compact.isEmpty { return nil }
        let padded = compact.count == 43 ? compact + "=" : compact
        guard let data = Data(base64Encoded: padded), data.count == 32 else {
            throw credentialError("The shared key must be a Base64-encoded 32-byte key.")
        }
        return data
    }

    init(profileID: String, revision: String, encrypted: Bool, keyBase64: String, password: String) throws {
        _ = try Self.account(profileID: profileID, revision: revision)
        let key = try Self.parseKey(keyBase64)
        guard encrypted ? (key != nil && password.isEmpty) : key == nil else {
            throw Self.credentialError("Use a shared key for encrypted connections, or a password for legacy connections.")
        }
        guard password.utf8.count <= 32, !password.utf8.contains(0) else {
            throw Self.credentialError("The legacy password must contain at most 32 UTF-8 bytes and no null characters.")
        }
        self.profileID = profileID
        self.revision = revision
        self.encrypted = encrypted
        self.sharedKey = key
        self.password = encrypted ? nil : password
    }

    func validate(profileID: String, revision: String, encrypted: Bool) throws {
        _ = try Self.account(profileID: profileID, revision: revision)
        guard self.profileID == profileID, self.revision == revision, self.encrypted == encrypted,
              encrypted ? (sharedKey?.count == 32 && password == nil) : (sharedKey == nil && password != nil && password!.utf8.count <= 32 && !password!.utf8.contains(0)) else {
            throw Self.credentialError("The profile credentials are missing or do not match this configuration. Save the profile again.")
        }
    }

    static func read(profileID: String, revision: String, encrypted: Bool) throws -> ProfileCredentials {
        let account = try self.account(profileID: profileID, revision: revision)
        guard let data = try Credentials.read(account) else {
            throw credentialError("Credentials for this profile are missing. Open PurpleHaze and save the profile again.")
        }
        let value = try JSONDecoder().decode(ProfileCredentials.self, from: data)
        try value.validate(profileID: profileID, revision: revision, encrypted: encrypted)
        return value
    }

    private static func credentialError(_ message: String) -> NSError {
        NSError(domain: "PurpleHaze.Credentials", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
