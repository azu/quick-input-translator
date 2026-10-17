import AppKit
import Carbon

@MainActor final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void
    private static let signature: OSType = 0x51544950 // QTIP

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    func register() throws {
        guard hotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let install = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x51544950, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches application event handlers on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &eventType, context, &handler)
        guard install == noErr else { throw HotKeyError.registration(install) }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | shiftKey),
                                        EventHotKeyID(signature: Self.signature, id: 1),
                                        GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            stop()
            throw HotKeyError.registration(status)
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    static func waitForModifiersReleased() async throws {
        let modifiers: CGEventFlags = [.maskControl, .maskShift, .maskCommand, .maskAlternate]
        for _ in 0..<200 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HotKeyError.keysHeld
    }
}

enum HotKeyError: LocalizedError {
    case registration(OSStatus), keysHeld
    var errorDescription: String? {
        switch self {
        case .registration(let status): "Ctrl＋Shift＋Aを登録できませんでした（\(status)）。他のアプリのショートカット設定を確認してください。"
        case .keysHeld: "キーを離してから、もう一度Ctrl＋Shift＋Aを押してください。"
        }
    }
}
