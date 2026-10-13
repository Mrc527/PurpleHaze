// Copyright © 2021 osy. Licensed under the Apache License, Version 2.0.
import UIKit
import NetworkExtension

@MainActor
final class ViewController: UIViewController {
    private var store: ProfileStore?
    private var manager: NETunnelProviderManager?
    private var working = true
    private var content: UIStackView!
    private var observers: [NSObjectProtocol] = []
    private var tunnelBundleID: String { Bundle.main.bundleIdentifier! + ".Iodine" }
    private var busy: Bool {
        working || [.connecting, .connected, .reasserting, .disconnecting].contains(manager?.connection.status ?? .invalid)
    }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "PurpleHaze"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "About", style: .plain, target: self, action: #selector(about))
        content = Brand.content(in: self)
        do { store = try ProfileStore() } catch { DispatchQueue.main.async { Brand.error(error, on: self) } }
        observers.append(NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.render(); self?.reconcileManager() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.render(); self?.reconcileManager() }
        })
        render()
        Task {
            do {
                manager = try await NETunnelProviderManager.loadAllFromPreferences().first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleID }
            } catch { Brand.error(error, on: self) }
            working = false; render(); reconcileManager()
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    private func render() {
        guard content != nil else { return }
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let header = UIStackView(); header.spacing = 14; header.alignment = .center
        let icon = UIImageView(image: UIImage(named: "BrandMark")); icon.contentMode = .scaleAspectFit; icon.layer.cornerRadius = 16; icon.clipsToBounds = true
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 64), icon.heightAnchor.constraint(equalToConstant: 64)])
        header.addArrangedSubview(icon); header.addArrangedSubview(Brand.label("Your connection,\nthrough DNS.", .title2)); content.addArrangedSubview(header)
        let status = manager?.connection.status ?? .disconnected
        let connected = [.connected, .connecting, .reasserting, .disconnecting].contains(status)
        let activeID = (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?[IodineSettings.profileID] as? String
        let selected = store?.selectedProfile
        let displayed = connected ? store?.profiles.first(where: { $0.id == activeID }) : selected
        let card = Brand.card(in: content)
        let statusText: String
        switch status {
        case .connected: statusText = "Connected"
        case .connecting: statusText = "Connecting…"
        case .reasserting: statusText = "Reconnecting…"
        case .disconnecting: statusText = "Disconnecting…"
        default: statusText = working ? "Preparing…" : "Disconnected"
        }
        card.addArrangedSubview(Brand.label(statusText, .title2, color: Brand.purple))
        card.addArrangedSubview(Brand.label(displayed?.name ?? (connected ? "Previous configuration" : "Choose a profile to begin"), .headline))
        if let profile = displayed {
            card.addArrangedSubview(Brand.label(profile.topDomain, .subheadline, color: Brand.muted))
            card.addArrangedSubview(Brand.label((profile.encrypted ? "Encrypted" : "Legacy · unencrypted") + (profile.serverProxy ? "  •  Server proxy" : ""), .footnote, color: Brand.muted))
        }
        let connect = Brand.button(connected ? "Disconnect" : "Connect", primary: true) { [weak self] in self?.toggleConnection() }
        connect.isEnabled = !working && status != .disconnecting && (connected || selected != nil)
        card.addArrangedSubview(connect)
        content.addArrangedSubview(Brand.label("Profiles", .title2))
        if store == nil { content.addArrangedSubview(Brand.label("Profiles could not be loaded. Existing data has been preserved.", .body)) }
        else if store!.profiles.isEmpty { content.addArrangedSubview(Brand.label("Add a server and save its connection settings in a profile.", .body, color: Brand.muted)) }
        for profile in store?.profiles ?? [] {
            let row = Brand.card(in: content)
            row.addArrangedSubview(Brand.label((profile.id == selected?.id ? "✓  " : "") + profile.name, .headline))
            row.addArrangedSubview(Brand.label(profile.topDomain, .subheadline, color: Brand.muted))
            row.addArrangedSubview(Brand.label((profile.encrypted ? "Encrypted" : "Legacy") + (profile.serverProxy ? " • Proxy" : ""), .footnote, color: Brand.muted))
            let actions = UIStackView(); actions.spacing = 10; actions.distribution = .fillEqually
            let select = Brand.button(profile.id == selected?.id ? "Selected" : "Select") { [weak self] in self?.select(profile.id) }
            let edit = Brand.button("Edit") { [weak self] in self?.edit(profile) }
            select.accessibilityIdentifier = "profile.select.\(profile.name)"; edit.accessibilityIdentifier = "profile.edit.\(profile.name)"
            select.isEnabled = !busy && profile.id != selected?.id; edit.isEnabled = !busy
            actions.addArrangedSubview(select); actions.addArrangedSubview(edit); row.addArrangedSubview(actions)
        }
        let add = Brand.button("New profile") { [weak self] in self?.edit(nil) }; add.accessibilityIdentifier = "profile.new"; add.isEnabled = !busy && store != nil; content.addArrangedSubview(add)
        if connected { content.addArrangedSubview(Brand.label("Disconnect before changing profiles or connection settings.", .footnote, color: Brand.muted)) }
        content.addArrangedSubview(Brand.button("Connection log") { [weak self] in self?.showLog() })
    }
    private func select(_ id: String) {
        guard !busy, let store else { return }
        do { try store.select(id); profilesChanged() } catch { Brand.error(error, on: self) }
    }
    private func edit(_ profile: ConnectionProfile?) {
        guard !busy, let store else { return }
        let editor = ProfileEditor(store: store, profile: profile, canEdit: { [weak self] in self?.busy == false }) { [weak self] in self?.profilesChanged() }
        let navigation = UINavigationController(rootViewController: editor); navigation.isModalInPresentation = true
        present(navigation, animated: true)
    }
    private func reconcileManager() {
        guard !busy, let manager else { return }
        let snapshot = (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        if let profile = store?.selectedProfile {
            if snapshot[IodineSettings.profileID] as? String != profile.id || snapshot[IodineSettings.credentialRevision] as? String != profile.credentialRevision { profilesChanged() }
        } else if store != nil { profilesChanged() }
    }
    private func profilesChanged() {
        render()
        guard !busy, let manager else { return }
        working = true; render()
        Task {
            do {
                if let profile = store?.selectedProfile {
                    configure(manager, profile: profile)
                    try await manager.saveToPreferences(); try await manager.loadFromPreferences()
                } else { try await manager.removeFromPreferences(); self.manager = nil }
            } catch { Brand.error(error, on: self) }
            working = false; render()
        }
    }
    private func configure(_ manager: NETunnelProviderManager, profile: ConnectionProfile) {
        let config = NETunnelProviderProtocol(); config.providerBundleIdentifier = tunnelBundleID
        config.serverAddress = profile.topDomain; config.providerConfiguration = profile.options
        manager.protocolConfiguration = config; manager.localizedDescription = "PurpleHaze — " + profile.name; manager.isEnabled = true
    }
    private func toggleConnection() {
        guard !working else { return }
        if busy { manager?.connection.stopVPNTunnel(); render(); return }
        guard let store, let profile = store.selectedProfile else { return }
        do { try profile.validate(); _ = try store.secrets(for: profile) } catch { Brand.error(error, on: self); return }
        working = true; render()
        Task {
            do {
                let manager = self.manager ?? NETunnelProviderManager(); self.manager = manager
                configure(manager, profile: profile)
                try await manager.saveToPreferences(); try await manager.loadFromPreferences()
                guard let connection = manager.connection as? NETunnelProviderSession else { throw Brand.failure("VPN session is unavailable.") }
                try connection.startVPNTunnel(options: profile.options)
            } catch { Brand.error(error, on: self) }
            working = false; render()
        }
    }
    private func showLog() { present(UINavigationController(rootViewController: ConnectionLogController()), animated: true) }
    @objc private func about() {
        let alert = UIAlertController(title: "PurpleHaze", message: "A DNS tunnel client for your iodine server.\n\nBased on PurpleHaze by osy and DullJZ. Android edition based on AndIodine by xapek.\n\nPurpleHaze: Apache 2.0\niodine: ISC\nOpenSSL: Apache 2.0\nhev-socks5-tunnel: MIT", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
}

@MainActor
private final class ConnectionLogController: UIViewController {
    private let text = UITextView()
    private var timer: Timer?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Connection log"; view.backgroundColor = Brand.canvas
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))
        text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.backgroundColor = Brand.canvas; text.textColor = Brand.ink
        text.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(text)
        NSLayoutConstraint.activate([text.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); timer?.invalidate(); timer = nil }
    private func refresh() {
        guard let identifier = Bundle.main.bundleIdentifier,
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + identifier)?.appendingPathComponent("log.txt"),
              let handle = try? FileHandle(forReadingFrom: url) else { text.text = "No connection log yet."; return }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd(); try handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
            let data = try handle.readToEnd() ?? Data(); let value = String(decoding: data, as: UTF8.self)
            if text.text != value { text.text = value; if !value.isEmpty { text.scrollRangeToVisible(NSRange(location: text.text.utf16.count - 1, length: 1)) } }
        } catch { text.text = "The connection log is unavailable." }
    }
    @objc private func done() { dismiss(animated: true) }
}
