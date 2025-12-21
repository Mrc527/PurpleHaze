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

import UIKit
import NetworkExtension

class ViewController: UIViewController {
    @IBOutlet var topDomainTextField: UITextField!
    @IBOutlet var passwordTextField: UITextField!
    @IBOutlet var logTextView: UITextView!
    @IBOutlet var vpnStartSwitch: UISwitch!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    
    var vpnObserver: Any?
    var vpnManager: NEVPNManager? {
        didSet {
            guard let manager = vpnManager else {
                vpnObserver = nil
                return
            }
            vpnObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: nil, using: { [weak self] _ in
                guard let _self = self else {
                    return
                }
                if manager.connection.status == .connecting {
                    _self.vpnWillConnect(for: manager)
                } else if manager.connection.status == .disconnecting {
                    _self.vpnWillDisconnect(for: manager)
                } else if manager.connection.status == .disconnected {
                    _self.vpnDidDisconnect(for: manager)
                } else if manager.connection.status == .connected {
                    _self.vpnDidConnect(for: manager)
                }
            })
        }
    }
    
    var lastLogIndex: UInt64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        topDomainTextField.text = UserDefaults.standard.string(forKey: IodineSettings.topDomain)
        passwordTextField.text = UserDefaults.standard.string(forKey: IodineSettings.password)
        
        // 配置日志视图样式
        logTextView.backgroundColor = UIColor.systemGray6
        logTextView.layer.borderColor = UIColor.systemGray4.cgColor
        logTextView.layer.borderWidth = 1.0
        logTextView.layer.cornerRadius = 8.0
        logTextView.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        logTextView.textColor = UIColor.label
        logTextView.isEditable = false
        
        logToUI("App started")
        initVpn()
        refreshLog()
    }
    
    func logToUI(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        DispatchQueue.main.async {
            self.logTextView.text += logMessage
            self.logTextView.scrollToBottom()
        }
    }
    
    func showError(message: String?) {
        let alertMessage = message ?? NSLocalizedString("An error has occurred.", comment: "Main")
        logToUI("ERROR: \(alertMessage)")
        DispatchQueue.main.async {
            let alert = UIAlertController(title: nil, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Main"), style: .default, handler: nil))
            self.present(alert, animated: true)
            self.vpnStartSwitch.isOn = self.vpnManager?.connection.status == .connected
        }
    }

    func showError(_ error: Error?) {
        showError(message: error?.localizedDescription)
    }
    
    @IBAction func advancedSettingsPressed(_ sender: Any) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @IBAction func helpButtonPressed(_ sender: Any) {
        if let url = URL(string: "https://github.com/osy/PurpleHaze") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    @IBAction func vpnStartSwitchChanged(_ sender: Any) {
        if vpnStartSwitch.isOn {
            clearLog()
            logToUI("VPN switch turned ON")
            guard let topdomain = topDomainTextField.text, topdomain.count > 0 else {
                showError(message: NSLocalizedString("You must specify a top domain.", comment: "ViewController"))
                vpnStartSwitch.isOn = false
                return
            }
            logToUI("Top domain: \(topdomain)")
            UserDefaults.standard.set(topdomain, forKey: IodineSettings.topDomain)
            UserDefaults.standard.set(passwordTextField.text, forKey: IodineSettings.password)
            setupVpn(with: vpnManager)
        } else {
            logToUI("VPN switch turned OFF")
            guard let vpnManager = vpnManager else {
                return
            }
            stopTunnel(with: vpnManager)
        }
    }
    
    @IBAction func dismissTextField(_ sender: Any) {
    }
}

extension ViewController {
    var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".Iodine")
    }
    
    func initVpn(onExistingManager: @escaping (NEVPNManager) -> () = { _ in }) {
        logToUI("Initializing VPN manager...")
        DispatchQueue.main.async {
            self.vpnStartSwitch.isEnabled = false
        }
        Task {
            do {
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                await MainActor.run {
                    self.logToUI("Found \(managers.count) VPN configuration(s)")
                }
                if !managers.isEmpty, let manager = managers.first {
                    await MainActor.run {
                        self.vpnManager = manager
                        self.logToUI("VPN manager loaded successfully")
                    }
                }
                await MainActor.run {
                    let status = self.vpnManager?.connection.status ?? .invalid
                    self.logToUI("VPN status: \(self.statusString(status))")
                    self.vpnStartSwitch.isOn = status == .connected
                    self.vpnStartSwitch.isEnabled = true
                }
                if let manager = self.vpnManager {
                    onExistingManager(manager)
                }
            } catch {
                await MainActor.run {
                    self.vpnStartSwitch.isEnabled = true
                    self.showError(error)
                }
            }
        }
    }
    
    func statusString(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reasserting: return "Reasserting"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
    
    func setupVpn(with manager: NEVPNManager? = nil) {
        if let manager = manager {
            logToUI("Using existing VPN configuration")
            startExistingTunnel(with: manager)
        } else {
            logToUI("Creating new VPN configuration")
            createAndStartTunnel()
        }
    }
    
    func createAndStartTunnel() {
        Task {
            let manager = NETunnelProviderManager()
            manager.localizedDescription = NSLocalizedString("Iodine DNS Tunnel", comment: "Main")
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = tunnelBundleId
            proto.serverAddress = "255.255.255.255"
            manager.protocolConfiguration = proto
            manager.isEnabled = true
            await MainActor.run {
                self.logToUI("Saving VPN configuration...")
            }
            do {
                try await manager.saveToPreferences()
                await MainActor.run {
                    self.logToUI("VPN configuration saved")
                    self.initVpn(onExistingManager: self.startExistingTunnel)
                }
            } catch {
                await MainActor.run {
                    self.showError(error)
                }
            }
        }
    }
    
    func startExistingTunnel(with manager: NEVPNManager) {
        logToUI("Starting VPN tunnel...")
        if manager.connection.status == .connected {
            logToUI("VPN already connected")
            return
        }
        let options = UserDefaults.standard.dictionaryRepresentation().mapValues { value in
            value as! NSObject
        }
        do {
            try manager.connection.startVPNTunnel(options: options)
            logToUI("VPN tunnel start requested")
        } catch NEVPNError.configurationDisabled {
            showError(message: NSLocalizedString("VPN has been disabled in settings or another VPN configuration is selected.", comment: "Main"))
            return
        } catch NEVPNError.configurationInvalid {
            showError(message: NSLocalizedString("VPN configuration is invalid.", comment: "Main"))
            vpnManager = nil
            return
        } catch {
            showError(error)
            return
        }
    }
    
    func stopTunnel(with manager: NEVPNManager) {
        if manager.connection.status == .disconnected {
            return
        }
        
        manager.connection.stopVPNTunnel()
    }
    
    func vpnWillConnect(for manager: NEVPNManager) {
        logToUI("VPN connecting...")
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = true
            self.vpnStartSwitch.isEnabled = false
            self.activityIndicator.startAnimating()
        }
    }
    
    func vpnDidConnect(for manager: NEVPNManager) {
        logToUI("VPN connected successfully!")
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = true
            self.vpnStartSwitch.isEnabled = true
            self.activityIndicator.stopAnimating()
        }
    }
    
    func vpnWillDisconnect(for manager: NEVPNManager) {
        logToUI("VPN disconnecting...")
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = false
            self.vpnStartSwitch.isEnabled = false
            self.activityIndicator.startAnimating()
        }
    }
    
    func vpnDidDisconnect(for manager: NEVPNManager) {
        logToUI("VPN disconnected")
        DispatchQueue.main.async {
            self.vpnStartSwitch.isOn = false
            self.vpnStartSwitch.isEnabled = true
            self.activityIndicator.stopAnimating()
        }
    }
}

