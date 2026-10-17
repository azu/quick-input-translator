import AppKit
import Testing
@testable import QuickTranslateInput

@Test @MainActor func progressIsAVisibleNonActivatingIconAboveText() throws {
    let application = NSApplication.shared
    let hud = TranslationHUD()
    defer { hud.hide() }
    let message = "HUD test " + UUID().uuidString
    let anchor = NSRect(x: 300, y: 300, width: 18, height: 20)
    hud.showProgress(message, near: anchor)
    let panel = try #require(application.windows.first { $0.title == message })
    #expect(panel.isVisible)
    #expect(panel.frame.size == NSSize(width: 28, height: 28))
    #expect(panel.frame.midX == anchor.midX)
    #expect(panel.frame.minY == anchor.maxY + 6)
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(panel.ignoresMouseEvents)
    hud.showSuccess()
    #expect(panel.title == "Translated")
    #expect(panel.frame.size == NSSize(width: 28, height: 28))
}

@Test @MainActor func indicatorIsCenteredAboveTrigger() {
    let anchor = NSRect(x: 100, y: 200, width: 18, height: 20)
    let origin = TranslationHUD.origin(above: anchor, size: NSSize(width: 28, height: 28),
                                       within: NSRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(origin == NSPoint(x: 95, y: 226))
}

@Test @MainActor func zeroWidthCaretStillAnchorsIndicator() {
    let anchor = NSRect(x: 100, y: 200, width: 0, height: 20)
    let origin = TranslationHUD.origin(above: anchor, size: NSSize(width: 28, height: 28),
                                       within: NSRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(origin == NSPoint(x: 86, y: 226))
}

@Test @MainActor func indicatorMovesBelowTextAtTopOfScreen() {
    let anchor = NSRect(x: 100, y: 960, width: 18, height: 20)
    let origin = TranslationHUD.origin(above: anchor, size: NSSize(width: 28, height: 28),
                                       within: NSRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(origin.y == 926)
}

@Test @MainActor func indicatorStaysOnSecondaryScreenAtEdge() {
    let origin = TranslationHUD.origin(above: NSRect(x: -1000, y: 100, width: 0, height: 20),
                                       size: NSSize(width: 28, height: 28),
                                       within: NSRect(x: -1000, y: -200, width: 1000, height: 800))
    #expect(origin == NSPoint(x: -992, y: 126))
}
