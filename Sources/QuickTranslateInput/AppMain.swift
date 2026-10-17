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
    private lazy var workflow = TranslationWorkflow(engine: AppleTranslationEngine(languages: { [model] in try model.selectedLanguages() }), input: input)
    private var hotKey: GlobalHotKey?
    private var typingMonitor: TypingMonitor?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var pendingTrigger: Task<Void, Never>?
    private var pendingID = UUID()
    private var permissionWatch: Task<Void, Never>?
    private let hud = TranslationHUD()
    private let pairMenuItem = NSMenuItem(title: "Translation", action: nil, keyEquivalent: "")
    private let statusMenuItem = NSMenuItem(title: "Getting ready", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.event("app.started", "build=\(Bundle.main.object(forInfoDictionaryKey: "QTIBuildID") as? String ?? "unknown") pid=\(getpid())")
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Quick Translate Input")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(pairMenuItem)
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        let setup = NSMenuItem(title: "Settings…", action: #selector(showSetup), keyEquivalent: "")
        setup.target = self
        menu.addItem(setup)
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        model.onStatusChange = { [weak self] status in
            self?.statusItem?.button?.toolTip = status
            self?.statusItem?.button?.title = status == "Translating…" ? "…" : ""
        }
        let monitor = TypingMonitor { [weak self] candidate, window in self?.handleTyping(candidate: candidate, localWindow: window) }
        monitor.trigger = model.trigger
        monitor.onExternalKey = { [weak self] in
            self?.model.externalInputStatus = "Last input from another app: \(Date().formatted(date: .omitted, time: .standard))"
        }
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
        model.onLanguageChange = { [weak self] in
            self?.cancelPendingTrigger()
            self?.task?.cancel()
        }
        model.checkPermission(force: true)
        permissionWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                self?.model.checkPermission()
            }
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

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem.title = model.status
        pairMenuItem.title = model.pairTitle
    }

    private func installMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu()
        let quit = NSMenuItem(title: "Quit Quick Translate Input", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSetup), keyEquivalent: ",")
        settings.target = self
        application.addItem(settings)
        application.addItem(.separator())
        application.addItem(quit)
        applicationItem.submenu = application
        main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showSetup() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 690),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Quick Translate Input Settings"
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
                model.setStatus("Current line selected.")
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
        if workflow.isRunning { task?.cancel(); return }
        guard candidate, task == nil else { return }
        Diagnostics.begin()
        let focus: AccessibilityInput.FocusToken
        do { focus = try input.focusToken(localWindow: localWindow) }
        catch {
            Diagnostics.failure("focus.failed", error)
            model.setStatus(error.localizedDescription)
            hud.showFailure(error.localizedDescription)
            return
        }
        model.setStatus("Checking input…")
        hud.showProgress("Checking input…", near: input.bounds(for: focus))
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
                    let target = try input.capture(mode: .triggeredLine(trigger))
                    hud.showProgress("Checking input…", near: input.bounds(for: focus, range: target.triggerRange))
                    try Task.checkCancellation()
                    pendingTrigger = nil
                    translate(focus: focus, trigger: trigger)
                    return
                } catch InputError.noTrigger {
                    continue
                } catch is CancellationError {
                    Diagnostics.event("trigger.cancelled")
                    return
                } catch {
                    Diagnostics.failure("capture.failed", error)
                    if pendingID == id {
                        model.setStatus(error.localizedDescription)
                        hud.showFailure(error.localizedDescription)
                    }
                    return
                }
            }
            if pendingID == id {
                let message = "Couldn’t confirm the line-end trigger and cursor position."
                model.setStatus(message)
                hud.showFailure(message)
            }
            Diagnostics.event("trigger.expired")
        }
    }

    private func translate(focus: AccessibilityInput.FocusToken, trigger: TranslationTrigger) {
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { task = nil }
            do {
                input.expectFocus(focus)
                try await workflow.perform(mode: .triggeredLine(trigger)) {
                    self.model.setStatus("Translating…")
                    self.hud.showProgress("Translating…")
                }
                model.setStatus("Translation applied.")
                Diagnostics.event("workflow.succeeded")
                hud.showSuccess()
            } catch is CancellationError {
                Diagnostics.event("workflow.cancelled")
                model.setStatus("Translation cancelled. Your text is unchanged.")
                hud.hide()
            } catch InputError.noTrigger {
                Diagnostics.event("workflow.no_trigger")
                // A key event may have changed the text before capture began.
                hud.hide()
            } catch {
                Diagnostics.failure("workflow.failed", error)
                model.setStatus(error.localizedDescription)
                hud.showFailure(error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        permissionWatch?.cancel()
        task?.cancel()
        cancelPendingTrigger()
        typingMonitor?.stop()
        hud.hide()
        hotKey?.stop()
    }
}
