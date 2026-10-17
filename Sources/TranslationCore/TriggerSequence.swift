/// The available triggers are three repeated characters. No keyboard text is retained.
public struct TriggerSequence {
    private var count = 0
    public init() {}

    public mutating func observe(isTriggerCharacter: Bool) -> Bool {
        guard isTriggerCharacter else {
            count = 0
            return false
        }
        count = min(count + 1, 4)
        return count == 3
    }
}

/// Tracks both configured triggers without retaining text or key history.
public struct TranslationTriggerDetector {
    public let line: TranslationTrigger
    public let wholeInput: TranslationTrigger
    private var lineSequence = TriggerSequence()
    private var wholeInputSequence = TriggerSequence()

    public init(line: TranslationTrigger = .dots, wholeInput: TranslationTrigger = .colons) {
        self.line = line
        self.wholeInput = wholeInput
    }

    public mutating func observe(_ character: String?) -> CaptureMode? {
        let lineCandidate = lineSequence.observe(isTriggerCharacter: line.accepts(character))
        let wholeInputCandidate = wholeInputSequence.observe(isTriggerCharacter: wholeInput.accepts(character))
        if lineCandidate { return .triggeredLine(line) }
        if wholeInputCandidate { return .triggeredField(wholeInput) }
        return nil
    }

    public mutating func reset() {
        lineSequence = TriggerSequence()
        wholeInputSequence = TriggerSequence()
    }
}
