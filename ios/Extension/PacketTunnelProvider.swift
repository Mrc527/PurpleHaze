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

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var iodine: Iodine?

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Try to start logging immediately
        try? StdioRedirect.shared.start()
        
        NSLog("PacketTunnelProvider: startTunnel called") // System log backup
        print("PacketTunnelProvider: startTunnel called", to: &StdioRedirect.standardError)
        if let options = options {
            print("Options: \(options.keys.joined(separator: ", "))", to: &StdioRedirect.standardError)
        } else {
            print("Options: nil", to: &StdioRedirect.standardError)
        }
        
        var mtu: Int?
        var clientIp: String?
        var serverIp: String?
        var subnetMask: String?
        
        // A system-initiated reconnect has no start options. Use the same profile
        // snapshot persisted on the VPN manager, not another profile's preferences.
        let configured = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let source: [String: Any]?
        if let options = options, !options.isEmpty { source = options }
        else if let configured = configured, !configured.isEmpty { source = configured }
        else { source = UserDefaults.standard.dictionary(forKey: IodineSettings.lastSavedSettings) }
        let publicKeys: Set<String> = [IodineSettings.profileID, IodineSettings.credentialRevision,
            IodineSettings.topDomain, IodineSettings.encrypted, IodineSettings.serverProxy,
            IodineSettings.nameserverHost, IodineSettings.ipv6Support, IodineSettings.rawMode,
            IodineSettings.lazyMode, IodineSettings.maxDownstreamFragmentSize, IodineSettings.selectTimeout,
            IodineSettings.hostnameMaxLength, IodineSettings.forceDnsType, IodineSettings.forceEncoding,
            IodineSettings.defaultRoute, IodineSettings.dnsMode, IodineSettings.dnsServer,
            IodineSettings.pacConfigUrl, IodineSettings.pacJavascript, IodineSettings.httpProxyServer,
            IodineSettings.httpProxyPort, IodineSettings.httpsProxyServer, IodineSettings.httpsProxyPort]
        let savedOptions = source?.filter { publicKeys.contains($0.key) }
        UserDefaults.standard.set(savedOptions, forKey: IodineSettings.lastSavedSettings)
        iodine = Iodine(options: savedOptions)
        iodine!.delegate = self
        let mtuObserver = NotificationCenter.default.addObserver(forName: IodineSetMTUNotification as NSNotification.Name, object: nil, queue: nil) { notification in
            mtu = notification.userInfo![kIodineMTU] as? Int
        }
        let ipObserver = NotificationCenter.default.addObserver(forName: IodineSetIPNotification as NSNotification.Name, object: nil, queue: nil) { notification in
            clientIp = notification.userInfo![kIodineClientIP] as? String
            serverIp = notification.userInfo![kIodineServerIP] as? String
            subnetMask = notification.userInfo![kIodineSubnetMask] as? String
        }
        defer {
            NotificationCenter.default.removeObserver(mtuObserver)
            NotificationCenter.default.removeObserver(ipObserver)
        }
        do {
            try iodine!.start()
            guard clientIp != nil && serverIp != nil && subnetMask != nil else {
                throw IodineError.internalError
            }
        } catch {
            iodine?.stop()
            iodine = nil
            let errorMsg = "ERROR starting iodine: \(error.localizedDescription)"
            print(errorMsg, to: &StdioRedirect.standardError)
            NSLog("%@", errorMsg) // Fallback to system log
            completionHandler(error)
            return
        }
        print("Network server: \(serverIp ?? "nil"), client: \(clientIp ?? "nil"), subnet: \(subnetMask ?? "nil")", to: &StdioRedirect.standardError)
        guard let serverIp = serverIp, let clientIp = clientIp, let subnetMask = subnetMask else {
            let error = IodineError.internalError
            print("ERROR: Missing network configuration. Server: \(self.iodine?.tunDnsServer ?? "nil")", to: &StdioRedirect.standardError)
            completionHandler(error)
            return
        }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverIp)
        let ipv4 = NEIPv4Settings(addresses: [clientIp], subnetMasks: [subnetMask])
        let fullRoute = savedOptions?[IodineSettings.serverProxy] as? Bool == true ||
            (savedOptions?[IodineSettings.defaultRoute] as? Bool ?? true)
        if fullRoute {
            ipv4.includedRoutes = [.default()]
        } else {
            let address = clientIp.split(separator: ".").compactMap { UInt8($0) }
            let mask = subnetMask.split(separator: ".").compactMap { UInt8($0) }
            guard address.count == 4, mask.count == 4 else {
                iodine?.stop()
                iodine = nil
                completionHandler(IodineError.internalError)
                return
            }
            let network = zip(address, mask).map { String($0 & $1) }.joined(separator: ".")
            ipv4.includedRoutes = [NEIPv4Route(destinationAddress: network, subnetMask: subnetMask)]
        }
        settings.ipv4Settings = ipv4
        // iodine carries IPv4 only; capture and discard IPv6 instead of bypassing the tunnel.
        let ipv6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [128])
        ipv6.includedRoutes = [.default()]
        settings.ipv6Settings = ipv6
        print("Network MTU: \(mtu ?? 0)", to: &StdioRedirect.standardError)
        if let mtu = mtu {
            settings.mtu = NSNumber(value: mtu)
        }
        configureDnsAndProxy(for: settings, with: savedOptions, serverIP: serverIp)
        setTunnelNetworkSettings(settings) { error in
            if error == nil {
                print("Tunnel started successfully!", to: &StdioRedirect.standardError)
                self.readPackets()
            } else {
                self.iodine?.stop()
                self.iodine = nil
                print("ERROR in setTunnelNetworkSettings: \(error?.localizedDescription ?? "(unknown)")", to: &StdioRedirect.standardError)
            }
            completionHandler(error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        print("PacketTunnelProvider: stopTunnel called with reason: \(reason.rawValue)", to: &StdioRedirect.standardError)
        iodine?.stop()
        iodine = nil
        StdioRedirect.shared.stop()
        completionHandler()
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.iodine != nil else { return }
            for (i, packet) in packets.enumerated() {
                self.iodine?.writeData(packet, family: protocols[i].int32Value)
            }
            self.readPackets()
        }
    }
    
    private func configureDnsAndProxy(for config: NEPacketTunnelNetworkSettings, with options: [String: Any]?, serverIP: String) {
        let proxyMode = options?[IodineSettings.serverProxy] as? Bool == true
        let mode = options?[IodineSettings.dnsMode] as? String ?? "custom"
        let configuredDNS = options?[IodineSettings.dnsServer] as? String ?? "8.8.8.8"
        let dnsServer: String?
        if proxyMode { dnsServer = mode == "custom" && !configuredDNS.isEmpty ? configuredDNS : "1.1.1.1" }
        else if mode == "system" { dnsServer = nil }
        else if mode == "tunnel" { dnsServer = serverIP }
        else { dnsServer = configuredDNS.isEmpty ? "1.1.1.1" : configuredDNS }
        if let dnsServer = dnsServer {
            print("Network DNS: \(dnsServer)", to: &StdioRedirect.standardError)
            let dnsSettings = NEDNSSettings(servers: [dnsServer])
            dnsSettings.matchDomains = [""]
            config.dnsSettings = dnsSettings
            // Custom/tunnel DNS must enter packetFlow even with subnet-only routing.
            let fullRoute = proxyMode || (options?[IodineSettings.defaultRoute] as? Bool ?? true)
            if !fullRoute {
                config.ipv4Settings?.includedRoutes?.append(NEIPv4Route(destinationAddress: dnsServer, subnetMask: "255.255.255.255"))
            }
        }
        // Full proxy mode converts all tunneled IPv4 TCP/UDP on the server.
        if proxyMode { return }
        let proxy = NEProxySettings()
        if let pacConfigUrl = options?[IodineSettings.pacConfigUrl] as? String, pacConfigUrl.count > 0 {
            proxy.autoProxyConfigurationEnabled = true
            proxy.proxyAutoConfigurationURL = URL(string: pacConfigUrl)
            print("Network PAC URL: \(pacConfigUrl)", to: &StdioRedirect.standardError)
        }
        if let pacJavascript = options?[IodineSettings.pacJavascript] as? String, pacJavascript.count > 0 {
            proxy.autoProxyConfigurationEnabled = true
            proxy.proxyAutoConfigurationJavaScript = pacJavascript
            print("Network PAC Javascript: \(pacJavascript)", to: &StdioRedirect.standardError)
        }
        let httpProxyPortString = options?[IodineSettings.httpProxyPort] as? String
        let httpProxyPort = Int(httpProxyPortString ?? "0") ?? 0
        if let httpProxyServer = options?[IodineSettings.httpProxyServer] as? String, httpProxyServer.count > 0 {
            proxy.httpEnabled = true
            proxy.httpServer = NEProxyServer(address: httpProxyServer, port: httpProxyPort)
            print("Network HTTP Proxy: \(httpProxyServer):\(httpProxyPort)", to: &StdioRedirect.standardError)
        }
        let httpsProxyPortString = options?[IodineSettings.httpsProxyPort] as? String
        let httpsProxyPort = Int(httpsProxyPortString ?? "0") ?? 0
        if let httpsProxyServer = options?[IodineSettings.httpsProxyServer] as? String, httpsProxyServer.count > 0 {
            proxy.httpsEnabled = true
            proxy.httpsServer = NEProxyServer(address: httpsProxyServer, port: httpsProxyPort)
            print("Network HTTPS Proxy: \(httpsProxyServer):\(httpsProxyPort)", to: &StdioRedirect.standardError)
        }
        if proxy.autoProxyConfigurationEnabled || proxy.httpEnabled || proxy.httpsEnabled {
            proxy.matchDomains = [""]
            config.proxySettings = proxy
        }
    }
}

extension PacketTunnelProvider: IodineDelegate {
    func iodineError(_ error: Error?) {
        print("ERROR: \(error?.localizedDescription ?? "(unknown)")", to: &StdioRedirect.standardError)
        cancelTunnelWithError(error)
    }
    
    func iodineReadData(_ data: [Data], withProtocols protocols: [NSNumber]) {
        packetFlow.writePackets(data, withProtocols: protocols)
    }
    
    func iodineDidStop() {
        print("Tunnel stopped.", to: &StdioRedirect.standardError)
        cancelTunnelWithError(nil)
    }
}
