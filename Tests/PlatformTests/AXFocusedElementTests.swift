import ApplicationServices
import Testing
import TranslationCore
@testable import QuickTranslateInput

@Test @MainActor func explicitAccessDenialIsNotReportedAsMissingFocus() {
    #expect(throws: InputError.permission) {
        try AXFocusedElement.decode(result: .apiDisabled, value: nil)
    }
}

@Test @MainActor func failedOrMissingFocusIsRejected() {
    let element = AXUIElementCreateApplication(getpid())
    for (status, value) in [(AXError.cannotComplete, element as CFTypeRef?), (.success, nil),
                            (.success, "not an element" as CFString)] {
        do {
            _ = try AXFocusedElement.decode(result: status, value: value)
            Issue.record("An invalid focus read must not be accepted")
        } catch {
            #expect(error as? ExternalInputError == .focus)
        }
    }
}

@Test @MainActor func validFocusReadPreservesElementIdentity() throws {
    let element = AXUIElementCreateApplication(getpid())
    let decoded = try AXFocusedElement.decode(result: .success, value: element)
    #expect(CFEqual(decoded, element))
}
