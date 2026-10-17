import AppKit
import Testing
import TranslationCore
@testable import QuickTranslateInput

@MainActor private final class ChangeDelegate: NSObject, NSTextViewDelegate {
    var changes = 0
    func textDidChange(_ notification: Notification) { changes += 1 }
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