extension ViewController {
    private var logUrl: URL? {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return nil
        }
        let groupBundleId = "group." + bundleId
        let containerUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupBundleId)
        return containerUrl?.appendingPathComponent("log.txt")
    }
    
    private func getNewLogLines() -> String? {
        guard let logUrl = logUrl else {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: logUrl) else {
            lastLogIndex = 0
            return nil
        }
        defer {
            handle.closeFile()
        }
        handle.seek(toFileOffset: lastLogIndex)
        let newlines = String(data: handle.readDataToEndOfFile(), encoding: .utf8)
        lastLogIndex = handle.offsetInFile
        return newlines
    }
    
    func clearLog() {
        guard let logUrl = logUrl else {
            return
        }
        try? FileManager.default.removeItem(at: logUrl)
        lastLogIndex = 0
        DispatchQueue.main.async {
            self.logTextView.text = ""
        }
    }
    
    func refreshLog() {
        if let lines = getNewLogLines() {
            print(lines, terminator: "")
            if lines.count > 0 {
                DispatchQueue.main.async {
                    self.logTextView.text += lines
                    self.logTextView.scrollToBottom()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.logTextView.text = ""
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: refreshLog)
    }
}

extension UITextView {
    func scrollToBottom() {
        let textCount: Int = text.count
        guard textCount >= 1 else { return }
        scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
    }
}
