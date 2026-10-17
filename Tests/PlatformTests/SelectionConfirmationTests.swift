import Foundation
import Testing
import TranslationCore
@testable import QuickTranslateInput

@Test @MainActor func delayedBrowserSelectionIsAcknowledgedBeforePaste() async throws {
    let caret = NSRange(location: 6, length: 0)
    let line = NSRange(location: 0, length: 6)
    var reads = 0
    var validations = 0
    try await SelectionConfirmation.wait(for: line, from: caret) {
        reads += 1
        return reads < 3 ? caret : line
    } validate: {
        validations += 1
    }
    #expect(reads == 3)
    #expect(validations == 3)
}

@Test @MainActor func inputChangeWhileWaitingForSelectionPreventsPaste() async {
    var reads = 0
    do {
        try await SelectionConfirmation.wait(for: NSRange(location: 0, length: 6),
                                              from: NSRange(location: 6, length: 0)) {
            reads += 1
            return NSRange(location: 6, length: 0)
        } validate: {
            if reads > 0 { throw InputError.changed }
        }
        Issue.record("Changed input must not reach the paste step")
    } catch {
        #expect(error as? InputError == .changed)
        #expect(reads == 1)
    }
}

@Test @MainActor func unexpectedUserSelectionPreventsPaste() async {
    do {
        try await SelectionConfirmation.wait(for: NSRange(location: 0, length: 6),
                                              from: NSRange(location: 6, length: 0)) {
            NSRange(location: 1, length: 2)
        } validate: {}
        Issue.record("A different selection must not reach the paste step")
    } catch {
        #expect(error as? InputError == .changed)
    }
}
