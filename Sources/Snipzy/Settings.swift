import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    static let autoCopyKey = "autoCopyAfterEdit"
    private let defaults: UserDefaults
    let autoCopyCheckbox = NSButton(checkboxWithTitle: "Copy image to clipboard after each edit", target: nil, action: nil)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 90), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Snipzy Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        autoCopyCheckbox.target = self
        autoCopyCheckbox.action = #selector(toggleAutoCopy(_:))
        autoCopyCheckbox.state = defaults.bool(forKey: Self.autoCopyKey) ? .on : .off
        let note = NSTextField(wrappingLabelWithString: "Applies to the editor window. Draw mode copies when you press Enter.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 340
        let stack = NSStackView(views: [autoCopyCheckbox, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggleAutoCopy(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: Self.autoCopyKey)
    }
}
