import Foundation

public enum InputError: LocalizedError, Equatable {
    case invalidRange, empty, permission, unsupported, secure, changed, emptyTranslation, unconfirmed, noTrigger

    public var errorDescription: String? {
        switch self {
        case .invalidRange: "選択範囲を正しく取得できませんでした。"
        case .empty: "翻訳する文章がありません。"
        case .noTrigger: "行末に翻訳の合図がありません。"
        case .permission: "「準備とテスト」からアクセシビリティ権限を許可してください。"
        case .unsupported: "この入力欄では文章の取得・選択・貼り付けを確認できません。"
        case .secure: "パスワード欄は翻訳しません。"
        case .changed: "入力内容・選択範囲・入力先が変わったため、反映を中止しました。"
        case .emptyTranslation: "訳文が空だったため、反映しませんでした。"
        case .unconfirmed: "反映を確認できませんでした。再試行せず、入力欄を確認してください。クリップボードは復元していません。"
        }
    }
}

public enum CaptureMode: Equatable, Sendable {
    case selectionOrCurrentLine
    case triggeredLine(TranslationTrigger)
}

/// AX and NSString both use UTF-16 offsets. Never convert these offsets to String.count.
public struct TextTarget: Equatable, Sendable {
    public let fullText: String
    public let originalSelection: NSRange
    public let replacementRange: NSRange
    public let sourceText: String

    public init(text: String, selection: NSRange, mode: CaptureMode = .selectionOrCurrentLine) throws {
        let string = text as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location <= string.length,
              selection.length <= string.length - selection.location,
              Self.isUTF16Boundary(selection.location, in: string),
              Self.isUTF16Boundary(selection.location + selection.length, in: string),
              Range(selection, in: text) != nil else { throw InputError.invalidRange }

        let range: NSRange
        if mode == .selectionOrCurrentLine && selection.length > 0 {
            range = selection
        } else {
            var start = 0, end = 0, contentsEnd = 0
            string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: selection.location, length: 0))
            range = NSRange(location: start, length: contentsEnd - start)
        }
        let contents = string.substring(with: range)
        let source: String
        if case .triggeredLine(let trigger) = mode {
            guard selection.length == 0, selection.location == NSMaxRange(range) else { throw InputError.noTrigger }
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
