import Foundation
import Translation
import TranslationCore

@MainActor final class AppleTranslationEngine: TranslationEngine {
    private let languages: () throws -> TranslationLanguages

    init(languages: @escaping () throws -> TranslationLanguages = { .japaneseToEnglish }) {
        self.languages = languages
    }

    func translate(_ text: String) async throws -> String {
        let pair = try languages()
        guard !pair.source.isEquivalent(to: pair.target) else { throw ModelError.sameLanguage }
        Diagnostics.event("translation.started", "source_length=\(text.utf16.count)")
        let status = await LanguageAvailability().status(from: pair.source, to: pair.target)
        try Task.checkCancellation()
        switch status {
        case .installed: break
        case .supported: throw ModelError.notPrepared
        case .unsupported: throw ModelError.unsupported
        @unknown default: throw ModelError.unsupported
        }
        let session = TranslationSession(installedSource: pair.source, target: pair.target)
        let result = try await session.translate(text).targetText
        Diagnostics.event("translation.finished", "result_length=\(result.utf16.count)")
        return result
    }
}

enum ModelError: LocalizedError, Equatable {
    case notPrepared, unsupported, sameLanguage
    var errorDescription: String? {
        switch self {
        case .notPrepared: "Open Settings and prepare the selected translation languages."
        case .unsupported: "This language pair is unavailable. Choose another pair in Settings."
        case .sameLanguage: "Choose different source and target languages."
        }
    }
}
