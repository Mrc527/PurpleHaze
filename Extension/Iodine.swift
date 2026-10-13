//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

final public class Iodine: NSObject {
    public private(set) var ipv6Support: Bool = true
    public private(set) var nameserverHost: String? = nil
    public private(set) var topDomain: String? = nil
    public private(set) var encrypted: Bool = false
    public private(set) var serverProxy: Bool = false
    public private(set) var maxDownstreamFragmentSize: Int = 0
    public private(set) var rawMode: Bool = true
    public private(set) var lazyMode: Bool = true
    public private(set) var selectTimeout: Int = 4
    public private(set) var hostnameMaxLength: Int = 0xFF
    public private(set) var forceDnsType: String? = nil
    public private(set) var forceEncoding: String? = nil
    
    public weak var delegate: IodineDelegate?
    
    private var iodineToNetworkExtensionSocket: Int32 = -1
    private var networkExtensionToIodineSocket: Int32 = -1
    private var dnsSocket: Int32 = -1
    private var profileID: String?
    private var credentialRevision: String?
    private var invalidProfileReference = false
    private var topDomainPtr: UnsafeMutablePointer<CChar>?
    
    private var packetSource: DispatchSourceRead?
    private let packetQueue = DispatchQueue(label: "Iodine.packets")
    
    private var runQueue: DispatchQueue?
    private var isSetupComplete: Bool = false
    private var isRunning: Bool = false
    private var nameserver = sockaddr_storage()
    
    private var defaultNameserver: sockaddr_storage? {
        func getSystemDNS() -> sockaddr_storage? {
            let statePtr = UnsafeMutablePointer<__res_9_state>.allocate(capacity: 1)
            defer {
                statePtr.deallocate()
            }
            statePtr.initialize(to: __res_9_state())
            defer {
                statePtr.deinitialize(count: 1)
            }
            var servers = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: Int(NI_MAXSERV))
            if res_9_ninit(statePtr) != 0 {
                print("ERROR: res_9_ninit failed", to: &StdioRedirect.standardError)
                return nil
            }
            defer {
                res_9_nclose(statePtr)
            }
            let count = res_9_getservers(statePtr, &servers, NI_MAXSERV)
            print("Found \(count) DNS servers", to: &StdioRedirect.standardError)
            guard count > 0 else {
                return nil
            }
            var serversList = servers
            serversList.removeLast(Int(NI_MAXSERV - count))
            
            guard var server = serversList.first(where: { server in
                self.ipv6Support || server.sin6.sin6_family != AF_INET6
            }) else {
                return nil
            }
            var result = sockaddr_storage()
            withUnsafePointer(to: &server) { addr in
                withUnsafeMutableBytes(of: &result) { target in
                    target.copyBytes(from: UnsafeRawBufferPointer(start: addr, count: MemoryLayout<res_9_sockaddr_union>.size))
                }
            }
            return result
        }

        if let systemDNS = getSystemDNS() {
            return systemDNS
        }
        
