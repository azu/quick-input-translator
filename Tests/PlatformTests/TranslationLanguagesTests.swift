import Foundation
import Testing
@testable import QuickTranslateInput

private let supported = ["ja", "en", "fr", "zh-Hans", "zh-Hant"].map { Locale.Language(identifier: $0) }

@Test func osLanguageMatchesRegionalPreference() {
    let target = TranslationLanguages.systemTarget(preferred: ["fr-CA", "en-US"], supported: supported)
    #expect(target?.minimalIdentifier == "fr")
}

@Test func chineseScriptsRemainDistinct() {
    let traditional = TranslationLanguages.systemTarget(preferred: ["zh-Hant-TW"], supported: supported)
    let simplified = TranslationLanguages.systemTarget(preferred: ["zh-Hans-CN"], supported: supported)
    #expect(traditional?.script == Locale.Language(identifier: "zh-Hant").script)
    #expect(simplified?.script == Locale.Language(identifier: "zh-Hans").script)
    #expect(TranslationLanguages.match("zh-Hant", in: [.init(identifier: "zh-Hans")]) == nil)
}

@Test func unsupportedOsLanguageFallsBackToEnglish() {
    #expect(TranslationLanguages.systemTarget(preferred: ["xx-XX"], supported: supported)?.minimalIdentifier == "en")
    #expect(TranslationLanguages.systemTarget(preferred: [], supported: []) == nil)
}

@Test @MainActor func languageSettingsPersistAndInvalidatePreparedState() throws {
    let name = "TranslationLanguagesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = AppModel(defaults: defaults)
    #expect(model.targetID == "system")
    #expect(model.sourceID == "ja")
    var cancellations = 0
    model.onLanguageChange = { cancellations += 1 }
    model.modelsInstalled = true
    model.canPrepare = true
    model.sourceID = "ja"
    #expect(cancellations == 0)
    #expect(model.modelsInstalled)
    model.sourceID = "en"
    model.targetID = "fr"
    #expect(cancellations == 2)
    #expect(!model.modelsInstalled)
    #expect(!model.canPrepare)
    let restored = AppModel(defaults: defaults)
    #expect(restored.sourceID == "en")
    #expect(restored.targetID == "fr")
    restored.languages = supported
    let pair = try restored.selectedLanguages()
    #expect(pair.source.minimalIdentifier == "en")
    #expect(pair.target.minimalIdentifier == "fr")
}

@Test @MainActor func unknownSavedLanguageDoesNotSilentlyTranslateIntoAnother() throws {
    let name = "TranslationLanguagesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = AppModel(defaults: defaults)
    model.languages = supported
    model.targetID = "xx"
    #expect(throws: ModelError.self) { try model.selectedLanguages() }
}

@Test @MainActor func sameLanguagePairIsRejectedWithoutTranslation() async throws {
    let engine = AppleTranslationEngine(languages: {
        .init(source: .init(identifier: "en"), target: .init(identifier: "en-US"))
    })
    await #expect(throws: ModelError.sameLanguage) { try await engine.translate("Hello") }
}
