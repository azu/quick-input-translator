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
    private let onEvent: @MainActor (Bool, NSWindow?) -> Void

    init(onEvent: @escaping @MainActor (Bool, NSWindow?) -> Void) { self.onEvent = onEvent }

    var isRunning: Bool { local != nil && global != nil }

    func start() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if AXIsProcessTrusted() {
            if global == nil {
                global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                    MainActor.assumeIsolated { self?.observe(event, localWindow: nil) }
                }
            }
        } else if let global {
            NSEvent.removeMonitor(global)
            self.global = nil
        }
        if local == nil {
            local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.observe(event, localWindow: event.window) }
                return event
            }
        }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
        sequence = TriggerSequence()
    }

    private func observe(_ event: NSEvent, localWindow: NSWindow?) {
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .option]
        let isTriggerCharacter = event.type == .keyDown && !event.isARepeat
            && event.modifierFlags.intersection(forbidden).isEmpty && trigger.accepts(event.characters)
        onEvent(sequence.observe(isTriggerCharacter: isTriggerCharacter), localWindow)
    }
}
