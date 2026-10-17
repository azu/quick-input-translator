import AppKit
import Testing
@testable import QuickTranslateInput

@Test @MainActor func restoresAllFormatsAndItems() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let first = NSPasteboardItem()
    first.setString("original", forType: .string)
    let richData = Data("{\\rtf1 original}".utf8)
    first.setData(richData, forType: .rtf)
    let second = NSPasteboardItem()
    second.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("test.custom"))
    #expect(board.writeObjects([first, second]))
    let transaction = try ClipboardTransaction(pasteboard: board)
    try transaction.stage("translated")
    #expect(board.string(forType: .string) == "translated")
    transaction.restoreIfUnchanged()
    #expect(board.pasteboardItems?.count == 2)
    #expect(board.pasteboardItems?[0].string(forType: .string) == "original")
    #expect(board.pasteboardItems?[0].data(forType: .rtf) == richData)
    #expect(board.pasteboardItems?[1].data(forType: NSPasteboard.PasteboardType("test.custom")) == Data([1, 2, 3]))
}

@Test @MainActor func doesNotOverwriteConcurrentCopy() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("original", forType: .string)
    let transaction = try ClipboardTransaction(pasteboard: board)
    try transaction.stage("translated")
    board.clearContents()
    board.setString("new user copy", forType: .string)
    #expect(!transaction.isUnchanged())
    transaction.restoreIfUnchanged()
    #expect(board.string(forType: .string) == "new user copy")
}

@Test @MainActor func restoresEmptyClipboard() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.clearContents()
    let transaction = try ClipboardTransaction(pasteboard: board)
    try transaction.stage("translated")
    transaction.restoreIfUnchanged()
    #expect(board.pasteboardItems?.isEmpty ?? true)
}

@Test @MainActor func refusesToStageAfterAnotherCopy() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("original", forType: .string)
    let transaction = try ClipboardTransaction(pasteboard: board)
    board.clearContents()
    board.setString("new user copy", forType: .string)
    #expect(throws: (any Error).self) { try transaction.stage("translated") }
    #expect(board.string(forType: .string) == "new user copy")
}