        print("WARNING: System DNS not found. Fallback to 8.8.8.8", to: &StdioRedirect.standardError)
        var storage = sockaddr_storage()
        let host = "8.8.8.8"
        if let hostPtr = host.unsafeAllocate() {
            defer { hostPtr.deallocate() }
            var len: socklen_t = 0
            if get_addr(hostPtr, 53, AF_INET, 0, &storage, &len) == 0 {
                return storage
            }
        }
        return nil
    }
    
    public var tunDnsServer: String? {
        guard var defaultNameserver = defaultNameserver else {
            return nil
        }
        let dnsHostname = String(cString: format_addr(&defaultNameserver, socklen_t(defaultNameserver.ss_len)))
        return dnsHostname
    }
    
    public convenience init(options: [String : Any]? = nil) {
        self.init()
        guard let options = options else {
            return
        }
        if let ipv6Support = options[IodineSettings.ipv6Support] as? Bool {
            self.ipv6Support = ipv6Support
        }
        if let nameserverHost = options[IodineSettings.nameserverHost] as? String, nameserverHost.count > 0 {
            self.nameserverHost = nameserverHost
        }
        if let topDomain = options[IodineSettings.topDomain] as? String, topDomain.count > 0 {
            self.topDomain = topDomain
        }
        if options[IodineSettings.profileID] != nil || options[IodineSettings.credentialRevision] != nil {
            profileID = options[IodineSettings.profileID] as? String
            credentialRevision = options[IodineSettings.credentialRevision] as? String
            invalidProfileReference = profileID == nil || credentialRevision == nil || options[IodineSettings.encrypted] as? Bool == nil
        }
        encrypted = options[IodineSettings.encrypted] as? Bool ?? false
        serverProxy = options[IodineSettings.serverProxy] as? Bool ?? false
        let maxDownstreamFragmentSize: Int?
        if let maxDownstreamFragmentSizeString = options[IodineSettings.maxDownstreamFragmentSize] as? String, maxDownstreamFragmentSizeString.count > 0 {
            maxDownstreamFragmentSize = Int(maxDownstreamFragmentSizeString)
        } else {
            maxDownstreamFragmentSize = options[IodineSettings.maxDownstreamFragmentSize] as? Int
        }
        if let maxDownstreamFragmentSize = maxDownstreamFragmentSize {
            if maxDownstreamFragmentSize > 0xffff {
                self.maxDownstreamFragmentSize = 0xffff
            } else {
                self.maxDownstreamFragmentSize = maxDownstreamFragmentSize
            }
        }
        if let rawMode = options[IodineSettings.rawMode] as? Bool {
            self.rawMode = rawMode
        }
        if let lazyMode = options[IodineSettings.lazyMode] as? Bool {
            self.lazyMode = lazyMode
            if !lazyMode {
                self.selectTimeout = 1
            }
        }
        let selectTimeout: Int?
        if let selectTimeoutString = options[IodineSettings.selectTimeout] as? String, selectTimeoutString.count > 0 {
            selectTimeout = Int(selectTimeoutString)
        } else {
            selectTimeout = options[IodineSettings.selectTimeout] as? Int
        }
        if let selectTimeout = selectTimeout {
            if selectTimeout < 1 {
                self.selectTimeout = 1
            } else {
                self.selectTimeout = selectTimeout
            }
        }
        let hostnameMaxLength: Int?
        if let hostnameMaxLengthString = options[IodineSettings.hostnameMaxLength] as? String, hostnameMaxLengthString.count > 0 {
            hostnameMaxLength = Int(hostnameMaxLengthString)
        } else {
            hostnameMaxLength = options[IodineSettings.hostnameMaxLength] as? Int
        }
        if let hostnameMaxLength = hostnameMaxLength {
            if hostnameMaxLength > 255 {
                self.hostnameMaxLength = 255
            } else if hostnameMaxLength < 10 {
                self.hostnameMaxLength = 10
            } else {
                self.hostnameMaxLength = hostnameMaxLength
            }
        }
        if let forceDnsType = options[IodineSettings.forceDnsType] as? String, forceDnsType.count > 0 {
            self.forceDnsType = forceDnsType
        }
        if let forceEncoding = options[IodineSettings.forceEncoding] as? String, forceEncoding.count > 0 {
            self.forceEncoding = forceEncoding
        }
    }
    
    private func setup() throws {
        print("Iodine: setup called", to: &StdioRedirect.standardError)
        guard !isSetupComplete else {
            throw IodineError.internalError
        }
        
        if let forceDnsType = forceDnsType {
            print("Iodine: Setting forceDnsType to \(forceDnsType)", to: &StdioRedirect.standardError)
            let forceDnsTypePtr = forceDnsType.unsafeAllocate()!
            client_set_qtype(forceDnsTypePtr)
            forceDnsTypePtr.deallocate()
        }
        
        if let forceEncoding = forceEncoding {
            print("Iodine: Setting forceEncoding to \(forceEncoding)", to: &StdioRedirect.standardError)
            let forceEncodingPtr = forceEncoding.unsafeAllocate()
            client_set_downenc(forceEncodingPtr)
            forceEncodingPtr?.deallocate()
        }
        
        let family = ipv6Support ? AF_UNSPEC : AF_INET
        if let host = nameserverHost {
            print("Iodine: Using custom nameserver host: \(host)", to: &StdioRedirect.standardError)
            let hostPtr = host.unsafeAllocate()!
            var len: socklen_t = 0
            let result = get_addr(hostPtr, DNS_PORT, family, 0, &nameserver, &len)
            hostPtr.deallocate()
            guard result == 0 else {
                throw IodineError.invalidNameserverHost
            }
            client_set_nameserver(&nameserver, Int32(len))
        } else {
            print("Iodine: Using default nameserver", to: &StdioRedirect.standardError)
            guard let defaultNameserver = defaultNameserver else {
                throw IodineError.defaultDnsNotFound
            }
            nameserver = defaultNameserver
            client_set_nameserver(&nameserver, Int32(nameserver.ss_len))
        }
        
        guard let topdomain = topDomain else {
            throw IodineError.invalidTopdomain()
        }
        print("Iodine: Top domain is \(topdomain)", to: &StdioRedirect.standardError)
        var errormsg: UnsafeMutablePointer<CChar>? = nil
        if let topDomainPtr = topDomainPtr {
            topDomainPtr.deallocate()
        }
        topDomainPtr = topdomain.unsafeAllocate()
        guard check_topdomain(topDomainPtr, 0, &errormsg) == 0 else {
            throw IodineError.invalidTopdomain(message: errormsg?.string)
        }
        client_set_topdomain(topDomainPtr)
        
        client_set_selecttimeout(Int32(selectTimeout))
        client_set_lazymode(lazyMode ? 1 : 0)
        client_set_hostname_maxlen(Int32(hostnameMaxLength))
        
        guard !invalidProfileReference, !serverProxy || encrypted else { throw IodineError.invalidCredentials }
        let credentialData: Data
        if let profileID = profileID, let revision = credentialRevision {
            let bundle = try ProfileCredentials.read(profileID: profileID, revision: revision, encrypted: encrypted)
            credentialData = encrypted ? bundle.sharedKey! : Data(bundle.password!.utf8)
        } else {
            // Compatibility only for an old VPN configuration with no profile reference.
            // A malformed or missing scoped item must never fall back to these globals.
            guard let data = try Credentials.read(encrypted ? Credentials.sharedKey : Credentials.password) else {
                throw IodineError.invalidCredentials
            }
            credentialData = data
        }
        var data = credentialData
        defer { data.resetBytes(in: 0..<data.count) }
        if encrypted {
            guard data.count == 32 else { throw IodineError.invalidCredentials }
            let ok = data.withUnsafeBytes { bytes in
                client_set_key(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
            guard ok == 1 else { throw IodineError.invalidCredentials }
        } else {
            guard data.count <= 32, !data.contains(0), let password = String(data: data, encoding: .utf8) else {
                throw IodineError.invalidCredentials
            }
            password.withCString { client_set_password($0) }
        }
        client_set_proxy(serverProxy ? 1 : 0)

        runQueue = DispatchQueue(label: "Iodine")
        isSetupComplete = true
    }
    
    public func start() throws {
        print("Iodine: start called", to: &StdioRedirect.standardError)
        guard !isRunning else {
            throw IodineError.internalError
        }
        
        client_init()
        
        if !isSetupComplete {
            try setup()
        }
        
        var fds = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else {
            throw IodineError.socketCreateFailed
        }
        iodineToNetworkExtensionSocket = fds[0]
        networkExtensionToIodineSocket = fds[1]
        
        print("Connecting to DNS...", to: &StdioRedirect.standardError)
        dnsSocket = open_dns_from_host(nil, 0, Int32(nameserver.ss_family), AI_PASSIVE)
        guard dnsSocket >= 0 else {
            print("ERROR: open_dns_from_host failed", to: &StdioRedirect.standardError)
            stop()
            throw IodineError.dnsOpenFailed
        }
        
        
        let dnsHostname = String(cString: format_addr(&nameserver, socklen_t(nameserver.ss_len)))
        print("Sending DNS queries for \(topDomain ?? "(null)") to \(dnsHostname)", to: &StdioRedirect.standardError);
        guard client_handshake(dnsSocket, rawMode ? 1 : 0, maxDownstreamFragmentSize > 0 ? 0 : 1, Int32(maxDownstreamFragmentSize)) == 0 else {
            print("ERROR: client_handshake failed", to: &StdioRedirect.standardError)
            stop()
            throw IodineError.handshakeFailed
        }
        
        if client_get_conn() == CONN_RAW_UDP {
            let rawAddr = client_get_raw_addr()
            print("Sending raw traffic directly to \(rawAddr?.string ?? "(unknown)")", to: &StdioRedirect.standardError)
        }
        
        print("Connection setup complete, transmitting data.", to: &StdioRedirect.standardError)
        
        self.isRunning = true
        openPackets()
        let tunFD = networkExtensionToIodineSocket, dnsFD = dnsSocket
        runQueue!.async {
            client_tunnel(tunFD, dnsFD)
            DispatchQueue.main.async {
                if self.isRunning { self.delegate?.iodineDidStop() }
            }
        }
    }
    
    public func stop() {
        isRunning = false
        client_stop()
        // Wake select before waiting for the worker. Close descriptors only after it exits.
        packetQueue.sync {
            if iodineToNetworkExtensionSocket >= 0 {
                var wake: UInt8 = 0
                _ = send(iodineToNetworkExtensionSocket, &wake, 1, MSG_DONTWAIT)
            }
        }
        runQueue?.sync {}
        packetQueue.sync {
            packetSource?.cancel()
            packetSource = nil
            if iodineToNetworkExtensionSocket >= 0 { close(iodineToNetworkExtensionSocket) }
            iodineToNetworkExtensionSocket = -1
        }
        if networkExtensionToIodineSocket >= 0 { close(networkExtensionToIodineSocket) }
        networkExtensionToIodineSocket = -1
        if dnsSocket >= 0 { close_dns(dnsSocket) }
        dnsSocket = -1
        client_cleanup()
        isSetupComplete = false
    }

    private func openPackets() {
        let fd = iodineToNetworkExtensionSocket
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: packetQueue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = recv(fd, &bytes, bytes.count, MSG_DONTWAIT)
            guard count >= 24, bytes[4] >> 4 == 4 else { return }
            let packet = Data(bytes[4..<count])
            self.delegate?.iodineReadData([packet], withProtocols: [NSNumber(value: AF_INET)])
        }
        packetSource = source
        source.resume()
    }

    public func writeData(_ data: Data, family: Int32) {
        // The iodine tunnel carries IPv4. Preserve one datagram per IP packet.
        guard family == AF_INET else { return }
        var prefix = UInt32(0x0800).bigEndian
        var packet = withUnsafeBytes(of: &prefix) { Data($0) }
        packet.append(data)
        packetQueue.async {
            guard self.iodineToNetworkExtensionSocket >= 0 else { return }
            packet.withUnsafeBytes { bytes in
                _ = send(self.iodineToNetworkExtensionSocket, bytes.baseAddress, bytes.count, MSG_DONTWAIT)
            }
        }
    }

    deinit { topDomainPtr?.deallocate() }
}

