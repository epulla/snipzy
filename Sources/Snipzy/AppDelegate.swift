import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyMonitor: CarbonHotKeyMonitor?
    private var editors: [EditorWindowController] = []
    private var captureInProgress = false
    private let captureService = CaptureService()
    private let pasteboard = SystemPasteboard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snipzy")
        statusItem.button?.toolTip = "Snipzy: Cmd-Shift-4 to capture"
        statusItem.menu = makeMenu()
        showShortcutHintIfNeeded()

        let monitor = CarbonHotKeyMonitor { [weak self] in
            self?.capture()
        }
        hotKeyMonitor = monitor
        do {
            try monitor.start()
        } catch {
            showError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let captureItem = menu.addItem(withTitle: "Capture Selection", action: #selector(capture), keyEquivalent: "4")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(withTitle: "Open Desktop", action: #selector(openDesktop), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snipzy", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func capture() {
        guard !captureInProgress else { return }
        captureInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [captureService] in
            let result = Result { try captureService.capture() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureInProgress = false
                switch result {
                case let .success(captured):
                    guard self.pasteboard.write(pngData: captured.pngData, tiffData: captured.tiffData) else {
                        self.showError(AppError.clipboardWriteFailed)
                        return
                    }
                    let controller = EditorWindowController(image: captured.image, pasteboard: self.pasteboard)
                    controller.onClose = { [weak self, weak controller] closedController in
                        guard let controller else { return }
                        self?.editors.removeAll { $0 === controller && $0 === closedController }
                        if self?.editors.isEmpty == true { NSApp.setActivationPolicy(.accessory) }
                    }
                    self.editors.append(controller)
                    NSApp.setActivationPolicy(.regular)
                    controller.showWindow(self)
                    // Ignore frontmost app so AppKit enables tooltips and cursor rects.
                    DispatchQueue.main.async { [weak controller] in
                        NSApp.activate(ignoringOtherApps: true)
                        controller?.window?.makeKeyAndOrderFront(nil)
                    }
                case let .failure(error):
                    if let captureError = error as? CaptureError, case .cancelled = captureError {
                        break
                    }
                    self.showError(error)
                }
            }
        }
    }

    @objc private func openDesktop() {
        NSWorkspace.shared.open(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func showShortcutHintIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didShowShortcutHint") else { return }
        defaults.set(true, forKey: "didShowShortcutHint")
        let alert = NSAlert()
        alert.messageText = "Enable Snipzy shortcut"
        alert.informativeText = "Disable macOS's built-in screenshot shortcut in System Settings > Keyboard > Keyboard Shortcuts > Screenshots, then use Cmd-Shift-4 for Snipzy."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum AppError: LocalizedError {
    case clipboardWriteFailed
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .clipboardWriteFailed: return "Could not copy screenshot to clipboard"
        case .imageEncodingFailed: return "Could not encode annotated screenshot"
        }
    }
}

@main
struct SnipzyApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
