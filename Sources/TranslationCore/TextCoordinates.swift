import Foundation

/// Relates displayed text to the text indexed by an external editor's selection API.
/// Chromium contenteditable can add paragraph separators to AXValue only.
public struct TextCoordinates: Equatable, Sendable {
    private let offsets: [Int]
    private let indexedText: String
    private let displayedText: String
    public let indexedLength: Int
    public var isIdentity: Bool { offsets.count == indexedLength + 1 }

    public init(displayed: String, indexed: String) throws {
        let display = Array(displayed.utf16), native = Array(indexed.utf16)
        var offsets = [0], index = 0
        for unit in display {
            if index < native.count, unit == native[index] {
                index += 1
            } else if unit != 10 {
                throw InputError.unsupported
            }
            offsets.append(index)
        }
        guard index == native.count else { throw InputError.unsupported }
        self.offsets = offsets
        self.indexedText = indexed
        self.displayedText = displayed
        self.indexedLength = native.count
    }

    /// Selection text may omit only paragraph separators already verified by
    /// the AXValue / AXStringForRange mapping. Explicit line breaks stay intact.
    public func matchesSelectedText(_ selected: String, range: NSRange) throws -> Bool {
        let nativeRange = try indexedRange(for: range)
        return selected == (displayedText as NSString).substring(with: range)
            || selected == (indexedText as NSString).substring(with: nativeRange)
    }

    public func indexedRange(for range: NSRange) throws -> NSRange {
        guard range.location >= 0, range.length >= 0, range.location < offsets.count,
              range.length < offsets.count - range.location else { throw InputError.invalidRange }
        let start = offsets[range.location], end = offsets[NSMaxRange(range)]
        return NSRange(location: start, length: end - start)
    }

    public func displayedRanges(for range: NSRange) throws -> [NSRange] {
        guard range.location >= 0, range.length >= 0, range.location <= indexedLength,
              range.length <= indexedLength - range.location else { throw InputError.invalidRange }
        let starts = offsets.indices.filter { offsets[$0] == range.location }
        if range.length == 0 { return starts.map { NSRange(location: $0, length: 0) } }
        let ends = offsets.indices.filter { offsets[$0] == NSMaxRange(range) }
        guard starts.count * ends.count <= 256 else { throw InputError.unsupported }
        return starts.flatMap { start in ends.filter { $0 >= start }.map { NSRange(location: start, length: $0 - start) } }
    }
}
