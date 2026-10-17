import CoreGraphics
import TranslationCore

@MainActor enum PasteShortcut {
    static func post(
        to pid: pid_t, onSubmit: () -> Void = {},
        send: (CGEvent, pid_t) -> Void = { event, pid in event.postToPid(pid) }
    ) async throws {
        try Task.checkCancellation()
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw InputError.unsupported
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        onSubmit()
        send(down, pid)
        Diagnostics.event("paste.key_down", "pid=\(pid)")
        // Never leave the target with a synthetic key held, even when cancelled.
        defer { send(up, pid); Diagnostics.event("paste.key_up", "pid=\(pid)") }
        try await Task.sleep(for: .milliseconds(20))
    }
}
