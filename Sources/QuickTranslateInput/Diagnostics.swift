import Foundation
import OSLog
import TranslationCore

/// Only technical metadata belongs here. Never pass text, titles, URLs or error descriptions.
@MainActor enum Diagnostics {
    private static let logger = Logger(subsystem: "info.efcl.quick-translate-input", category: "translation")
    private static var operation = "-"
    private static var lastRejectedCapture: String?

    static func begin() {
        operation = String(UUID().uuidString.prefix(8))
        lastRejectedCapture = nil
        event("trigger.detected")
    }

    static func event(_ stage: String, _ metadata: String = "") {
        logger.notice("op=\(operation, privacy: .public) stage=\(stage, privacy: .public) \(metadata, privacy: .public)")
    }

    static func failure(_ stage: String, _ error: Error) {
        let type = String(reflecting: Swift.type(of: error))
        let code = (error as NSError).code
        logger.error("op=\(operation, privacy: .public) stage=\(stage, privacy: .public) error_type=\(type, privacy: .public) code=\(code)")
    }

    /// Called only after TextTarget has validated the range and rejected the trigger.
    static func captureRejected(text: String, selection: NSRange, trigger: TranslationTrigger) {
        let metadata = triggerMetadata(text: text, selection: selection, trigger: trigger)
        guard metadata != lastRejectedCapture else { return }
        lastRejectedCapture = metadata
        event("capture.trigger_mismatch", metadata)
    }

    /// The caller must first validate the range with TextTarget.
    private static func triggerMetadata(text: String, selection: NSRange, trigger: TranslationTrigger) -> String {
        let string = text as NSString
        var start = 0, end = 0, contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                            for: NSRange(location: selection.location, length: 0))
        let line = string.substring(with: NSRange(location: start, length: contentsEnd - start))
        let caretEnd = NSMaxRange(selection)
        let prefix = caretEnd <= contentsEnd
            ? string.substring(with: NSRange(location: start, length: caretEnd - start)) : ""
        return "full_length=\(string.length) selection=\(selection.location),\(selection.length) line=\(start),\(contentsEnd - start) selection_at_line_end=\(caretEnd == contentsEnd) marker_at_line_end=\(trigger.source(in: line) != nil) marker_at_caret=\(trigger.source(in: prefix) != nil) marker_before_whitespace=\(trigger.source(in: line.trimmingCharacters(in: .whitespaces)) != nil)"
    }
}
