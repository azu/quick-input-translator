import AppKit
import SwiftUI
import TranslationCore

@main struct QuickTranslateInputMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let workflow = TranslationWorkflow(engine: AppleTranslationEngine(), input: AccessibilityInput())
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private let statusMenuItem = NSMenuItem(title: "準備中", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "文⇄A"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "日本語 → 英語 · ⌃⇧A", action: nil, keyEquivalent: ""))
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        let setup = NSMenuItem(title: "準備とテスト…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        let quit = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        model.onStatusChange = { [weak self] status in self?.statusItem?.button?.toolTip = status }
        let hotKey = GlobalHotKey { [weak self] in self?.translate() }
        self.hotKey = hotKey
        do {
            try hotKey.register()
            model.shortcutReady = true
        } catch {
            model.setStatus(error.localizedDescription)
        }
        showSetup()
    }

    func menuWillOpen(_ menu: NSMenu) { statusMenuItem.title = model.status }

    @objc private func showSetup() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 668, height: 560),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Quick Translate Input — 準備とテスト"
            window.contentView = NSHostingView(rootView: SetupView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
    }

    private func translate() {
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { task = nil }
            do {
                try await GlobalHotKey.waitForModifiersReleased()
                model.setStatus("翻訳中…")
                try await workflow.perform()
                model.setStatus("翻訳を反映しました。")
            } catch {
                model.setStatus(error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        task?.cancel()
        hotKey?.stop()
    }
}
