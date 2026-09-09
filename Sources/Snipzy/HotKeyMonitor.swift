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
    if status == noErr, hotKeyID.signature == snipzyHotKeySignature {
        DispatchQueue.main.async {
            monitor.fire()
        }
    }
    return noErr
}

final class CarbonHotKeyMonitor: @unchecked Sendable {
    private var hotKey: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
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

        let hotKeyID = EventHotKeyID(signature: snipzyHotKeySignature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            UInt32(cmdKey | shiftKey),
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
