import Foundation
import Testing
@testable import TranslationCore

@MainActor private final class StubInput: InputAccess {
    var text = "前\n日本語\n後"
    var selection = NSRange(location: 3, length: 0)
    var replacements = 0
    var cleared = 0
    var captureError: InputError?
    func capture(mode: CaptureMode) throws -> TextTarget {
        if let captureError { throw captureError }
        return try TextTarget(text: text, selection: selection, mode: mode)
    }
    func replace(_ target: TextTarget, with translation: String) async throws {
        guard target.matches(text: text, selection: selection) else { throw InputError.changed }
        text = target.replacing(with: translation)
        replacements += 1
    }
    func clear() { cleared += 1 }
}

@MainActor private final class StubEngine: TranslationEngine {
    var result = "Japanese"
    var error: InputError?
    var calls = 0
    var duringTranslation: (() async throws -> Void)?
    func translate(_ text: String) async throws -> String {
        calls += 1
        try await duringTranslation?()
        if let error { throw error }
        return result
    }
}

@Test @MainActor func workflowOnlyReplacesTarget() async throws {
    let input = StubInput(), engine = StubEngine()
    let workflow = TranslationWorkflow(engine: engine, input: input)
    #expect(try await workflow.perform())
    #expect(input.text == "前\nJapanese\n後")
    #expect(input.replacements == 1)
    #expect(input.cleared == 1)
    #expect(!workflow.isRunning)
}

@Test @MainActor func changedInputIsNotOverwritten() async {
    let input = StubInput(), engine = StubEngine()
    engine.duringTranslation = { input.text += "追記" }
    let workflow = TranslationWorkflow(engine: engine, input: input)
    await #expect(throws: InputError.changed) { try await workflow.perform() }
    #expect(input.text == "前\n日本語\n後追記")
    #expect(input.replacements == 0)
    #expect(input.cleared == 1)
}

@Test @MainActor func permissionFailureDoesNotTranslate() async {
    let input = StubInput(), engine = StubEngine()
    input.captureError = .permission
    let workflow = TranslationWorkflow(engine: engine, input: input)
    await #expect(throws: InputError.permission) { try await workflow.perform() }
    #expect(engine.calls == 0)
    #expect(input.replacements == 0)
    #expect(!workflow.isRunning)
}

@Test @MainActor func translationFailureAndEmptyResultNeverReplace() async {
    for shouldThrow in [true, false] {
        let input = StubInput(), engine = StubEngine()
        engine.error = shouldThrow ? .unsupported : nil
        engine.result = " \n"
        let workflow = TranslationWorkflow(engine: engine, input: input)
        await #expect(throws: shouldThrow ? InputError.unsupported : InputError.emptyTranslation) {
            try await workflow.perform()
        }
        #expect(input.text == "前\n日本語\n後")
        #expect(input.replacements == 0)
        #expect(input.cleared == 1)
    }
}

@Test @MainActor func duplicateInvocationIsIgnored() async throws {
    let input = StubInput(), engine = StubEngine()
    let workflow = TranslationWorkflow(engine: engine, input: input)
    engine.duringTranslation = { () async throws -> Void in
        let duplicate = try await workflow.perform()
        #expect(!duplicate)
    }
    #expect(try await workflow.perform())
    #expect(engine.calls == 1)
    #expect(input.replacements == 1)
    #expect(input.cleared == 1)
}

@Test @MainActor func unchangedTranslationDoesNotPaste() async throws {
    let input = StubInput(), engine = StubEngine()
    engine.result = "日本語"
    let workflow = TranslationWorkflow(engine: engine, input: input)
    #expect(try await workflow.perform())
    #expect(input.replacements == 0)
}

@Test @MainActor func cancelledTranslationDoesNotPaste() async {
    let input = StubInput(), engine = StubEngine()
    engine.duringTranslation = { withUnsafeCurrentTask { $0?.cancel() } }
    let workflow = TranslationWorkflow(engine: engine, input: input)
    let task = Task { try await workflow.perform() }
    do {
        _ = try await task.value
        Issue.record("Cancellation should have stopped replacement")
    } catch is CancellationError {
        #expect(input.replacements == 0)
        #expect(input.cleared == 1)
        #expect(!workflow.isRunning)
    } catch { Issue.record("Unexpected error: \(error)") }
}

@Test @MainActor func triggerIsRemovedEvenWhenTranslationMatchesSource() async throws {
    let input = StubInput(), engine = StubEngine()
    input.text = "前\n日本語...\n後"
    input.selection = NSRange(location: 8, length: 0)
    engine.result = "日本語"
    let workflow = TranslationWorkflow(engine: engine, input: input)
    #expect(try await workflow.perform(mode: .triggeredLine(.dots)))
    #expect(input.text == "前\n日本語\n後")
    #expect(input.replacements == 1)
}

@Test @MainActor func failedTranslationKeepsTriggerAndOriginalText() async {
    let input = StubInput(), engine = StubEngine()
    input.text = "前\n日本語;;;\n後"
    input.selection = NSRange(location: 8, length: 0)
    engine.error = .unsupported
    let workflow = TranslationWorkflow(engine: engine, input: input)
    await #expect(throws: InputError.unsupported) { try await workflow.perform(mode: .triggeredLine(.semicolons)) }
    #expect(input.text == "前\n日本語;;;\n後")
    #expect(input.replacements == 0)
}
