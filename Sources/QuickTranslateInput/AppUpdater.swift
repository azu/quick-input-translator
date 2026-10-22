import AppKit
import Sparkle

/// Only release bundles opt in. Locally signed builds must never be replaced
/// with a differently signed release, which would discard Accessibility trust.
// Sparkle documents that the standard driver and its delegates run on the
// main thread; the Objective-C delegate protocol has no actor annotations.
@MainActor final class AppUpdater: NSObject, NSMenuItemValidation, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var updateItems: [NSMenuItem] = []

    static func isConfigured(_ info: [String: Any]) -> Bool {
        guard info["QTIReleaseChannel"] as? String == "signed-release",
              let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }

    func start() {
        guard controller == nil, Self.isConfigured(Bundle.main.infoDictionary ?? [:]) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        controller?.startUpdater()
    }

    func addMenuItems(to menu: NSMenu) {
        guard controller != nil else { return }
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleChecks), keyEquivalent: "")
        let install = NSMenuItem(title: "Automatically Install Updates", action: #selector(toggleInstallation), keyEquivalent: "")
        for item in [check, automatic, install] {
            item.target = self
            menu.addItem(item)
        }
        updateItems.append(check)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let updater = controller?.updater else { return false }
        switch menuItem.action {
        case #selector(checkForUpdates): return updater.canCheckForUpdates
        case #selector(toggleChecks):
            menuItem.state = updater.automaticallyChecksForUpdates ? .on : .off
            return true
        case #selector(toggleInstallation):
            menuItem.state = updater.automaticallyDownloadsUpdates ? .on : .off
            return updater.automaticallyChecksForUpdates
        default: return false
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    @objc private func toggleChecks(_ sender: Any?) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
    }

    @objc private func toggleInstallation(_ sender: Any?) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyDownloadsUpdates.toggle()
    }

    // A menu bar app needs a visible reminder without taking typing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        for item in updateItems { item.title = "Update Available…" }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        resetReminder()
    }

    func standardUserDriverWillFinishUpdateSession() { resetReminder() }

    private func resetReminder() {
        for item in updateItems { item.title = "Check for Updates…" }
    }
}
