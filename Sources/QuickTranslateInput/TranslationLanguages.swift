import Foundation
import Translation

struct TranslationLanguages: Equatable, Sendable {
    var source: Locale.Language
    var target: Locale.Language

    static func available() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    static let japaneseToEnglish = Self(source: .init(identifier: "ja"), target: .init(identifier: "en"))

    static func match(_ identifier: String, in supported: [Locale.Language]) -> Locale.Language? {
        let requested = Locale.Language(identifier: identifier)
        return supported.first { $0.isEquivalent(to: requested) }
            ?? supported.first { $0.languageCode == requested.languageCode && $0.script == requested.script }
    }

    static func systemTarget(preferred: [String] = Locale.preferredLanguages,
                             supported: [Locale.Language]) -> Locale.Language? {
        for identifier in preferred {
            if let language = match(identifier, in: supported) { return language }
        }
        return match("en", in: supported)
    }

    static func name(_ language: Locale.Language) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }
}