public enum IodineError: LocalizedError {
    case invalidCredentials
    case internalError
    case invalidNameserverHost
    case defaultDnsNotFound
    case invalidTopdomain(message: String? = nil)
    case socketCreateFailed
    case dnsOpenFailed
    case handshakeFailed
    case notConnected
    case invalidPacket
    case incompletePacket
    case unrecognizedFamily(_ family: Int32)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Missing or invalid tunnel credentials. An encrypted connection requires the server’s 32-byte shared key."
        case .internalError:
            return NSLocalizedString("An internal error has occurred.", comment: "Iodine")
        case .invalidNameserverHost:
            return NSLocalizedString("Invalid nameserver host.", comment: "Iodine")
        case .defaultDnsNotFound:
            return NSLocalizedString("Cannot get default DNS address.", comment: "Iodine")
        case .invalidTopdomain(let message):
            return NSLocalizedString("Invalid top domain: \(message ?? "unknown cause")", comment: "Iodine")
        case .socketCreateFailed:
            return NSLocalizedString("Failed to create socketpair for communication.", comment: "Iodine")
        case .dnsOpenFailed:
            return NSLocalizedString("Failed to open connection to DNS server.", comment: "Iodine")
        case .handshakeFailed:
            return NSLocalizedString("Failed to establish handshake with server.", comment: "Iodine")
        case .notConnected:
            return NSLocalizedString("Not connected.", comment: "Iodine")
        case .invalidPacket:
            return NSLocalizedString("Invalid packet.", comment: "Iodine")
        case .incompletePacket:
            return NSLocalizedString("Incomplete packet.", comment: "Iodine")
        case .unrecognizedFamily(let family):
            return NSLocalizedString("Unrecognized family \(family).", comment: "Iodine")
        }
    }
}

fileprivate extension String {
    func unsafeAllocate(capacity: Int = 0) -> UnsafeMutablePointer<CChar>? {
        let utf8 = self.utf8CString
        let result = UnsafeMutableBufferPointer<CChar>.allocate(capacity: capacity > 0 ? capacity : utf8.count)
        let (_, lastIndex) = result.initialize(from: utf8)
        let remaining = UnsafeMutableBufferPointer<CChar>(rebasing: result.suffix(from: lastIndex))
        remaining.initialize(repeating: 0)
        return result.baseAddress
    }
}

fileprivate extension UnsafePointer where Pointee == CChar {
    var string: String {
        String(cString: self)
    }
}

fileprivate extension UnsafeMutablePointer where Pointee == CChar {
    var string: String {
        String(cString: self)
    }
}
