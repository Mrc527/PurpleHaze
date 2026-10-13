import Foundation

final class MemoryVault: ProfileCredentialVault {
    var items: [String: Data] = [:]
    var failWrites = false
    var failReads = false
    func read(_ account: String) throws -> Data? {
        if failReads { throw ProfileError.invalid("Vault locked") }
        return items[account]
    }
    func save(_ data: Data, account: String) throws {
        if failWrites { throw ProfileError.invalid("Vault write failed") }
        items[account] = data
    }
    func remove(_ account: String) throws { items.removeValue(forKey: account) }
}

@main
struct ProfileStoreTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        count += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: " + message) }
        catch { count += 1 }
    }
    static func withFixture(_ body: (UserDefaults, MemoryVault, URL) throws -> Void) throws {
        let name = "PurpleHaze.ProfileTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(defaults, MemoryVault(), directory.appendingPathComponent("profiles.json"))
    }
    static func main() throws {
        let keyA = Data(repeating: 17, count: 32).base64EncodedString()
        let keyB = Data(repeating: 29, count: 32).base64EncodedString()
        try withFixture { defaults, vault, file in
            let store = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            check(store.profiles.isEmpty && store.selectedProfile == nil, "Pristine app should have no profiles")
            var first = ConnectionProfile()
            first.name = "Home"; first.topDomain = "home.example.com"; first.serverProxy = true
            try store.save(first, keyBase64: keyA, password: "")
            first = store.selectedProfile!
            var second = ConnectionProfile()
            second.name = "Work"; second.topDomain = "work.example.com"
            try store.save(second, keyBase64: keyB, password: "")
            second = store.profiles.last!
            try store.select(second.id)
            let reloaded = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            check(reloaded.selectedID == second.id && reloaded.profiles.count == 2, "Selection must survive reload")
            let a = try reloaded.secrets(for: first), b = try reloaded.secrets(for: second)
            check(a.keyBase64 == keyA && b.keyBase64 == keyB, "Keys must be isolated by profile")
            let json = try String(contentsOf: file, encoding: .utf8)
            check(!json.contains(keyA) && !json.contains(keyB), "No secrets in metadata")
            check(defaults.data(forKey: ProfileStore.storageKey) == nil, "Atomic file, not preferences, owns metadata")
            check(first.options[IodineSettings.profileID] as? String == first.id, "Options identify the profile")
            check(first.options[IodineSettings.password] == nil, "Options never contain the password")
            let oldRevision = second.credentialRevision
            second.encrypted = false
            try reloaded.save(second, keyBase64: "", password: "legacy-secret")
            second = reloaded.selectedProfile!
            check(second.credentialRevision != oldRevision, "Mode changes get a new immutable snapshot")
            let password = try reloaded.secrets(for: second).password
            check(password == "legacy-secret", "Legacy password retained")
            let oldAccount = try ProfileCredentials.account(profileID: second.id, revision: oldRevision)
            check(vault.items[oldAccount] == nil, "Old revision cannot silently reconnect")
            rejects("unknown profile") { try reloaded.select(UUID().uuidString) }
            var fake = first; fake.id = UUID().uuidString
            rejects("unknown secrets") { _ = try reloaded.secrets(for: fake) }
            try reloaded.delete(second.id)
            check(reloaded.selectedID == first.id, "Deleting selected profile chooses the remaining profile")
            rejects("deleted credentials") { _ = try reloaded.secrets(for: second) }
            try reloaded.delete(first.id)
            check(reloaded.profiles.isEmpty && reloaded.selectedProfile == nil && vault.items.isEmpty, "Last delete clears selection and credentials")
        }
        try withFixture { defaults, vault, file in
            defaults.set("old.example.com", forKey: IodineSettings.topDomain)
            defaults.set("migration-password", forKey: IodineSettings.password)
            defaults.set(false, forKey: IodineSettings.rawMode)
            defaults.set("7", forKey: IodineSettings.selectTimeout)
            defaults.set("9.9.9.9", forKey: IodineSettings.dnsServer)
            defaults.set("https://example.com/proxy.pac", forKey: IodineSettings.pacConfigUrl)
            let store = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            let profile = store.selectedProfile!
            check(!profile.encrypted && profile.defaultRoute && !profile.rawMode && profile.selectTimeout == 7, "Legacy settings preserved")
            check(profile.dnsServer == "9.9.9.9" && profile.dnsMode == "custom", "Legacy DNS preserved")
            check(profile.options[IodineSettings.pacConfigUrl] as? String == "https://example.com/proxy.pac", "Legacy proxy preserved")
            let migratedPassword = try store.secrets(for: profile).password
            check(migratedPassword == "migration-password", "Plaintext password migrated to scoped vault")
            check(defaults.object(forKey: IodineSettings.password) == nil, "Legacy plaintext removed after durable commit")
            let again = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            check(again.profiles.count == 1 && again.selectedID == profile.id, "Migration is idempotent")
        }
        try withFixture { defaults, vault, file in
            defaults.set("secure.example.com", forKey: IodineSettings.topDomain)
            defaults.set(true, forKey: IodineSettings.encrypted)
            vault.items[Credentials.sharedKey] = Data(base64Encoded: keyA)!
            vault.failWrites = true
            rejects("migration vault failure") { _ = try ProfileStore(defaults: defaults, vault: vault, fileURL: file) }
            check(!FileManager.default.fileExists(atPath: file.path), "Failed migration must not commit metadata")
            check(vault.items[Credentials.sharedKey] != nil, "Failed migration preserves source key")
            vault.failWrites = false
            let store = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            let profile = store.selectedProfile!
            let key = try store.secrets(for: profile).keyBase64
            check(profile.encrypted && key == keyA, "Encrypted migration preserves key and mode")
            check(vault.items[Credentials.sharedKey] == nil, "Retire old global key after migration")
            let originalData = try Data(contentsOf: file)
            vault.failWrites = true
            var edit = profile; edit.topDomain = "changed.example.com"
            rejects("save vault failure") { try store.save(edit, keyBase64: keyB, password: "") }
            let currentData = try Data(contentsOf: file)
            check(originalData == currentData && store.selectedProfile == profile, "Failed save leaves active metadata untouched")
            vault.failWrites = false
            let savedKey = try store.secrets(for: profile).keyBase64
            check(savedKey == keyA, "Failed save leaves old credentials usable")
        }
        try withFixture { defaults, vault, file in
            let store = try ProfileStore(defaults: defaults, vault: vault, fileURL: file)
            var profile = ConnectionProfile(); profile.topDomain = "disk.example.com"
            try store.save(profile, keyBase64: keyA, password: "")
            profile = store.selectedProfile!
            let directory = file.deletingLastPathComponent()
            let backup = directory.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: directory, to: backup)
            defer {
                try? FileManager.default.removeItem(at: directory)
                try? FileManager.default.moveItem(at: backup, to: directory)
            }
            try Data("not a directory".utf8).write(to: directory)
            let oldItems = vault.items
            rejects("metadata write failure") { try store.save(profile, keyBase64: keyB, password: "") }
            check(vault.items == oldItems, "Failed metadata commit removes new orphan revision and keeps old key")
            check(store.selectedProfile == profile, "Failed metadata commit leaves in-memory profile untouched")
        }
        try withFixture { defaults, vault, file in
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let corrupt = Data("{bad".utf8)
            try corrupt.write(to: file)
            rejects("corrupt metadata does not reset or re-migrate") { _ = try ProfileStore(defaults: defaults, vault: vault, fileURL: file) }
            let preserved = try Data(contentsOf: file)
            check(preserved == corrupt, "Invalid metadata preserved for recovery")
        }
        try withFixture { defaults, vault, file in
            defaults.set("missing.example.com", forKey: IodineSettings.topDomain)
            defaults.set(true, forKey: IodineSettings.encrypted)
            rejects("missing key never downgrades migration") { _ = try ProfileStore(defaults: defaults, vault: vault, fileURL: file) }
            check(!FileManager.default.fileExists(atPath: file.path), "Missing encrypted key leaves migration uncommitted")
        }
        var profile = ConnectionProfile(); profile.topDomain = "tunnel.example.com"
        try profile.validate()
        check(profile.defaultRoute && profile.dnsMode == "custom" && profile.dnsServer == "1.1.1.1" && !profile.rawMode && !profile.ipv6Support && profile.selectTimeout == 1, "Canonical Android/iOS defaults match")
        rejects("proxy without encryption") { var bad = profile; bad.encrypted = false; bad.serverProxy = true; try bad.validate() }
        rejects("invalid DNS") { var bad = profile; bad.dnsServer = "256.1.1.1"; try bad.validate() }
        rejects("invalid query type") { var bad = profile; bad.forceDnsType = "INVALID"; try bad.validate() }
        rejects("invalid base64") { _ = try ProfileCredentials.parseKey("bad key") }
        let unpadded = try ProfileCredentials.parseKey(String(keyA.dropLast()))
        check(unpadded?.count == 32, "Unpadded Base64 supported")
        let bundle = try ProfileCredentials(profileID: profile.id, revision: profile.credentialRevision, encrypted: true, keyBase64: keyA, password: "")
        rejects("profile ID mismatch") { try bundle.validate(profileID: UUID().uuidString, revision: profile.credentialRevision, encrypted: true) }
        rejects("revision mismatch") { try bundle.validate(profileID: profile.id, revision: UUID().uuidString, encrypted: true) }
        rejects("mode mismatch") { try bundle.validate(profileID: profile.id, revision: profile.credentialRevision, encrypted: false) }
        rejects("mixed credentials") { _ = try ProfileCredentials(profileID: profile.id, revision: profile.credentialRevision, encrypted: true, keyBase64: keyA, password: "secret") }
        rejects("NUL password") { _ = try ProfileCredentials(profileID: profile.id, revision: profile.credentialRevision, encrypted: false, keyBase64: "", password: "x\0y") }
        print("Passed \(count) profile/store/credential checks.")
    }
}
