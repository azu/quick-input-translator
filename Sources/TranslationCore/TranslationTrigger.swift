public enum TranslationTrigger: String, CaseIterable, Sendable {
    case dots = "..."
    case semicolons = ";;;"
    case colons = ":::"

    public var character: String { String(rawValue.prefix(1)) }

    public func accepts(_ character: String?) -> Bool {
        character == self.character || (self == .dots && character == "。")
    }

    public func source(in line: String) -> String? {
        if line.hasSuffix(rawValue) {
            let source = String(line.dropLast(rawValue.count))
            return source.hasSuffix(character) ? nil : source
        }
        // Some apps replace three typed periods with a typographic ellipsis.
        if self == .dots, line.hasSuffix("。。。。") { return nil }
        if self == .dots, line.hasSuffix("。。。") {
            return String(line.dropLast(3))
        }
        if self == .dots, line.hasSuffix("…") {
            let source = String(line.dropLast())
            return source.hasSuffix(".") || source.hasSuffix("…") ? nil : source
        }
        return nil
    }
}
