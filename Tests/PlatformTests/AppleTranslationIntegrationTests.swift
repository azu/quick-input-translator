import Foundation
import AppKit
import Testing
import TranslationCore
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

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_TRANSLATION_INTEGRATION"] == "1"))
@MainActor func installedJapaneseEnglishModelTranslatesWholeInput() async throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let source = "こんにちは。\n\n明日の会議は午後三時からです。"
    view.string = source + ":::"
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    let target = try TextViewInput.capture(view, mode: .triggeredField(.colons))
    #expect(target.sourceText == source)
    let engine = AppleTranslationEngine()
    let translated = try await engine.translate(target.sourceText)
    #expect(!translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(translated != source)
    #expect(!translated.contains(":::"))
    try TextViewInput.replace(view, target: target, translation: translated)
    #expect(view.string == translated)
    #expect(view.selectedRange() == NSRange(location: translated.utf16.count, length: 0))
}
