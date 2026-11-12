import AppKit
import ExplorerCore

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("text.about.explorer.babc19a9")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        guard let content = window.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel(L("text.explorer.app.icon.55f599bb"))
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 80), icon.heightAnchor.constraint(equalToConstant: 80)])
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label("Explorer", size: 27, weight: .semibold))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("text.development.21b6a798")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        stack.addArrangedSubview(label(L("text.version.argument.69ea5a45", version) + (build.map { " (\($0))" } ?? ""), size: 12, secondary: true))
        let description = label(L("text.a.native.mac.file.manager.inspired.by.windows.explorer.familiar.bb8bfd7d"), size: 14)
        description.maximumNumberOfLines = 0
        description.preferredMaxLayoutWidth = 370
        stack.addArrangedSubview(description)
        stack.setCustomSpacing(20, after: description)

        let publisher = NSButton(title: L("text.developed.by.binary.quest.f15c0ca9"), target: self, action: #selector(openPublisher))
        publisher.bezelStyle = .inline
        publisher.font = .systemFont(ofSize: 13, weight: .medium)
        publisher.toolTip = "www.binaryquest.com"
        stack.addArrangedSubview(publisher)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        for (title, action) in [(L("text.website.b5a229ac"), #selector(openWebsite)), (L("text.source.code.bc47da66"), #selector(openSource))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons)
        stack.setCustomSpacing(20, after: buttons)
        stack.addArrangedSubview(label(L("text.free.and.open.source.mit.license.1d282604"), size: 11, secondary: true))
        stack.addArrangedSubview(label("© Binary Quest Software Pty Ltd", size: 11, secondary: true))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.alignment = .center
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.isSelectable = true
        return field
    }

    @objc private func openWebsite() { open("https://explorer.bquick.io") }
    @objc private func openSource() { open("https://github.com/binaryquest/MacExplorer") }
    @objc private func openPublisher() { open("https://www.binaryquest.com") }
    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
