import AppKit
import Testing
@testable import QuickTranslateInput

@Suite(.serialized) @MainActor struct SettingsWindowTests {
    @Test func closingReleasesTheWindowAndHostingView() async throws {
        _ = NSApplication.shared
        let domain = "SettingsWindowTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        let settings = SettingsWindow(model: model)
        weak var closedWindow: NSWindow?
        weak var closedContent: NSView?
        autoreleasepool {
            settings.show()
            closedWindow = settings.window
            closedContent = settings.window?.contentView
            settings.window?.close()
        }
        #expect(settings.window == nil)
        for _ in 0..<100 {
            if closedWindow == nil && closedContent == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(closedContent == nil)
        #expect(closedWindow == nil)
    }

    @Test func immediateReopenKeepsTheNewViewAndUserState() async throws {
        _ = NSApplication.shared
        let domain = "SettingsWindowTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        model.sample = "Temporary test draft\nSecond line"
        model.sourceID = "ja"
        model.targetID = "fr"
        model.setLineTrigger(.semicolons)
        let settings = SettingsWindow(model: model)
        defer { settings.window?.close() }
        weak var closedContent: NSView?
        var previousFrame = NSRect.zero
        autoreleasepool {
            settings.show()
            settings.window?.setFrameOrigin(NSPoint(x: 140, y: 160))
            previousFrame = settings.window?.frame ?? .zero
            closedContent = settings.window?.contentView
            settings.window?.close()
            settings.show()
        }
        for _ in 0..<100 {
            if closedContent == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(closedContent == nil)
        #expect(settings.window?.contentView != nil)
        #expect(settings.window?.isVisible == true)
        #expect(settings.window?.frame == previousFrame)
        #expect(model.sample == "Temporary test draft\nSecond line")
        #expect(model.sourceID == "ja")
        #expect(model.targetID == "fr")
        #expect(model.trigger == .semicolons)
    }
}
