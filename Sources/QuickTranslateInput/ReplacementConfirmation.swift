import Foundation
import TranslationCore

@MainActor enum ReplacementConfirmation {
    enum Observation: String { case original, expected, different, unreadable, focusLost, cancelled, timeout }

    static func wait(
        original: String, expected: String,
        attempts: Int = 100, interval: Duration = .milliseconds(20),
        read: () throws -> String, hasFocus: () -> Bool,
        onObservation: (Observation) -> Void = { _ in }
    ) async throws {
        var previous: Observation?
        func observe(_ state: Observation) {
            if previous != state { onObservation(state); previous = state }
        }
        for _ in 0..<attempts {
            guard !Task.isCancelled else { observe(.cancelled); throw InputError.unconfirmed }
            guard hasFocus() else { observe(.focusLost); throw InputError.unconfirmed }
            if let current = try? read() {
                if current == expected { observe(.expected); return }
                guard current == original else { observe(.different); throw InputError.unconfirmed }
                observe(.original)
            } else { observe(.unreadable) }
            do { try await Task.sleep(for: interval) }
            catch { observe(.cancelled); throw InputError.unconfirmed }
        }
        observe(.timeout)
        throw InputError.unconfirmed
    }
}
