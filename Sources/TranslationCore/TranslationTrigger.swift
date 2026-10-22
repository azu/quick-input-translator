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
        let suffix = line.suffix(3)
        if suffix.count == 3, suffix.allSatisfy({ accepts(String($0)) }) {
            let source = String(line.dropLast(3))
            return accepts(source.last.map { String($0) }) ? nil : source
        }
        // Some apps replace three typed periods with a typographic ellipsis.
        if self == .dots, line.hasSuffix("…") {
            let source = String(line.dropLast())
            return accepts(source.last.map { String($0) }) || source.hasSuffix("…") ? nil : source
        }
        return nil
    }
}
