import Foundation

public enum InputError: LocalizedError, Equatable {
    case invalidRange, empty, permission, unsupported, secure, changed, emptyTranslation, unconfirmed, noTrigger

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "Couldn’t read the selected range."
        case .empty: "There’s no text to translate."
        case .noTrigger: "There’s no translation trigger at the end of the target text."
        case .permission: "Allow Accessibility access in Settings."
        case .unsupported: "This input field doesn’t provide the access needed to read, select, and replace text."
        case .secure: "Password fields can’t be translated."
        case .changed: "Translation stopped because the text, selection, or input field changed."
        case .emptyTranslation: "No translation was returned. Your text is unchanged."
        case .unconfirmed: "Couldn’t confirm the replacement. Check the input field before trying again."
        }
    }
}

public enum CaptureMode: Equatable, Sendable {
    case selectionOrCurrentLine
    case triggeredLine(TranslationTrigger)
    case triggeredField(TranslationTrigger)

    public var trigger: TranslationTrigger? {
        switch self {
        case .selectionOrCurrentLine: nil
        case .triggeredLine(let trigger), .triggeredField(let trigger): trigger
        }
    }

    public var isWholeInput: Bool {
        if case .triggeredField = self { return true }
        return false
    }
}

/// AX and NSString both use UTF-16 offsets. Never convert these offsets to String.count.
public struct TextTarget: Equatable, Sendable {
    public let fullText: String
    public let originalSelection: NSRange
    public let replacementRange: NSRange
    public let sourceText: String
    public let triggerRange: NSRange?

    public init(text: String, selection: NSRange, mode: CaptureMode = .selectionOrCurrentLine) throws {
        let string = text as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location <= string.length,
              selection.length <= string.length - selection.location,
              Self.isUTF16Boundary(selection.location, in: string),
              Self.isUTF16Boundary(selection.location + selection.length, in: string),
              Range(selection, in: text) != nil else { throw InputError.invalidRange }

        let range: NSRange
        if mode.isWholeInput {
            range = NSRange(location: 0, length: string.length)
        } else if mode == .selectionOrCurrentLine && selection.length > 0 {
            range = selection
        } else {
            var start = 0, end = 0, contentsEnd = 0
            string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: selection.location, length: 0))
            range = NSRange(location: start, length: contentsEnd - start)
        }
        let contents = string.substring(with: range)
        let source: String
        if let trigger = mode.trigger {
            // IMEs may select the active composition at the end of the line.
            guard NSMaxRange(selection) == NSMaxRange(range) else { throw InputError.noTrigger }
            guard let beforeMarker = trigger.source(in: contents) else { throw InputError.noTrigger }
            source = beforeMarker
        } else {
            source = contents
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InputError.empty
        }
        self.fullText = text
        self.originalSelection = selection
        self.replacementRange = range
        self.sourceText = source
        if mode.trigger != nil {
            let markerLength = (contents as NSString).length - (source as NSString).length
            self.triggerRange = NSRange(location: NSMaxRange(range) - markerLength, length: markerLength)
        } else {
            self.triggerRange = nil
        }
    }

    public func matches(text: String, selection: NSRange) -> Bool {
        fullText == text && originalSelection == selection
    }

    public func replacing(with translation: String) -> String {
        (fullText as NSString).replacingCharacters(in: replacementRange, with: translation)
    }

    private static func isUTF16Boundary(_ offset: Int, in text: NSString) -> Bool {
        guard offset > 0, offset < text.length else { return true }
        let previous = text.character(at: offset - 1)
        let next = text.character(at: offset)
        return !(0xD800...0xDBFF).contains(previous) || !(0xDC00...0xDFFF).contains(next)
    }
}
