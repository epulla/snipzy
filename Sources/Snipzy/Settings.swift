import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    static let autoCopyKey = "autoCopyAfterEdit"
    static let loginDefaultAppliedKey = "launchAtLoginDefaultApplied"

    /// Launch at login defaults to on: register once on first run, then respect the user's choice.
    static func applyLaunchAtLoginDefault(defaults: UserDefaults = .standard, register: () throws -> Void = { try SMAppService.mainApp.register() }) {
        guard !defaults.bool(forKey: loginDefaultAppliedKey) else { return }
        defaults.set(true, forKey: loginDefaultAppliedKey)
        try? register()
    }
    private let defaults: UserDefaults
    private let history: CaptureHistory
    let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    let autoCopyCheckbox = NSButton(checkboxWithTitle: "Copy image to clipboard after each edit", target: nil, action: nil)
    let historyLimitField = NSTextField()
    let historyLimitStepper = NSStepper()

    init(defaults: UserDefaults = .standard, history: CaptureHistory) {
        self.defaults = defaults
        self.history = history
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 90), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Snipzy Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        refreshLoginState()
        autoCopyCheckbox.target = self
        autoCopyCheckbox.action = #selector(toggleAutoCopy(_:))
        autoCopyCheckbox.state = defaults.bool(forKey: Self.autoCopyKey) ? .on : .off
        let note = NSTextField(wrappingLabelWithString: "Applies to the editor window. Draw mode copies when you press Enter.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 340
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: CaptureHistory.limitRange.lowerBound)
        formatter.maximum = NSNumber(value: CaptureHistory.limitRange.upperBound)
        formatter.allowsFloats = false
        historyLimitField.formatter = formatter
        historyLimitField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        historyLimitField.target = self
        historyLimitField.action = #selector(changeHistoryLimit(_:))
        historyLimitStepper.minValue = Double(CaptureHistory.limitRange.lowerBound)
        historyLimitStepper.maxValue = Double(CaptureHistory.limitRange.upperBound)
        historyLimitStepper.target = self
        historyLimitStepper.action = #selector(changeHistoryLimit(_:))
        historyLimitField.integerValue = history.limit
        historyLimitStepper.integerValue = history.limit
        let historyRow = NSStackView(views: [NSTextField(labelWithString: "Keep last"), historyLimitField, historyLimitStepper, NSTextField(labelWithString: "captures in Recent")])
        historyRow.spacing = 6
        let stack = NSStackView(views: [loginCheckbox, autoCopyCheckbox, note, historyRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: loginCheckbox)
        stack.setCustomSpacing(12, after: note)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        // Login items can be changed in System Settings while Snipzy runs.
        refreshLoginState()
        super.showWindow(sender)
    }

    private func refreshLoginState() {
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        do {
            if loginCheckbox.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
            refreshLoginState()
        }
    }

    @objc private func toggleAutoCopy(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: Self.autoCopyKey)
    }

    @objc private func changeHistoryLimit(_ sender: NSControl) {
        history.setLimit(sender.integerValue)
        historyLimitField.integerValue = history.limit
        historyLimitStepper.integerValue = history.limit
    }
}
