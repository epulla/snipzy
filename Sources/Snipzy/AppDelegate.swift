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
    private lazy var session = HistorySession(history: history)
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
        let submenu = NSMenu()
        for entry in entries {
            let item = submenu.addItem(withTitle: entry.title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = entry.id
            item.image = entry.thumbnail(fitting: NSSize(width: 64, height: 40))
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        submenu.items.forEach { $0.target = self }
        recentItem.submenu = submenu
    }

    // Reuses the newest regular editor so Recent swaps in place like the editor's own history panel.
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let editor = editors.last(where: { !$0.isDrawMode }) {
            editor.showEntry(id)
            bringToFront(editor)
            return
        }
        guard let state = session.state(for: id) else { return }
        let controller = EditorWindowController(image: state.image, annotations: state.annotations, pasteboard: pasteboard, session: session)
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
            overlay.onOpenInEditor = { [weak self] image, annotations, historyID in
                guard let self else { return }
                if let historyID { session.store(historyID, image: image, annotations: annotations) }
                let editor = EditorWindowController(image: image, annotations: annotations, pasteboard: pasteboard, session: session)
                editor.historyID = historyID
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
            let editor = EditorWindowController(image: captured.image, pasteboard: pasteboard, session: session)
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

    /// Keeps the editor's history entry in sync with its latest rendered PNG; adds one on first render if needed.
    static func trackHistory(_ controller: EditorWindowController, in history: CaptureHistory) {
        controller.onRendered = { [weak controller] png in
            guard let controller else { return }
            if let id = controller.historyID {
                history.replace(id: id, with: png)
            } else {
                controller.historyID = history.add(png)
            }
        }
    }

    private func showEditor(_ controller: EditorWindowController) {
        let stale = controller.isDrawMode ? [] : Self.staleEditors(editors)
        Self.trackHistory(controller, in: history)
        controller.onClose = { [weak self, weak controller] closedController in
            guard let controller else { return }
            self?.editors.removeAll { $0 === controller && $0 === closedController }
            if self?.editors.isEmpty == true { NSApp.setActivationPolicy(.accessory) }
        }
        // Append before closing stale editors so the app never drops to .accessory in between.
        editors.append(controller)
        stale.forEach { $0.close() }
        bringToFront(controller)
    }

    private func bringToFront(_ controller: EditorWindowController) {
        NSApp.setActivationPolicy(.regular)
        controller.showWindow(self)
        // macOS 14+ may ignore activation for an accessory app; orderFrontRegardless keeps the editor on top anyway.
        DispatchQueue.main.async { [weak controller] in
            NSApp.activate()
            controller?.window?.orderFrontRegardless()
            controller?.window?.makeKey()
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
