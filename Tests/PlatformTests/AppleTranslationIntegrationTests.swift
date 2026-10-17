import Foundation
import Testing
@testable import QuickTranslateInput

// Opt in on a physical Mac with the Japanese/English models already installed.
// This initializer cannot download models or display a preparation prompt.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_TRANSLATION_INTEGRATION"] == "1"))
@MainActor func installedJapaneseEnglishModelTranslates() async throws {
    let translated = try await AppleTranslationEngine().translate("こんにちは。今日は良い天気です。")
    #expect(!translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(translated != "こんにちは。今日は良い天気です。")
}
