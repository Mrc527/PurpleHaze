import UIKit

/// Shared PurpleHaze colors and native, accessible building blocks.
enum Brand {
    static let purple = UIColor(red: 115/255, green: 25/255, blue: 99/255, alpha: 1)
    static let ink = UIColor(red: 37/255, green: 22/255, blue: 46/255, alpha: 1)
    static let muted = UIColor(red: 110/255, green: 94/255, blue: 118/255, alpha: 1)
    static let canvas = UIColor(red: 250/255, green: 245/255, blue: 253/255, alpha: 1)
    static let lavender = UIColor(red: 228/255, green: 193/255, blue: 249/255, alpha: 1)
    static func label(_ text: String, _ style: UIFont.TextStyle = .body, color: UIColor = ink) -> UILabel {
        let label = UILabel(); label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: style); label.adjustsFontForContentSizeCategory = true; label.textColor = color
        return label
    }
    static func stack(spacing: CGFloat = 12) -> UIStackView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = spacing; return stack
    }
    static func content(in controller: UIViewController) -> UIStackView {
        controller.view.backgroundColor = canvas
        let scroll = UIScrollView(); scroll.keyboardDismissMode = .interactive; scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        let content = stack(spacing: 18); content.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.keyboardLayoutGuide.topAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        return content
    }
    static func card(in parent: UIStackView) -> UIStackView {
        let card = stack(); card.backgroundColor = .white; card.layer.cornerRadius = 18
        card.isLayoutMarginsRelativeArrangement = true; card.directionalLayoutMargins = .init(top: 18, leading: 18, bottom: 18, trailing: 18)
        parent.addArrangedSubview(card); return card
    }
    static func button(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = primary ? UIButton.Configuration.filled() : .tinted()
        config.title = title; config.baseBackgroundColor = purple; config.baseForegroundColor = primary ? .white : purple
        config.cornerStyle = .medium; config.contentInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() }); return button
    }
    static func error(_ error: Error, on controller: UIViewController) {
        let alert = UIAlertController(title: "Unable to continue", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); controller.present(alert, animated: true)
    }
    static func failure(_ message: String) -> Error { NSError(domain: "PurpleHaze", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
