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
