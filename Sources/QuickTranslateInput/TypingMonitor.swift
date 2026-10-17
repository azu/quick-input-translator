import AppKit
import ApplicationServices
import TranslationCore

@MainActor final class TypingMonitor {
    private var local: Any?
    private var global: Any?
    private var detector = TranslationTriggerDetector()
    private var lastExternalReport = Date.distantPast
    var onExternalKey: (() -> Void)?
    func configure(line: TranslationTrigger, wholeInput: TranslationTrigger) {
        detector = TranslationTriggerDetector(line: line, wholeInput: wholeInput)
    }
    private let onEvent: @MainActor (CaptureMode?, NSWindow?) -> Void

    init(onEvent: @escaping @MainActor (CaptureMode?, NSWindow?) -> Void) { self.onEvent = onEvent }

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
        detector.reset()
    }

    private func observe(_ event: NSEvent, localWindow: NSWindow?) {
        if localWindow == nil, event.type == .keyDown, Date().timeIntervalSince(lastExternalReport) >= 1 {
            lastExternalReport = Date()
            onExternalKey?()
        }
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .option]
        let isTyping = event.type == .keyDown && !event.isARepeat
            && event.modifierFlags.intersection(forbidden).isEmpty
        onEvent(detector.observe(isTyping ? event.characters : nil), localWindow)
    }
}
