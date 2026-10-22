import Foundation
import Testing
@testable import TranslationCore

@Test(arguments: [(TranslationTrigger.dots, "。"), (.semicolons, "；"), (.colons, "："), (.atSigns, "＠")])
func japaneseTriggerCharactersMatchTheirConfiguredTrigger(trigger: TranslationTrigger, character: String) {
    #expect(trigger.japaneseInputCharacter == character)
    #expect(trigger.japaneseInputMarker == String(repeating: character, count: 3))
    #expect(trigger.accepts(character))
    for other in TranslationTrigger.allCases where other != trigger {
        #expect(!other.accepts(character))
    }
}

@Test(arguments: TranslationTrigger.allCases)
func japaneseAndMixedMarkersPreserveSourceAndRanges(trigger: TranslationTrigger) throws {
    // Exercise every arrangement of half-width and Japanese characters.
    for pattern in 0..<8 {
        let marker = (0..<3).map { pattern & (1 << $0) == 0 ? trigger.character : trigger.japaneseInputCharacter }.joined()
        let source = "😀ＡＢＣ；本文：＠。を残す"
        let text = "前\r\n" + source + marker + "\r\n後"
        let selection = NSRange(location: ("前\r\n" + source).utf16.count, length: marker.utf16.count)
        let target = try TextTarget(text: text, selection: selection, mode: .triggeredLine(trigger))
        #expect(target.sourceText == source)
        #expect(target.triggerRange == selection)
        #expect(target.replacing(with: "Translation") == "前\r\nTranslation\r\n後")
    }
}

@Test(arguments: TranslationTrigger.allCases)
func japaneseMarkersRejectIncompleteWrongAndNonfinalInput(trigger: TranslationTrigger) {
    let character = trigger.japaneseInputCharacter
    var invalid = ["日本語" + character, "日本語" + character + character,
                   "日本語" + trigger.japaneseInputMarker + "続き"]
    invalid += TranslationTrigger.allCases.filter { $0 != trigger }.map { "日本語" + $0.japaneseInputMarker }
    for text in invalid {
        for mode in [CaptureMode.triggeredLine(trigger), .triggeredField(trigger)] {
            #expect(throws: InputError.noTrigger) {
                try TextTarget(text: text, selection: NSRange(location: text.utf16.count, length: 0), mode: mode)
            }
        }
    }
}

@Test(arguments: TranslationTrigger.allCases)
func triggeredLineExcludesMarkerFromSourceAndRemovesItOnSuccess(trigger: TranslationTrigger) throws {
    let text = "😀前\r\n日本語\(trigger.rawValue)\r\n後"
    let caret = (text as NSString).range(of: "\r\n後").location
    let target = try TextTarget(text: text, selection: NSRange(location: caret, length: 0), mode: .triggeredLine(trigger))
    #expect(target.sourceText == "日本語")
    #expect(target.replacing(with: "Japanese") == "😀前\r\nJapanese\r\n後")
}

@Test(arguments: TranslationTrigger.allCases)
func rejectsWrongAndIncompleteMarkers(trigger: TranslationTrigger) {
    let alternatives = TranslationTrigger.allCases.filter { $0 != trigger }.map { "日本語\($0.rawValue)" }
    let invalid = alternatives + ["日本語", "日本語\(trigger.character)", "日本語\(trigger.character)\(trigger.character)"]
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
}

@Test(arguments: TranslationTrigger.allCases)
func confirmedTriggerPreservesExistingMatchingPunctuation(trigger: TranslationTrigger) throws {
    for punctuation in [trigger.character, trigger.japaneseInputCharacter] {
        let source = "日本語" + punctuation
        for marker in [trigger.rawValue, trigger.japaneseInputMarker] {
            let text = source + marker
            for mode in [CaptureMode.triggeredLine(trigger), .triggeredField(trigger)] {
                let target = try TextTarget(text: text, selection: NSRange(location: text.utf16.count, length: 0), mode: mode)
                #expect(target.sourceText == source)
                #expect(target.triggerRange == NSRange(location: source.utf16.count, length: marker.utf16.count))
            }
        }
    }
}

@Test(arguments: TranslationTrigger.allCases)
func doesNotTranslateEmptySource(trigger: TranslationTrigger) {
    for marker in [trigger.rawValue, trigger.japaneseInputMarker] {
        let text = " \t\(marker)"
        for mode in [CaptureMode.triggeredLine(trigger), .triggeredField(trigger)] {
            #expect(throws: InputError.empty) {
                try TextTarget(text: text, selection: NSRange(location: text.utf16.count, length: 0), mode: mode)
            }
        }
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
