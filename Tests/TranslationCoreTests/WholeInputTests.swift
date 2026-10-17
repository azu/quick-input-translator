import Foundation
import Testing
@testable import TranslationCore

@Test(arguments: TranslationTrigger.allCases)
func wholeInputIncludesAllLinesAndOnlyRemovesFinalMarker(trigger: TranslationTrigger) throws {
    let source = "😀最初の段落\r\n途中の記号\(trigger.rawValue)です。\n\n最後の段落"
    let text = source + trigger.rawValue
    let target = try TextTarget(text: text, selection: NSRange(location: text.utf16.count, length: 0),
                                mode: .triggeredField(trigger))
    #expect(target.sourceText == source)
    #expect(target.replacementRange == NSRange(location: 0, length: text.utf16.count))
    #expect(target.replacing(with: "First paragraph\n\nLast paragraph") == "First paragraph\n\nLast paragraph")
    let marker = try #require(target.triggerRange)
    #expect((text as NSString).substring(with: marker) == trigger.rawValue)
}

@Test(arguments: TranslationTrigger.allCases)
func wholeInputRejectsMarkerBeforeFieldEndAndExcessiveMarkers(trigger: TranslationTrigger) {
    for text in ["日本語\(trigger.rawValue)\n後の行", "日本語\(trigger.rawValue)続き",
                 "日本語\(trigger.rawValue)\(trigger.character)"] {
        let caret = NSMaxRange((text as NSString).range(of: trigger.rawValue))
        #expect(throws: InputError.noTrigger) {
            try TextTarget(text: text, selection: NSRange(location: caret, length: 0), mode: .triggeredField(trigger))
        }
    }
    let text = "前の行\n日本語\(trigger.rawValue)"
    #expect(throws: InputError.noTrigger) {
        try TextTarget(text: text, selection: NSRange(location: 1, length: 0), mode: .triggeredField(trigger))
    }
}

@Test(arguments: TranslationTrigger.allCases)
func wholeInputRejectsWhitespaceButAcceptsMarkerOnItsOwnLastLine(trigger: TranslationTrigger) throws {
    let empty = " \n\t" + trigger.rawValue
    #expect(throws: InputError.empty) {
        try TextTarget(text: empty, selection: NSRange(location: empty.utf16.count, length: 0), mode: .triggeredField(trigger))
    }
    let text = "最初の行\n最後の行\n" + trigger.rawValue
    let target = try TextTarget(text: text, selection: NSRange(location: text.utf16.count, length: 0), mode: .triggeredField(trigger))
    #expect(target.sourceText == "最初の行\n最後の行\n")
}

@Test(arguments: ["...", "。。。", "…"])
func wholeInputAcceptsJapaneseCompositionAndEllipsis(marker: String) throws {
    let source = "前の行\n😀日本語"
    let text = source + marker
    let selection = NSRange(location: source.utf16.count, length: marker.utf16.count)
    let target = try TextTarget(text: text, selection: selection, mode: .triggeredField(.dots))
    #expect(target.sourceText == source)
    #expect(target.originalSelection == selection)
    #expect(target.triggerRange == selection)
}

@Test func detectorRoutesEachConfiguredTriggerAndResetsOnOtherInput() {
    for line in TranslationTrigger.allCases {
        for whole in TranslationTrigger.allCases where line != whole {
            var detector = TranslationTriggerDetector(line: line, wholeInput: whole)
            for (trigger, expected) in [(line, CaptureMode.triggeredLine(line)), (whole, .triggeredField(whole))] {
                #expect(detector.observe(nil) == nil)
                #expect(detector.observe(trigger.character) == nil)
                #expect(detector.observe(trigger.character) == nil)
                #expect(detector.observe(trigger.character) == expected)
                #expect(detector.observe(trigger.character) == nil)
            }
            #expect(detector.observe(whole.character) == nil)
            #expect(detector.observe(nil) == nil) // Click or modified key.
            #expect(detector.observe(whole.character) == nil)
            #expect(detector.observe("a") == nil)
            #expect(detector.observe(whole.character) == nil)
            detector.reset()
            #expect(detector.observe(whole.character) == nil)
        }
    }
}

@Test func wholeInputRangeMapsAcrossChromiumParagraphSeparators() throws {
    let text = "😀最初\n\n最後:::"
    let indexed = text.replacingOccurrences(of: "\n", with: "")
    let coordinates = try TextCoordinates(displayed: text, indexed: indexed)
    let selections = try coordinates.displayedRanges(for: NSRange(location: indexed.utf16.count, length: 0))
    let targets = selections.compactMap { try? TextTarget(text: text, selection: $0, mode: .triggeredField(.colons)) }
    let target = try #require(targets.first)
    #expect(targets.count == 1)
    #expect(target.sourceText == "😀最初\n\n最後")
    #expect(try coordinates.indexedRange(for: target.replacementRange) == NSRange(location: 0, length: indexed.utf16.count))
}
