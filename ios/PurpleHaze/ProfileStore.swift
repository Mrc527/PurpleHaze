import Foundation

protocol ProfileCredentialVault {
    func read(_ account: String) throws -> Data?
    func save(_ data: Data, account: String) throws
    func remove(_ account: String) throws
}

struct KeychainProfileVault: ProfileCredentialVault {
    func read(_ account: String) throws -> Data? { try Credentials.read(account) }
    func save(_ data: Data, account: String) throws { try Credentials.save(data, account: account) }
    func remove(_ account: String) throws { try Credentials.remove(account) }
}

/// Main-thread owner of profile metadata. A single encoded document contains both
/// the ordered profiles and selection; credentials are committed before metadata.
final class ProfileStore {
    static let storageKey = "PurpleHaze.Profiles.v1"
    private struct Document: Codable {
        var version = 1
        var profiles: [ConnectionProfile]
        var selectedID: String?
    }
    private let defaults: UserDefaults
    private let vault: ProfileCredentialVault
    private let fileURL: URL
    private(set) var profiles: [ConnectionProfile] = []
    private(set) var selectedID: String?
    var selectedProfile: ConnectionProfile? { profiles.first { $0.id == selectedID } }

    init(defaults: UserDefaults = .standard, vault: ProfileCredentialVault = KeychainProfileVault(), fileURL: URL? = nil) throws {
        self.defaults = defaults
        self.vault = vault
        self.fileURL = try fileURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PurpleHaze", isDirectory: true).appendingPathComponent("profiles.json")
        let storedData = FileManager.default.fileExists(atPath: self.fileURL.path)
            ? try Data(contentsOf: self.fileURL) : defaults.data(forKey: Self.storageKey)
        if let data = storedData {
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1, Set(document.profiles.map(\.id)).count == document.profiles.count,
                  document.profiles.allSatisfy({ UUID(uuidString: $0.id) != nil && UUID(uuidString: $0.credentialRevision) != nil }),
                  document.selectedID == nil || document.profiles.contains(where: { $0.id == document.selectedID }) else {
                throw ProfileError.invalid("The saved profile list is invalid. Existing credentials have been preserved.")
            }
            profiles = document.profiles
            selectedID = document.selectedID
            // Also upgrades the short-lived preferences-backed profile format.
            try persist(profiles, selectedID: selectedID)
            try cleanupLegacySecrets()
        } else {
            try migrateLegacy()
        }
    }

    func select(_ id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else { throw ProfileError.invalid("This profile no longer exists.") }
        try persist(profiles, selectedID: id)
    }

    func save(_ profile: ConnectionProfile, keyBase64: String, password: String) throws {
        var updated = profile
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.topDomain = updated.topDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nameserverHost = updated.nameserverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.dnsServer = updated.dnsServer.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.credentialRevision = UUID().uuidString
        try updated.validate()
        let bundle = try ProfileCredentials(profileID: updated.id, revision: updated.credentialRevision,
                                            encrypted: updated.encrypted, keyBase64: keyBase64, password: password)
        let account = try ProfileCredentials.account(profileID: updated.id, revision: updated.credentialRevision)
        try vault.save(JSONEncoder().encode(bundle), account: account)
        var next = profiles
        let previous = next.first(where: { $0.id == updated.id })
        if let index = next.firstIndex(where: { $0.id == updated.id }) { next[index] = updated }
        else { next.append(updated) }
        do { try persist(next, selectedID: selectedID ?? updated.id) }
        catch { try? vault.remove(account); throw error }
        // Old provider snapshots intentionally fail closed after an edit; the app
        // saves the newly selected snapshot to its VPN manager before connecting.
        if let previous = previous {
            try? vault.remove(ProfileCredentials.account(profileID: previous.id, revision: previous.credentialRevision))
        }
    }

    func secrets(for profile: ConnectionProfile) throws -> (keyBase64: String, password: String) {
        guard profiles.contains(where: { $0.id == profile.id && $0.credentialRevision == profile.credentialRevision }) else {
            throw ProfileError.invalid("This profile is missing or has changed. Reload the profile list.")
        }
        let account = try ProfileCredentials.account(profileID: profile.id, revision: profile.credentialRevision)
        guard let data = try vault.read(account) else { throw ProfileError.invalid("Credentials for this profile are missing.") }
        let bundle = try JSONDecoder().decode(ProfileCredentials.self, from: data)
        try bundle.validate(profileID: profile.id, revision: profile.credentialRevision, encrypted: profile.encrypted)
        return (bundle.sharedKey?.base64EncodedString() ?? "", bundle.password ?? "")
    }

    func delete(_ id: String) throws {
        guard let profile = profiles.first(where: { $0.id == id }) else { throw ProfileError.invalid("This profile no longer exists.") }
        // Remove the secret first: an old VPN snapshot cannot reconnect to a
        // deleted profile. A crash leaves a visible, repairable profile, not a key.
        try vault.remove(ProfileCredentials.account(profileID: profile.id, revision: profile.credentialRevision))
        let next = profiles.filter { $0.id != id }
        try persist(next, selectedID: selectedID == id ? next.first?.id : selectedID)
    }

