import Foundation
import Testing
@testable import TranslationCore

@Test(arguments: ["...", "。。。", "…"])
func markerRangeUsesActualMarkerAfterEmojiAndOtherLines(marker: String) throws {
    let text = "前の行\n😀日本語" + marker
    let target = try TextTarget(text: text, selection: NSRange(location: (text as NSString).length, length: 0),
                                mode: .triggeredLine(.dots))
    let range = try #require(target.triggerRange)
    #expect((text as NSString).substring(with: range) == marker)
    #expect(NSMaxRange(range) == NSMaxRange(target.replacementRange))
}

@Test func ordinaryLineSelectionHasNoMarkerAnchor() throws {
    let target = try TextTarget(text: "日本語", selection: NSRange(location: 3, length: 0))
    #expect(target.triggerRange == nil)
}
