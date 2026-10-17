import AppKit
import TranslationCore

/// Access our own editor directly; AX IPC to our own main thread is unreliable.
@MainActor enum TextViewInput {
    static func capture(_ view: NSTextView, mode: CaptureMode) throws -> TextTarget {
        guard view.isEditable, !(view.delegate is NSSecureTextField) else { throw InputError.unsupported }
        let target = try TextTarget(text: view.string, selection: view.selectedRange(), mode: mode)
        if mode.trigger != nil, view.hasMarkedText() {
            // Commit through the input client, never by sending Return to an arbitrary app.
            view.unmarkText()
            view.inputContext?.discardMarkedText()
            guard view.string == target.fullText else { throw InputError.changed }
            view.setSelectedRange(NSRange(location: NSMaxRange(target.replacementRange), length: 0))
            return try TextTarget(text: view.string, selection: view.selectedRange(), mode: mode)
        }
        return target
    }

    static func replace(_ view: NSTextView, target: TextTarget, translation: String) throws {
        guard target.matches(text: view.string, selection: view.selectedRange()), !view.hasMarkedText() else {
            throw InputError.changed
        }
        guard view.isEditable, let storage = view.textStorage else {
            throw InputError.unsupported
        }
        view.allowsUndo = true
        view.breakUndoCoalescing()
        guard view.shouldChangeText(in: target.replacementRange, replacementString: translation) else {
            throw InputError.unsupported
        }
        storage.replaceCharacters(in: target.replacementRange, with: translation)
        view.didChangeText()
        view.setSelectedRange(NSRange(location: target.replacementRange.location + (translation as NSString).length, length: 0))
        guard view.string == target.replacing(with: translation) else { throw InputError.unconfirmed }
    }
}
