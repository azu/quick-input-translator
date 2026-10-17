import AppKit
import ApplicationServices
import TranslationCore

@MainActor final class TypingMonitor {
    private var local: Any?
    private var global: Any?
    private var sequence = TriggerSequence()
    var trigger: TranslationTrigger = .dots {
        didSet { sequence = TriggerSequence() }
    }
    private let onEvent: @MainActor (Bool) -> Void

    init(onEvent: @escaping @MainActor (Bool) -> Void) { self.onEvent = onEvent }

    var isRunning: Bool { local != nil && global != nil }

    func start() {
        guard !isRunning, AXIsProcessTrusted() else { return }
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
            return event
        }
        if !isRunning { stop() }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
        sequence = TriggerSequence()
    }

    private func observe(_ event: NSEvent) {
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .option]
        let isTriggerCharacter = event.type == .keyDown && !event.isARepeat
            && event.modifierFlags.intersection(forbidden).isEmpty && event.characters == trigger.character
        onEvent(sequence.observe(isTriggerCharacter: isTriggerCharacter))
    }
}
