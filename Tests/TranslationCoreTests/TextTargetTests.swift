import Foundation
import Testing
@testable import TranslationCore

@Test func selectionTakesPriorityOverCurrentLine() throws {
    let text = "前の行\n日本語の文章\n次の行"
    let range = (text as NSString).range(of: "本語の")
    let target = try TextTarget(text: text, selection: range)
    #expect(target.sourceText == "本語の")
    #expect(target.replacing(with: "English") == "前の行\n日English文章\n次の行")
}

@Test func multilineSelectionIsPreserved() throws {
    let text = "前\n一行\n二行\n後"
    let range = (text as NSString).range(of: "一行\n二行")
    let target = try TextTarget(text: text, selection: range)
    #expect(target.sourceText == "一行\n二行")
    #expect(target.replacing(with: "two lines") == "前\ntwo lines\n後")
}

@Test(arguments: [0, 1, 2, 3])
func currentLineAtStartMiddleAndEnd(offset: Int) throws {
    let text = "前\n日本語\n後"
    let target = try TextTarget(text: text, selection: NSRange(location: 2 + offset, length: 0))
    #expect(target.sourceText == "日本語")
    #expect(target.replacing(with: "Japanese") == "前\nJapanese\n後")
}

@Test func emojiUsesUTF16Offsets() throws {
    let text = "😀前\n👨‍👩‍👧‍👦日本語\n後"
    let caret = (text as NSString).range(of: "語").location
    let target = try TextTarget(text: text, selection: NSRange(location: caret, length: 0))
    #expect(target.sourceText == "👨‍👩‍👧‍👦日本語")
    #expect(target.replacing(with: "Family") == "😀前\nFamily\n後")
}

@Test func crlfAndCRAreNotReplaced() throws {
    let target = try TextTarget(text: "前\r\n日本語\r\n後", selection: NSRange(location: 4, length: 0))
    #expect(target.replacing(with: "Japanese") == "前\r\nJapanese\r\n後")
    let cr = try TextTarget(text: "前\r日本語\r後", selection: NSRange(location: 3, length: 0))
    #expect(cr.replacing(with: "Japanese") == "前\rJapanese\r後")
}

@Test func lastLineAndSingleLine() throws {
    let last = try TextTarget(text: "前\n日本語", selection: NSRange(location: 5, length: 0))
    #expect(last.sourceText == "日本語")
    let single = try TextTarget(text: "日本語", selection: NSRange(location: 3, length: 0))
    #expect(single.replacing(with: "Japanese") == "Japanese")
}

@Test func emptyAndWhitespaceTargetsAreRejected() {
    for (text, location) in [("", 0), ("日本語\n", 4), ("前\n \t\n後", 3)] {
        #expect(throws: InputError.empty) {
            try TextTarget(text: text, selection: NSRange(location: location, length: 0))
        }
    }
}

@Test func invalidAndSplitSurrogateRangesAreRejected() {
    for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 0),
                  NSRange(location: 0, length: 10), NSRange(location: 1, length: 0)] {
        #expect(throws: InputError.invalidRange) { try TextTarget(text: "😀語", selection: range) }
    }
}

@Test func detectsTextAndSelectionChanges() throws {
    let selection = NSRange(location: 1, length: 0)
    let target = try TextTarget(text: "日本語", selection: selection)
    #expect(target.matches(text: "日本語", selection: selection))
    #expect(!target.matches(text: "日本語を追記", selection: selection))
    #expect(!target.matches(text: "日本語", selection: NSRange(location: 2, length: 0)))
}
