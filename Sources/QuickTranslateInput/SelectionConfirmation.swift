import Foundation
import TranslationCore

/// An AX setter can return before the target process publishes the new selection.
@MainActor enum SelectionConfirmation {
    static func wait(
        for requested: NSRange, from original: NSRange,
        read: () throws -> NSRange, validate: () throws -> Void
    ) async throws {
        for _ in 0..<25 {
            try Task.checkCancellation()
            try validate()
            let current = try read()
            if current == requested { return }
            guard current == original else { throw InputError.changed }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ExternalInputError.selection
    }
}
