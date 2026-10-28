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
        NSApp.mainMenu = Self.makeMainMenu()
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

    static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Snipzy")
        let quit = appMenu.addItem(withTitle: "Quit Snipzy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(withTitle: "Snipzy", action: nil, keyEquivalent: "").submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = NSEvent.ModifierFlags.command.union(.shift)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu
        return menu
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
        let frame = DisplayUnderMouse.frame
        let rect = frame.map { DisplayUnderMouse.captureRect(for: $0, primaryMaxY: DisplayUnderMouse.primaryMaxY) }
        DispatchQueue.global(qos: .userInitiated).async { [captureService] in
            // Without a snapshot (e.g. no Screen Recording permission) selection runs on the live screen.
            let snapshot = rect.flatMap { try? captureService.captureDisplay(rect: $0) }
            DispatchQueue.main.async {
                var overlay: FreezeOverlay?
                if let snapshot, let frame { overlay = FreezeOverlay(image: snapshot.image, frame: frame) }
                overlay?.show()
                DispatchQueue.global(qos: .userInitiated).async { [overlay] in
                    let result = Result { try captureService.capture() }
                    DispatchQueue.main.async { [weak self] in
                        overlay?.close()
                        self?.finishCapture(result)
                    }
                }
            }
        }
    }

    private func finishCapture(_ result: Result<CapturedImage, Error>) {
        captureInProgress = false
        switch result {
        case let .success(captured):
            guard pasteboard.write(pngData: captured.pngData, tiffData: captured.tiffData) else {
                showError(AppError.clipboardWriteFailed)
                return
            }
            showEditor(EditorWindowController(image: captured.image, pasteboard: pasteboard))
        case let .failure(error):
            if let captureError = error as? CaptureError, case .cancelled = captureError { return }
            showError(error)
        }
    }

    private func showEditor(_ controller: EditorWindowController) {
        controller.onClose = { [weak self, weak controller] closedController in
            guard let controller else { return }
            self?.editors.removeAll { $0 === controller && $0 === closedController }
            if self?.editors.isEmpty == true { NSApp.setActivationPolicy(.accessory) }
        }
        editors.append(controller)
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(self)
        // Ignore frontmost app so AppKit enables tooltips and cursor rects.
        DispatchQueue.main.async { [weak controller] in
            NSApp.activate(ignoringOtherApps: true)
            controller?.window?.makeKeyAndOrderFront(nil)
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
