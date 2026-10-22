import Foundation

/// Keep source separators separately from the text sent for translation.
public struct TranslationLayout {
    private struct Part {
        let text: String
        let separator: String
        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private let parts: [Part]
    public let lines: [String]

    public init(_ source: String) {
        var parts: [Part] = []
        var start = source.startIndex
        for index in source.indices where source[index].isNewline {
            parts.append(Part(text: String(source[start..<index]), separator: String(source[index])))
            start = source.index(after: index)
        }
        parts.append(Part(text: String(source[start...]), separator: ""))
        self.parts = parts
        self.lines = parts.filter { !$0.isBlank }.map(\.text)
    }

    /// The translations must be in the same order as `lines`.
    public func applying(_ translations: [String]) throws -> String {
        guard translations.count == lines.count else { throw InputError.emptyTranslation }
        var result = ""
        var index = 0
        for part in parts {
            if part.isBlank {
                result += part.text
            } else {
                let line = translations[index].split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard !line.isEmpty else { throw InputError.emptyTranslation }
                result += line
                index += 1
            }
            result += part.separator
        }
        return result
    }
}
