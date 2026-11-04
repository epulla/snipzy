import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var recentItem: NSMenuItem!
    private var hotKeyMonitors: [CarbonHotKeyMonitor] = []
    private var editors: [EditorWindowController] = []
    private var captureInProgress = false
    private let captureService = CaptureService()
    private let pasteboard = SystemPasteboard()
    private let history = CaptureHistory()
    private lazy var settings = SettingsWindowController(history: history)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Snipzy")
        statusItem.button?.toolTip = "Snipzy: Cmd-Shift-4 to capture, Cmd-Shift-6 to draw on screen"
        statusItem.menu = makeMenu()
        showShortcutHintIfNeeded()
        SettingsWindowController.applyLaunchAtLoginDefault()

        hotKeyMonitors = [
            CarbonHotKeyMonitor(keyCode: kVK_ANSI_4, id: 1) { [weak self] in self?.capture() },
            CarbonHotKeyMonitor(keyCode: kVK_ANSI_6, id: 2) { [weak self] in self?.drawOnScreen() }
        ]
        for monitor in hotKeyMonitors {
            do {
                try monitor.start()
            } catch {
                showError(error)
            }
        }
    }

    static func makeMainMenu() -> NSMenu {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Snipzy")
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
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
        hotKeyMonitors.forEach { $0.stop() }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let captureItem = menu.addItem(withTitle: "Capture Selection", action: #selector(capture), keyEquivalent: "4")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        let drawItem = menu.addItem(withTitle: "Draw on Screen", action: #selector(drawOnScreen), keyEquivalent: "6")
        drawItem.keyEquivalentModifierMask = [.command, .shift]
        recentItem = menu.addItem(withTitle: "Recent", action: nil, keyEquivalent: "")
        let desktopItem = menu.addItem(withTitle: "Open Desktop", action: #selector(openDesktop), keyEquivalent: "")
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Snipzy", action: #selector(quit), keyEquivalent: "q")
        let symbols = [(captureItem, "viewfinder"), (drawItem, "pencil.tip.crop.circle"), (recentItem!, "clock.arrow.circlepath"), (desktopItem, "menubar.dock.rectangle"), (settingsItem, "gearshape"), (quitItem, "power")]
        for (item, symbol) in symbols { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        return menu
    }

    // No submenu and no action leaves Recent disabled while history is empty.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let entries = history.entries()
        guard !entries.isEmpty else {
            recentItem.submenu = nil
            return
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        let submenu = NSMenu()
        for entry in entries {
            let item = submenu.addItem(withTitle: formatter.string(from: entry.date), action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = entry.id
            item.image = Self.thumbnail(at: entry.url)
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        submenu.items.forEach { $0.target = self }
        recentItem.submenu = submenu
    }

    private static func thumbnail(at url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(64 / image.size.width, 40 / image.size.height, 1)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return image
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let entry = history.entries().first(where: { $0.id == id }),
              let image = NSImage(contentsOf: entry.url) else { return }
        let controller = EditorWindowController(image: image, pasteboard: pasteboard)
        controller.historyID = id
        showEditor(controller)
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func capture() {
        guard !captureInProgress else { return }
        captureInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [captureService] in
            let result = Result { try captureService.capture() }
            DispatchQueue.main.async { [weak self] in
                self?.finishCapture(result)
            }
        }
    }

    @objc private func drawOnScreen() {
        guard !captureInProgress, !editors.contains(where: \.isDrawMode) else { return }
        captureInProgress = true
        Task { @MainActor in
            let snapshot = await DisplayUnderMouse.snapshot()
            captureInProgress = false
            guard let snapshot else {
                showError(AppError.screenSnapshotFailed)
                return
            }
            let overlay = EditorWindowController(image: snapshot.image, pasteboard: pasteboard, drawOn: snapshot.frame)
            overlay.onOpenInEditor = { [weak self, weak overlay] image, annotations in
                guard let self else { return }
                let editor = EditorWindowController(image: image, annotations: annotations, pasteboard: pasteboard)
                editor.historyID = overlay?.historyID
                showEditor(editor)
            }
            showEditor(overlay)
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
            let editor = EditorWindowController(image: captured.image, pasteboard: pasteboard)
            editor.historyID = history.add(captured.pngData)
            showEditor(editor)
        case let .failure(error):
            if let captureError = error as? CaptureError, case .cancelled = captureError { return }
            showError(error)
        }
    }

    /// Editors a new capture replaces: unannotated editor windows; draw mode and annotated ones stay.
    static func staleEditors(_ editors: [EditorWindowController]) -> [EditorWindowController] {
        editors.filter { !$0.isDrawMode && !$0.hasAnnotations }
    }

    private func showEditor(_ controller: EditorWindowController) {
        if !controller.isDrawMode { Self.staleEditors(editors).forEach { $0.close() } }
        controller.onRendered = { [weak self, weak controller] png in
            guard let self, let controller else { return }
            if let id = controller.historyID {
                history.replace(id: id, with: png)
            } else {
                controller.historyID = history.add(png)
            }
        }
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

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.showWindow(nil)
        settings.window?.makeKeyAndOrderFront(nil)
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
    case screenSnapshotFailed

    var errorDescription: String? {
        switch self {
        case .clipboardWriteFailed: return "Could not copy screenshot to clipboard"
        case .imageEncodingFailed: return "Could not encode annotated screenshot"
        case .screenSnapshotFailed: return "Could not capture the screen. Check Screen Recording permission for Snipzy."
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
