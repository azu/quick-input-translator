import AppKit
import Testing
import TranslationCore
@testable import QuickTranslateInput

@MainActor private final class ChangeDelegate: NSObject, NSTextViewDelegate {
    var changes = 0
    let undo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
    func textDidChange(_ notification: Notification) { changes += 1 }
}

@Test @MainActor func wholeInputReplacementUndoesOnceWithoutUndoingEarlierTyping() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let delegate = ChangeDelegate()
    delegate.undo.groupsByEvent = false
    view.delegate = delegate
    view.allowsUndo = true
    let source = "😀前の行\n\n日本語"
    view.string = source
    view.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    delegate.undo.beginUndoGrouping()
    view.insertText(":::", replacementRange: view.selectedRange())
    delegate.undo.endUndoGrouping()
    let original = view.string
    let target = try TextViewInput.capture(view, mode: .triggeredField(.colons))
    delegate.undo.beginUndoGrouping()
    try TextViewInput.replace(view, target: target, translation: "First line\n\nJapanese")
    delegate.undo.endUndoGrouping()
    #expect(view.string == "First line\n\nJapanese")
    #expect(delegate.undo.canUndo)
    delegate.undo.undo()
    #expect(view.string == original)
    #expect(view.string == source + ":::")
    #expect(delegate.undo.canUndo)
    delegate.undo.undo()
    #expect(view.string == source)
}

@Test @MainActor func wholeInputCommitsCompositionAtTheEndOfMultipleLines() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "最初の行\n"
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.setMarkedText("日本語。。。", selectedRange: NSRange(location: 6, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    let target = try TextViewInput.capture(view, mode: .triggeredField(.dots))
    #expect(!view.hasMarkedText())
    #expect(target.sourceText == "最初の行\n日本語")
    #expect(view.string == "最初の行\n日本語。。。")
    try TextViewInput.replace(view, target: target, translation: "First line\nJapanese")
    #expect(view.string == "First line\nJapanese")
}

@Test @MainActor func nativeEditorReplacementNotifiesBindingAndPreservesOtherLines() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "前\n日本語...\n後"
    view.setSelectedRange(NSRange(location: 8, length: 0))
    let delegate = ChangeDelegate()
    view.delegate = delegate
    let target = try TextViewInput.capture(view, mode: .triggeredLine(.dots))
    try TextViewInput.replace(view, target: target, translation: "Japanese")
    #expect(view.string == "前\nJapanese\n後")
    #expect(delegate.changes == 1)
    #expect(view.selectedRange() == NSRange(location: 10, length: 0))
}

@Test @MainActor func nativeEditorCommitsJapaneseMarkedTextWithoutReturn() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "前\n"
    view.setSelectedRange(NSRange(location: 2, length: 0))
    view.setMarkedText("日本語。。。", selectedRange: NSRange(location: 6, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(view.hasMarkedText())
    let target = try TextViewInput.capture(view, mode: .triggeredLine(.dots))
    #expect(!view.hasMarkedText())
    #expect(target.sourceText == "日本語")
    #expect(view.string == "前\n日本語。。。")
    try TextViewInput.replace(view, target: target, translation: "Japanese")
    #expect(view.string == "前\nJapanese")
}

@Test @MainActor func missingTriggerKeepsCompositionMarked() {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.setMarkedText("日本語。。", selectedRange: NSRange(location: 5, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(throws: InputError.noTrigger) { try TextViewInput.capture(view, mode: .triggeredLine(.dots)) }
    #expect(view.hasMarkedText())
    #expect(view.string == "日本語。。")
}

@Test @MainActor func newCompositionPreventsStaleNativeReplacement() throws {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "日本語..."
    view.setSelectedRange(NSRange(location: 6, length: 0))
    let target = try TextViewInput.capture(view, mode: .triggeredLine(.dots))
    view.setMarkedText("追記", selectedRange: NSRange(location: 2, length: 0),
                       replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(throws: InputError.changed) { try TextViewInput.replace(view, target: target, translation: "Japanese") }
    #expect(view.string == "日本語...追記")
}
