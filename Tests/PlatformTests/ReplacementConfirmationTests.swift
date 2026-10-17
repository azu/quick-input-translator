import Foundation
import Testing
import TranslationCore
@testable import QuickTranslateInput

@Test @MainActor func replacementWaitsForDelayedBrowserValue() async throws {
    var reads = 0
    try await ReplacementConfirmation.wait(original: "日本語...", expected: "Japanese",
                                             attempts: 5, interval: .zero) {
        reads += 1
        return reads < 4 ? "日本語..." : "Japanese"
    } hasFocus: { true }
    #expect(reads == 4)
}

@Test @MainActor func unchangedInputDoesNotCountAsSuccessfulReplacement() async {
    var reads = 0
    do {
        try await ReplacementConfirmation.wait(original: "日本語...", expected: "Japanese",
                                                 attempts: 3, interval: .zero) {
            reads += 1
            return "日本語..."
        } hasFocus: { true }
        Issue.record("An unapplied write must not report success")
    } catch {
        #expect(error as? InputError == .unconfirmed)
        #expect(reads == 3)
    }
}

@Test @MainActor func userEditDuringReplacementIsNotOverwrittenOrReportedAsSuccess() async {
    var reads = 0
    do {
        try await ReplacementConfirmation.wait(original: "日本語...", expected: "Japanese",
                                                 interval: .zero) {
            reads += 1
            return "利用者の追記"
        } hasFocus: { true }
        Issue.record("Changed input must abort confirmation")
    } catch {
        #expect(error as? InputError == .unconfirmed)
        #expect(reads == 1)
    }
}

@Test @MainActor func lostFocusCannotConfirmEvenWhenTextMatches() async {
    do {
        try await ReplacementConfirmation.wait(original: "日本語...", expected: "Japanese") {
            Issue.record("Do not read another input after losing focus")
            return "Japanese"
        } hasFocus: { false }
        Issue.record("Lost focus must abort confirmation")
    } catch {
        #expect(error as? InputError == .unconfirmed)
    }
}

@Test @MainActor func pastedParagraphRepresentationCanConfirmWithoutAnotherPaste() async throws {
    var reads = 0, comparisons = 0
    let before = try TextCoordinates(displayed: "前\n後:::", indexed: "前後:::")
    try await ReplacementConfirmation.wait(original: "前\n後:::", expected: "First\n\nLast",
                                             attempts: 3, interval: .zero) {
        reads += 1
        return reads == 1 ? "前\n後:::" : "First\nLast"
    } hasFocus: { true } matchesExpected: { current in
        comparisons += 1
        return try TextCoordinates(displayed: current, indexed: current)
            .matchesPastedText("First\n\nLast", original: before)
    }
    #expect(reads == 2)
    #expect(comparisons == 1)
}

@Test @MainActor func focusLostDuringParagraphComparisonCannotConfirm() async {
    var focused = true
    do {
        try await ReplacementConfirmation.wait(original: "原文:::", expected: "First\n\nLast") {
            "First\nLast"
        } hasFocus: { focused } matchesExpected: { _ in
            focused = false
            return true
        }
        Issue.record("Focus must still match after the additional AX read")
    } catch {
        #expect(error as? InputError == .unconfirmed)
    }
}
