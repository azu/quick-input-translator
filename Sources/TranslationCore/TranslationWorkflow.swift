import Foundation

@MainActor public protocol TranslationEngine {
    func translate(_ text: String) async throws -> String
}

@MainActor public protocol InputAccess {
    func capture() throws -> TextTarget
    func replace(_ target: TextTarget, with translation: String) async throws
    func clear()
}

@MainActor public final class TranslationWorkflow {
    public private(set) var isRunning = false
    private let engine: any TranslationEngine
    private let input: any InputAccess

    public init(engine: any TranslationEngine, input: any InputAccess) {
        self.engine = engine
        self.input = input
    }

    /// Returns false for a duplicate invocation; the original operation owns its state.
    @discardableResult public func perform() async throws -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        defer {
            input.clear()
            isRunning = false
        }
        let target = try input.capture()
        let translated = try await engine.translate(target.sourceText)
        try Task.checkCancellation()
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InputError.emptyTranslation
        }
        if translated != target.sourceText {
            try await input.replace(target, with: translated)
        }
        return true
    }
}
