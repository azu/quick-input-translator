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
        let layout = TranslationLayout(text)
        guard !layout.lines.isEmpty else { return text }
        let translated = try await Self.translate(lines: layout.lines, languages: pair)
        try Task.checkCancellation()
        let result = try layout.applying(translated)
        Diagnostics.event("translation.finished", "result_length=\(result.utf16.count)")
        return result
    }

    // Keep the SDK's non-Sendable session and requests in one isolation region.
    nonisolated private static func translate(lines: [String], languages: TranslationLanguages) async throws -> [String] {
        try Task.checkCancellation()
        let session = TranslationSession(installedSource: languages.source, target: languages.target)
        let requests = lines.map { TranslationSession.Request(sourceText: $0) }
        return try await session.translations(from: requests).map(\.targetText)
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
