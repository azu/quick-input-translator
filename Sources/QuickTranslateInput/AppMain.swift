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
    private let input = AccessibilityInput()
    private lazy var workflow = TranslationWorkflow(engine: AppleTranslationEngine(), input: input)
    private var hotKey: GlobalHotKey?
    private var typingMonitor: TypingMonitor?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var pendingTrigger: Task<Void, Never>?
    private var pendingID = UUID()
    private let hud = TranslationHUD()
    private let statusMenuItem = NSMenuItem(title: "準備中", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "文⇄A"
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "日本語 → 英語 · 行末の合図で翻訳", action: nil, keyEquivalent: ""))
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
        model.onStatusChange = { [weak self] status in
            self?.statusItem?.button?.toolTip = status
            self?.statusItem?.button?.title = status == "翻訳中…" ? "翻訳中…" : "文⇄A"
        }
        let monitor = TypingMonitor { [weak self] candidate, window in self?.handleTyping(candidate: candidate, localWindow: window) }
        monitor.trigger = model.trigger
        typingMonitor = monitor
        model.onPermissionChange = { [weak self] allowed in
            guard let self else { return }
            self.typingMonitor?.start()
            if !allowed { self.cancelPendingTrigger() }
            self.model.monitorReady = self.typingMonitor?.isRunning == true
        }
        model.onTriggerChange = { [weak self] trigger in
            self?.cancelPendingTrigger()
            self?.typingMonitor?.trigger = trigger
        }
        let hotKey = GlobalHotKey { [weak self] in self?.selectLine() }
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

    private func installMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu()
        let quit = NSMenuItem(title: "Quick Translate Inputを終了", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        application.addItem(quit)
        applicationItem.submenu = application
        main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

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

    private func selectLine() {
        cancelPendingTrigger()
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { task = nil }
            do {
                try await GlobalHotKey.waitForModifiersReleased()
                try input.selectCurrentLine()
                model.setStatus("行を選択しました。")
            } catch {
                model.setStatus(error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    private func cancelPendingTrigger() {
        if pendingTrigger != nil, task == nil { hud.hide() }
        pendingID = UUID()
        pendingTrigger?.cancel()
        pendingTrigger = nil
    }

    private func handleTyping(candidate: Bool, localWindow: NSWindow?) {
        cancelPendingTrigger()
        guard candidate, task == nil else { return }
        let focus: AccessibilityInput.FocusToken
        do { focus = try input.focusToken(localWindow: localWindow) }
        catch {
            model.setStatus(error.localizedDescription)
            hud.show(error.localizedDescription, working: false)
            return
        }
        hud.show("入力を確認中…", working: true, near: input.bounds(for: focus))
        let id = UUID()
        pendingID = id
        let trigger = model.trigger
        pendingTrigger = Task { @MainActor in
            defer { if pendingID == id { pendingTrigger = nil } }
            // Input dispatch in the other process may finish after the event monitor fires.
            for _ in 0..<30 {
                do {
                    try await Task.sleep(for: .milliseconds(20))
                    guard input.hasFocus(focus) else { if pendingID == id { hud.hide() }; return }
                    input.expectFocus(focus)
                    defer { input.clear() }
                    _ = try input.capture(mode: .triggeredLine(trigger))
                    try Task.checkCancellation()
                    pendingTrigger = nil
                    translate(focus: focus, trigger: trigger)
                    return
                } catch InputError.noTrigger {
                    continue
                } catch {
                    if pendingID == id { hud.hide() }
                    return
                }
            }
            if pendingID == id { hud.hide() }
        }
    }

    private func translate(focus: AccessibilityInput.FocusToken, trigger: TranslationTrigger) {
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { task = nil }
            do {
                input.expectFocus(focus)
                try await workflow.perform(mode: .triggeredLine(trigger)) {
                    self.model.setStatus("翻訳中…")
                    self.hud.show("翻訳中…", working: true)
                }
                model.setStatus("翻訳を反映しました。")
                hud.show("翻訳しました", working: false)
            } catch InputError.noTrigger {
                // A key event may have changed the text before capture began.
                hud.hide()
            } catch {
                model.setStatus(error.localizedDescription)
                hud.show(error.localizedDescription, working: false)
                NSSound.beep()
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        task?.cancel()
        cancelPendingTrigger()
        typingMonitor?.stop()
        hud.hide()
        hotKey?.stop()
    }
}
