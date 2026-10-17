import Foundation
import Translation
import TranslationCore

@MainActor final class AppleTranslationEngine: TranslationEngine {
    static let source = Locale.Language(identifier: "ja")
    static let target = Locale.Language(identifier: "en")

    func translate(_ text: String) async throws -> String {
        let status = await LanguageAvailability().status(from: Self.source, to: Self.target)
        guard status == .installed else { throw ModelError.notPrepared }
        let session = TranslationSession(installedSource: Self.source, target: Self.target)
        return try await session.translate(text).targetText
    }
}

enum ModelError: LocalizedError {
    case notPrepared
    var errorDescription: String? {
        "「準備とテスト」で日本語・英語の言語モデルを準備してください。"
    }
}
