import Foundation
import Testing
@testable import TranslationCore

@Test func chromiumParagraphCaretFindsMarkerInDisplayedLine() throws {
    let text = "前の行。\nこんにちは...\n後の行。"
    let indexed = text.replacingOccurrences(of: "\n", with: "")
    let coordinates = try TextCoordinates(displayed: text, indexed: indexed)
    let nativeReplacement = (indexed as NSString).range(of: "こんにちは...")
    let caret = NSRange(location: NSMaxRange(nativeReplacement), length: 0)
    let targets = try coordinates.displayedRanges(for: caret).compactMap {
        try? TextTarget(text: text, selection: $0, mode: .triggeredLine(.dots))
    }
    #expect(targets.count == 1)
    let target = try #require(targets.first)
    #expect(target.sourceText == "こんにちは")
    #expect(try coordinates.indexedRange(for: target.replacementRange) == nativeReplacement)
    #expect(target.replacing(with: "Hello") == "前の行。\nHello\n後の行。")
}

@Test func coordinateMappingPreservesEmojiAndExplicitLineBreaks() throws {
    let text = "🙂 前\n日本語...\n後"
    let identity = try TextCoordinates(displayed: text, indexed: text)
    let range = (text as NSString).range(of: "日本語...")
    #expect(identity.isIdentity)
    #expect(try identity.indexedRange(for: range) == range)
    #expect(try identity.displayedRanges(for: range) == [range])
    let indexed = text.replacingOccurrences(of: "\n", with: "")
    let mapped = try TextCoordinates(displayed: text, indexed: indexed)
    #expect(try mapped.indexedRange(for: range) == (indexed as NSString).range(of: "日本語..."))
}

@Test func generatedBlankLinesDoNotGuessWhichLineOwnsCaret() throws {
    let mapping = try TextCoordinates(displayed: "A\n\nB", indexed: "AB")
    #expect(try mapping.displayedRanges(for: NSRange(location: 1, length: 0)) == [
        NSRange(location: 1, length: 0), NSRange(location: 2, length: 0), NSRange(location: 3, length: 0)
    ])
}

@Test func unrelatedIndexedTextIsRejectedInsteadOfCorrected() {
    #expect(throws: InputError.unsupported) { try TextCoordinates(displayed: "A\nB", indexed: "AXB") }
    #expect(throws: InputError.unsupported) { try TextCoordinates(displayed: "A B", indexed: "AB") }
    #expect(throws: InputError.unsupported) { try TextCoordinates(displayed: "AB", indexed: "ABC") }
}

@Test func coordinateRangesOutsideTextAreRejected() throws {
    let mapping = try TextCoordinates(displayed: "A\nB", indexed: "AB")
    #expect(throws: InputError.invalidRange) { try mapping.indexedRange(for: NSRange(location: 3, length: 1)) }
    #expect(throws: InputError.invalidRange) { try mapping.displayedRanges(for: NSRange(location: 3, length: 0)) }
    #expect(throws: InputError.invalidRange) { try mapping.indexedRange(for: NSRange(location: -1, length: 0)) }
}
