import UIKit

@MainActor
final class ProfileEditor: UIViewController {
    private let store: ProfileStore
    private var profile: ConnectionProfile
    private let isNew: Bool
    private let saved: () -> Void
    private let canEdit: () -> Bool
    private var fields: [String: UITextField] = [:]
    private var toggles: [String: UISwitch] = [:]
    private var selections: [String: String] = [:]
    private let security = UISegmentedControl(items: ["Encrypted", "Legacy"])
    private let dnsMode = UISegmentedControl(items: ["System", "Tunnel", "Custom"])
    private var keyRow: UIStackView!, passwordRow: UIStackView!, dnsRow: UIStackView!
    private var canSave = true

    init(store: ProfileStore, profile: ConnectionProfile?, canEdit: @escaping () -> Bool, saved: @escaping () -> Void) {
        self.canEdit = canEdit; self.store = store; self.profile = profile ?? ConnectionProfile(); self.isNew = profile == nil; self.saved = saved
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use programmatic initializer") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = isNew ? "New profile" : "Edit profile"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        var key = "", password = ""
        if !isNew {
            do { let secrets = try store.secrets(for: profile); key = secrets.keyBase64; password = secrets.password }
            catch { DispatchQueue.main.async { Brand.error(Brand.failure("Stored credentials are unavailable. Re-enter the credentials for this profile before saving.\n\n" + error.localizedDescription), on: self) } }
        }
        let body = Brand.content(in: self)
        body.superview?.accessibilityIdentifier = "profile.editor.scroll"
        security.accessibilityIdentifier = "profile.security"; dnsMode.accessibilityIdentifier = "profile.dnsMode"
        let general = section(body, "Profile")
        field(general, "name", "Name", profile.name, placeholder: "Home server")
        field(general, "domain", "Top domain", profile.topDomain, placeholder: "tunnel.example.com")
        let credentials = section(body, "Security", "Credentials are stored separately for each profile in Keychain.")
        security.selectedSegmentIndex = profile.encrypted ? 0 : 1; credentials.addArrangedSubview(security)
        security.addTarget(self, action: #selector(securityChanged), for: .valueChanged)
        keyRow = field(credentials, "key", "Shared key · Base64", key, placeholder: "Server key", secret: true)
        passwordRow = field(credentials, "password", "Legacy password", password, placeholder: "Unencrypted connection", secret: true)
        toggle(credentials, "proxy", "Server proxy · TCP / UDP / DNS", profile.serverProxy)
        credentials.addArrangedSubview(Brand.label("Server proxy requires encryption and routes IPv4 app traffic through your server. IPv6 traffic is blocked.", .footnote, color: Brand.muted))
        let network = section(body, "Routing & DNS")
        toggle(network, "route", "Route all IPv4 traffic", profile.defaultRoute)
        network.addArrangedSubview(Brand.label("Always enabled while Server proxy is on.", .footnote, color: Brand.muted))
        network.addArrangedSubview(Brand.label("DNS inside the tunnel", .subheadline, color: Brand.muted))
        dnsMode.selectedSegmentIndex = ["system", "tunnel", "custom"].firstIndex(of: profile.dnsMode) ?? 2
        dnsMode.addTarget(self, action: #selector(dnsChanged), for: .valueChanged); network.addArrangedSubview(dnsMode)
        dnsRow = field(network, "dns", "Custom DNS", profile.dnsServer, placeholder: "1.1.1.1")
        let transport = section(body, "Transport", "These settings control how the DNS tunnel reaches your server.")
        field(transport, "resolver", "Tunnel nameserver", profile.nameserverHost, placeholder: "Automatic")
        toggle(transport, "ipv6", "Allow IPv6 tunnel nameservers", profile.ipv6Support)
        toggle(transport, "raw", "Try direct UDP", profile.rawMode)
        toggle(transport, "lazy", "Lazy mode", profile.lazyMode)
        choice(transport, "type", "DNS query type", profile.forceDnsType, choices: ["", "NULL", "PRIVATE", "TXT", "SRV", "MX", "CNAME", "A"])
        choice(transport, "encoding", "Downstream encoding", profile.forceEncoding, choices: ["", "base32", "base64", "base64u", "base128", "raw"])
        field(transport, "timeout", "Request timeout · seconds", String(profile.selectTimeout), number: true)
        field(transport, "hostname", "Maximum hostname length", String(profile.hostnameMaxLength), number: true)
        field(transport, "fragment", "Downstream fragment size · 0 = automatic", String(profile.maxDownstreamFragmentSize), number: true)
        let saveButton = Brand.button("Save profile", primary: true) { [weak self] in self?.save() }; saveButton.isEnabled = canSave; body.addArrangedSubview(saveButton)
        if !isNew { body.addArrangedSubview(Brand.button("Delete profile") { [weak self] in self?.deleteProfile() }) }
        navigationItem.rightBarButtonItem?.isEnabled = canSave
        securityChanged(); dnsChanged()
    }
    private func section(_ parent: UIStackView, _ name: String, _ detail: String? = nil) -> UIStackView {
        let card = Brand.card(in: parent); card.addArrangedSubview(Brand.label(name, .title3)); if let detail { card.addArrangedSubview(Brand.label(detail, .footnote, color: Brand.muted)) }; return card
    }
    @discardableResult private func field(_ parent: UIStackView, _ key: String, _ title: String, _ value: String, placeholder: String = "", secret: Bool = false, number: Bool = false) -> UIStackView {
        let row = Brand.stack(spacing: 6); row.addArrangedSubview(Brand.label(title, .subheadline, color: Brand.muted))
        let text = UITextField(); text.accessibilityIdentifier = "profile.\(key)"; text.text = value; text.placeholder = placeholder; text.borderStyle = .roundedRect
        text.font = .preferredFont(forTextStyle: .body); text.adjustsFontForContentSizeCategory = true; text.textColor = Brand.ink
        text.autocapitalizationType = .none; text.autocorrectionType = .no; text.spellCheckingType = .no; text.isSecureTextEntry = secret
        text.keyboardType = number ? .numberPad : .asciiCapable; text.textContentType = key == "password" ? .password : nil
        text.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; fields[key] = text; row.addArrangedSubview(text); parent.addArrangedSubview(row); return row
    }
    private func toggle(_ parent: UIStackView, _ key: String, _ title: String, _ value: Bool) {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 12; row.alignment = .center
        let label = Brand.label(title); let toggle = UISwitch(); toggle.isOn = value; toggle.onTintColor = Brand.purple; toggle.accessibilityLabel = title; toggle.accessibilityIdentifier = "profile.\(key)"
        row.addArrangedSubview(label); row.addArrangedSubview(toggle); row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        toggles[key] = toggle; parent.addArrangedSubview(row)
    }
    private func choice(_ parent: UIStackView, _ key: String, _ title: String, _ value: String, choices: [String]) {
        parent.addArrangedSubview(Brand.label(title, .subheadline, color: Brand.muted)); selections[key] = value
        let button = UIButton(type: .system); button.contentHorizontalAlignment = .leading; button.tintColor = Brand.purple
        button.setTitle(value.isEmpty ? "Automatic" : value, for: .normal); button.showsMenuAsPrimaryAction = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.menu = UIMenu(children: choices.map { option in UIAction(title: option.isEmpty ? "Automatic" : option) { [weak self, weak button] _ in self?.selections[key] = option; button?.setTitle(option.isEmpty ? "Automatic" : option, for: .normal) } })
        parent.addArrangedSubview(button)
    }
    @objc private func securityChanged() {
        let encrypted = security.selectedSegmentIndex == 0
        keyRow.isHidden = !encrypted; passwordRow.isHidden = encrypted; toggles["proxy"]?.isEnabled = encrypted
        if !encrypted { toggles["proxy"]?.isOn = false }
    }
    @objc private func dnsChanged() { dnsRow.isHidden = dnsMode.selectedSegmentIndex != 2 }
    private func text(_ key: String) -> String { (fields[key]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private func number(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
        guard let value = Int(text(key)), range.contains(value) else { throw Brand.failure("\(key) must be between \(range.lowerBound) and \(range.upperBound).") }; return value
    }
    @objc private func save() {
        guard canSave else { return }
        guard canEdit() else { Brand.error(Brand.failure("Disconnect before changing a profile."), on: self); return }
        do {
            profile.name = text("name"); profile.topDomain = text("domain"); profile.encrypted = security.selectedSegmentIndex == 0
            profile.serverProxy = toggles["proxy"]!.isOn; profile.defaultRoute = toggles["route"]!.isOn
            profile.dnsMode = ["system", "tunnel", "custom"][dnsMode.selectedSegmentIndex]; profile.dnsServer = text("dns"); profile.nameserverHost = text("resolver")
            profile.ipv6Support = toggles["ipv6"]!.isOn; profile.rawMode = toggles["raw"]!.isOn; profile.lazyMode = toggles["lazy"]!.isOn
            profile.forceDnsType = selections["type"] ?? ""; profile.forceEncoding = selections["encoding"] ?? ""
            profile.selectTimeout = try number("timeout", 1...60); profile.hostnameMaxLength = try number("hostname", 100...255); profile.maxDownstreamFragmentSize = try number("fragment", 0...65535)
            try store.save(profile, keyBase64: profile.encrypted ? text("key") : "", password: profile.encrypted ? "" : fields["password"]?.text ?? "")
            dismiss(animated: true, completion: saved)
        } catch { Brand.error(error, on: self) }
    }
    @objc private func cancel() {
        let alert = UIAlertController(title: "Discard changes?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel)); alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in self?.dismiss(animated: true) }); present(alert, animated: true)
    }
    private func deleteProfile() {
        let alert = UIAlertController(title: "Delete \(profile.name)?", message: "This removes the profile and its stored credentials.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }; do { guard self.canEdit() else { throw Brand.failure("Disconnect before deleting a profile.") }; try self.store.delete(self.profile.id); self.dismiss(animated: true, completion: self.saved) } catch { Brand.error(error, on: self) }
        }); present(alert, animated: true)
    }
}
