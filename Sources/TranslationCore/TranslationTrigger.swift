public enum TranslationTrigger: String, CaseIterable, Sendable {
    case dots = "..."
    case semicolons = ";;;"
    case colons = ":::"
    case atSigns = "@@@"

    public var character: String { String(rawValue.prefix(1)) }

    public var japaneseInputCharacter: String {
        switch self {
        case .dots: "。"
        case .semicolons: "；"
        case .colons: "："
        case .atSigns: "＠"
        }
    }

    public var japaneseInputMarker: String { String(repeating: japaneseInputCharacter, count: 3) }

    public func accepts(_ character: String?) -> Bool {
        character == self.character || character == japaneseInputCharacter
    }

    public func source(in line: String) -> String? {
        // The detector counts newly typed keys. An earlier sentence-ending
        // period may be identical to the marker, so preserve it as source.
        let suffix = line.suffix(3)
        if suffix.count == 3, suffix.allSatisfy({ accepts(String($0)) }) {
            return String(line.dropLast(3))
        }
        // Some apps replace three typed periods with a typographic ellipsis.
        if self == .dots, line.hasSuffix("…") {
            return String(line.dropLast())
        }
        return nil
    }
}
