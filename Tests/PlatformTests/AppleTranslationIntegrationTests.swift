import Foundation
import Testing
@testable import QuickTranslateInput

// Opt in on a physical Mac with the Japanese/English models already installed.
// This initializer cannot download models or display a preparation prompt.
@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_TRANSLATION_INTEGRATION"] == "1"))
@MainActor func installedJapaneseEnglishModelTranslates() async throws {
    let name = "TranslationIntegrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = AppModel(defaults: defaults)
    model.languages = await TranslationLanguages.available()
    model.sourceID = "ja"
    model.targetID = "en"
    let engine = AppleTranslationEngine(languages: { try model.selectedLanguages() })
    let translated = try await engine.translate("こんにちは。今日は良い天気です。")
    #expect(!translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(translated != "こんにちは。今日は良い天気です。")
}
