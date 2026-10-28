import Carbon.HIToolbox

private let snipzyHotKeySignature: OSType = 0x534E5A59

private func snipzyHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    let monitor = Unmanaged<CarbonHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    // Each monitor installs its own handler, so pass other hotkeys on to the next one.
    guard status == noErr, hotKeyID.signature == snipzyHotKeySignature, hotKeyID.id == monitor.id else {
        return OSStatus(eventNotHandledErr)
    }
    DispatchQueue.main.async {
        monitor.fire()
    }
    return noErr
}

final class CarbonHotKeyMonitor: @unchecked Sendable {
    private var hotKey: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let keyCode: Int
    private let modifiers: Int
    fileprivate let id: UInt32
    private let callback: () -> Void

    init(keyCode: Int, modifiers: Int = cmdKey | shiftKey, id: UInt32, callback: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.id = id
        self.callback = callback
    }

    func start() throws {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            snipzyHotKeyHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { throw HotKeyError.status(installStatus) }

        let hotKeyID = EventHotKeyID(signature: snipzyHotKeySignature, id: id)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            throw HotKeyError.status(registerStatus)
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKey = nil
        handlerRef = nil
    }

    fileprivate func fire() {
        callback()
    }

    deinit {
        stop()
    }
}

enum HotKeyError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        if case let .status(status) = self { return "Could not register screenshot hotkey (status \(status))" }
        return nil
    }
}