    private func persist(_ next: [ConnectionProfile], selectedID: String?) throws {
        let data = try JSONEncoder().encode(Document(profiles: next, selectedID: selectedID))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        defaults.removeObject(forKey: Self.storageKey)
        profiles = next
        self.selectedID = selectedID
    }

    private func migrateLegacy() throws {
        var old = defaults.dictionary(forKey: IodineSettings.lastSavedSettings) ?? [:]
        let keys = [IodineSettings.topDomain, IodineSettings.encrypted, IodineSettings.serverProxy,
                    IodineSettings.nameserverHost, IodineSettings.ipv6Support, IodineSettings.rawMode,
                    IodineSettings.lazyMode, IodineSettings.maxDownstreamFragmentSize, IodineSettings.selectTimeout,
                    IodineSettings.hostnameMaxLength, IodineSettings.forceDnsType, IodineSettings.forceEncoding,
                    IodineSettings.dnsServer, IodineSettings.password,
                    IodineSettings.pacConfigUrl, IodineSettings.pacJavascript,
                    IodineSettings.httpProxyServer, IodineSettings.httpProxyPort,
                    IodineSettings.httpsProxyServer, IodineSettings.httpsProxyPort]
        for key in keys { if let value = defaults.object(forKey: key) { old[key] = value } }
        let key = try vault.read(Credentials.sharedKey)
        let passwordData = try vault.read(Credentials.password)
        if let passwordData = passwordData, String(data: passwordData, encoding: .utf8) == nil {
            throw ProfileError.invalid("The previous password could not be decoded. Existing credentials have been preserved.")
        }
        let password = passwordData.flatMap { String(data: $0, encoding: .utf8) } ?? (old[IodineSettings.password] as? String ?? "")
        let domain = old[IodineSettings.topDomain] as? String ?? ""
        guard !domain.isEmpty || key != nil || !password.isEmpty else {
            try persist([], selectedID: nil)
            defaults.removeObject(forKey: IodineSettings.password)
            return
        }
        var profile = ConnectionProfile()
        profile.name = "Default"
        profile.topDomain = domain
        profile.encrypted = old[IodineSettings.encrypted] as? Bool ?? false
        profile.serverProxy = old[IodineSettings.serverProxy] as? Bool ?? false
        profile.nameserverHost = old[IodineSettings.nameserverHost] as? String ?? ""
        profile.ipv6Support = old[IodineSettings.ipv6Support] as? Bool ?? true
        profile.rawMode = old[IodineSettings.rawMode] as? Bool ?? true
        profile.lazyMode = old[IodineSettings.lazyMode] as? Bool ?? true
        profile.defaultRoute = true // All prior PurpleHaze versions installed the default route.
        profile.dnsMode = "custom"
        profile.dnsServer = old[IodineSettings.dnsServer] as? String ?? "8.8.8.8"
        if profile.dnsServer.isEmpty { profile.dnsServer = "8.8.8.8" }
        for key in [IodineSettings.pacConfigUrl, IodineSettings.pacJavascript,
                    IodineSettings.httpProxyServer, IodineSettings.httpProxyPort,
                    IodineSettings.httpsProxyServer, IodineSettings.httpsProxyPort] {
            if let value = old[key] as? String, !value.isEmpty { profile.legacyProxyOptions[key] = value }
        }
        profile.maxDownstreamFragmentSize = integer(old[IodineSettings.maxDownstreamFragmentSize], fallback: 0)
        profile.selectTimeout = integer(old[IodineSettings.selectTimeout], fallback: 4)
        profile.hostnameMaxLength = integer(old[IodineSettings.hostnameMaxLength], fallback: 255)
        profile.forceDnsType = old[IodineSettings.forceDnsType] as? String ?? ""
        profile.forceEncoding = old[IodineSettings.forceEncoding] as? String ?? ""
        // Explicit legacy mode remains legacy even if an unused old key exists.
        let bundle = try ProfileCredentials(profileID: profile.id, revision: profile.credentialRevision,
                                            encrypted: profile.encrypted,
                                            keyBase64: profile.encrypted ? (key?.base64EncodedString() ?? "") : "",
                                            password: profile.encrypted ? "" : password)
        let account = try ProfileCredentials.account(profileID: profile.id, revision: profile.credentialRevision)
        try vault.save(JSONEncoder().encode(bundle), account: account)
        do { try persist([profile], selectedID: profile.id) }
        catch { try? vault.remove(account); throw error }
        // Only clear the old plaintext once the migrated secret and durable metadata exist.
        try cleanupLegacySecrets()
    }

    private func cleanupLegacySecrets() throws {
        defaults.removeObject(forKey: IodineSettings.password)
        if var last = defaults.dictionary(forKey: IodineSettings.lastSavedSettings) {
            last.removeValue(forKey: IodineSettings.password)
            defaults.set(last, forKey: IodineSettings.lastSavedSettings)
        }
        try? vault.remove(Credentials.sharedKey)
        try? vault.remove(Credentials.password)
    }

    private func integer(_ value: Any?, fallback: Int) -> Int {
        if let number = value as? Int { return number }
        if let string = value as? String, let number = Int(string) { return number }
        return fallback
    }
}
