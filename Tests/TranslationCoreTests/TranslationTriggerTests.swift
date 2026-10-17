import Foundation
import Testing
@testable import TranslationCore

@Test(arguments: TranslationTrigger.allCases)
func triggeredLineExcludesMarkerFromSourceAndRemovesItOnSuccess(trigger: TranslationTrigger) throws {
    let text = "😀前\r\n日本語\(trigger.rawValue)\r\n後"
    let caret = (text as NSString).range(of: "\r\n後").location
    let target = try TextTarget(text: text, selection: NSRange(location: caret, length: 0), mode: .triggeredLine(trigger))
    #expect(target.sourceText == "日本語")
    #expect(target.replacing(with: "Japanese") == "😀前\r\nJapanese\r\n後")
}

@Test(arguments: TranslationTrigger.allCases)
func rejectsWrongIncompleteAndExcessiveMarkers(trigger: TranslationTrigger) {
    let alternatives = TranslationTrigger.allCases.filter { $0 != trigger }.map { "日本語\($0.rawValue)" }
    let invalid = alternatives + ["日本語", "日本語\(trigger.character)", "日本語\(trigger.character)\(trigger.character)",
                                  "日本語\(trigger.rawValue)\(trigger.character)"]
    for text in invalid {
        #expect(throws: InputError.noTrigger) {
            try TextTarget(text: text, selection: NSRange(location: (text as NSString).length, length: 0), mode: .triggeredLine(trigger))
        }
    }
}

@Test func rejectsMarkerInMiddleOfLineAndSelectionBeforeLineEnd() {
    let text = "日本語...続き"
    #expect(throws: InputError.noTrigger) {
        try TextTarget(text: text, selection: NSRange(location: 6, length: 0), mode: .triggeredLine(.dots))
    }
    #expect(throws: InputError.noTrigger) {
        try TextTarget(text: "日本語...", selection: NSRange(location: 0, length: 2), mode: .triggeredLine(.dots))
    }
}

@Test func japanesePeriodsAndCompositionSelectionCanTriggerTranslation() throws {
    let target = try TextTarget(text: "日本語。。。", selection: NSRange(location: 3, length: 3), mode: .triggeredLine(.dots))
    #expect(target.sourceText == "日本語")
    #expect(target.replacing(with: "Japanese") == "Japanese")
    #expect(TranslationTrigger.dots.accepts("。"))
    #expect(!TranslationTrigger.semicolons.accepts("。"))
    #expect(throws: InputError.noTrigger) {
        try TextTarget(text: "日本語。。。。", selection: NSRange(location: 7, length: 0), mode: .triggeredLine(.dots))
    }
}

@Test(arguments: TranslationTrigger.allCases)
func doesNotTranslateEmptySource(trigger: TranslationTrigger) {
    let text = " \t\(trigger.rawValue)"
    #expect(throws: InputError.empty) {
        try TextTarget(text: text, selection: NSRange(location: (text as NSString).length, length: 0), mode: .triggeredLine(trigger))
    }
}

@Test func handlesAutomaticEllipsisSubstitutionOnlyForDots() throws {
    let target = try TextTarget(text: "日本語…", selection: NSRange(location: 4, length: 0), mode: .triggeredLine(.dots))
    #expect(target.sourceText == "日本語")
    #expect(target.replacing(with: "Japanese") == "Japanese")
    #expect(throws: InputError.noTrigger) {
        try TextTarget(text: "日本語…", selection: NSRange(location: 4, length: 0), mode: .triggeredLine(.semicolons))
    }
}

@Test func waitsForExactlyThreeConsecutiveTriggerCharacters() {
    var sequence = TriggerSequence()
    let observations = (0..<13).map { _ in sequence.observe(isTriggerCharacter: true) }
    #expect(observations == [false, false, true] + Array(repeating: false, count: 10))
}

@Test func otherInputOrClickBreaksTriggerSequence() {
    var sequence = TriggerSequence()
    let observations = [true, true, false, true, true, true].map { sequence.observe(isTriggerCharacter: $0) }
    #expect(observations == [false, false, false, false, false, true])
}
