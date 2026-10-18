import AppKit
import SwiftUI

@MainActor final class SettingsWindow: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var frame: NSRect?
    private(set) var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 690),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Quick Input Translator Settings"
            window.contentView = NSHostingView(rootView: SetupView(model: model))
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let frame { window.setFrame(frame, display: false) }
            else { window.center() }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        frame = closingWindow.frame
        window = nil
        // Keep AppKit's window alive until close() finishes, then detach its
        // SwiftUI tree. Capture this window so an immediate reopen stays intact.
        DispatchQueue.main.async { [closingWindow] in
            closingWindow.contentView = nil
        }
    }
}
