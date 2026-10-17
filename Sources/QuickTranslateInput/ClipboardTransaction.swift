import AppKit

@MainActor final class ClipboardTransaction {
    private let pasteboard: NSPasteboard
    private let savedItems: [[NSPasteboard.PasteboardType: Data]]
    private let originalChangeCount: Int
    private var stagedChangeCount: Int?

    init(pasteboard: NSPasteboard = .general) throws {
        self.pasteboard = pasteboard
        self.originalChangeCount = pasteboard.changeCount
        self.savedItems = try (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { throw ClipboardError.readFailed }
                values[type] = data
            }
            return values
        }
    }

    func stage(_ text: String) throws {
        guard pasteboard.changeCount == originalChangeCount else { throw ClipboardError.changed }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            stagedChangeCount = pasteboard.changeCount
            restoreIfUnchanged()
            throw ClipboardError.writeFailed
        }
        stagedChangeCount = pasteboard.changeCount
    }

    func isUnchanged() -> Bool { stagedChangeCount == pasteboard.changeCount }

    func restoreIfUnchanged() {
        guard isUnchanged() else { return }
        pasteboard.clearContents()
        let items = savedItems.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
        stagedChangeCount = nil
    }
}

enum ClipboardError: LocalizedError {
    case readFailed, writeFailed, changed
    var errorDescription: String? {
        switch self {
        case .readFailed: "Pasting stopped because the original clipboard contents couldn’t be preserved."
        case .writeFailed: "Couldn’t copy the translation to the clipboard."
        case .changed: "Pasting stopped because the clipboard changed."
        }
    }
}
