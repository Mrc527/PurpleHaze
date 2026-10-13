import Foundation

/// Public configuration only. Secrets live in a revision-scoped Keychain item.
struct ConnectionProfile: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var credentialRevision = UUID().uuidString
    var name = "New profile"
    var topDomain = ""
    var encrypted = true
    var serverProxy = false
    var nameserverHost = ""
    var dnsMode = "custom"
    var dnsServer = "1.1.1.1"
    var defaultRoute = true
    var ipv6Support = false
    var rawMode = false
    var lazyMode = true
    var maxDownstreamFragmentSize = 0
    var selectTimeout = 1
    var hostnameMaxLength = 255
    var forceDnsType = ""
    var forceEncoding = ""
    // Retain old Settings.app HTTP/PAC settings during migration. New profiles
    // use serverProxy; these compatibility options are intentionally not exposed.
    var legacyProxyOptions: [String: String] = [:]

    var options: [String: NSObject] {
        [IodineSettings.profileID: id as NSString,
         IodineSettings.credentialRevision: credentialRevision as NSString,
         IodineSettings.topDomain: topDomain as NSString,
         IodineSettings.encrypted: NSNumber(value: encrypted),
         IodineSettings.serverProxy: NSNumber(value: serverProxy),
         IodineSettings.nameserverHost: nameserverHost as NSString,
         IodineSettings.dnsMode: dnsMode as NSString,
         IodineSettings.dnsServer: dnsServer as NSString,
         IodineSettings.defaultRoute: NSNumber(value: defaultRoute),
         IodineSettings.ipv6Support: NSNumber(value: ipv6Support),
         IodineSettings.rawMode: NSNumber(value: rawMode),
         IodineSettings.lazyMode: NSNumber(value: lazyMode),
         IodineSettings.maxDownstreamFragmentSize: NSNumber(value: maxDownstreamFragmentSize),
         IodineSettings.selectTimeout: NSNumber(value: selectTimeout),
         IodineSettings.hostnameMaxLength: NSNumber(value: hostnameMaxLength),
         IodineSettings.forceDnsType: forceDnsType as NSString,
         IodineSettings.forceEncoding: forceEncoding as NSString]
            .merging(legacyProxyOptions.mapValues { $0 as NSString }) { current, _ in current }
    }

    func validate() throws {
        guard UUID(uuidString: id) != nil, UUID(uuidString: credentialRevision) != nil else {
            throw ProfileError.invalid("Invalid profile identifier.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileError.invalid("Enter a profile name.")
        }
        let labels = topDomain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, topDomain.utf8.count <= 253, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { throw ProfileError.invalid("Enter a valid tunnel domain, for example tunnel.example.com.") }
        guard ["system", "tunnel", "custom"].contains(dnsMode) else { throw ProfileError.invalid("Invalid DNS mode.") }
        if dnsMode == "custom" {
            let parts = dnsServer.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil && !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else {
                throw ProfileError.invalid("Enter an IPv4 address for the custom DNS server.")
            }
        }
        guard !serverProxy || encrypted else { throw ProfileError.invalid("Server proxy requires an encrypted connection.") }
        guard (0...65535).contains(maxDownstreamFragmentSize), (1...60).contains(selectTimeout),
              (100...255).contains(hostnameMaxLength), topDomain.utf8.count + 16 < hostnameMaxLength else {
            throw ProfileError.invalid("Use a fragment size of 0–65535, timeout of 1–60 seconds and hostname length of 100–255, leaving room for the tunnel domain.")
        }
        guard ["", "NULL", "PRIVATE", "CNAME", "A", "MX", "SRV", "TXT"].contains(forceDnsType),
              ["", "base32", "base64", "base64u", "base128", "raw"].contains(forceEncoding) else {
            throw ProfileError.invalid("Invalid DNS record type or downstream encoding.")
        }
    }
}

enum ProfileError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
