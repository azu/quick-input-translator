import AppKit
import ApplicationServices
import TranslationCore

enum ExternalInputError: LocalizedError {
    case focus, role, readOnly, selection, contents

    var errorDescription: String? {
        switch self {
        case .focus: "Couldn’t find the focused input field."
        case .role: "This app doesn’t expose the focused area as an editable text field."
        case .readOnly: "Couldn’t confirm that this input field is editable."
        case .selection: "This input field doesn’t support reading or changing the cursor position."
        case .contents: "Couldn’t read the text in this input field."
        }
    }
}

@MainActor final class AccessibilityInput: InputAccess {
    enum FocusToken {
        case local(NSTextView, frontmostPID: pid_t?)
        case external(AXUIElement, pid: pid_t)
    }
    private typealias Capture = (focus: FocusToken, target: TextTarget, coordinates: TextCoordinates?)
    private var captured: Capture?
    private var expectedFocus: FocusToken?

    func clear() { captured = nil; expectedFocus = nil }
    func expectFocus(_ token: FocusToken) { expectedFocus = token }

    func focusToken(localWindow: NSWindow? = nil) throws -> FocusToken {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let window = localWindow ?? (frontmostPID == getpid() ? NSApp.keyWindow : nil)
        if let window, let view = window.firstResponder as? NSTextView {
            guard view.isEditable else { throw InputError.unsupported }
            return .local(view, frontmostPID: frontmostPID)
        }
        guard AXIsProcessTrusted() else { throw InputError.permission }
        guard let frontmostPID else { throw InputError.changed }
        let element = try focusedElement(in: frontmostPID)
        var owner: pid_t = 0
        AXUIElementGetPid(element, &owner)
        Diagnostics.event("focus.external", "app=\(NSRunningApplication(processIdentifier: frontmostPID)?.bundleIdentifier ?? "-") pid=\(frontmostPID) ax_pid=\(owner)")
        try ensureEditable(element)
        return .external(element, pid: frontmostPID)
    }

    func hasFocus(_ token: FocusToken) -> Bool {
        switch token {
        case .local(let view, let pid):
            return view.window?.firstResponder === view && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        case .external(let element, let pid):
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                && (try? focusedElement(in: pid)).map { CFEqual($0, element) } == true
        }
    }

    func selectCurrentLine() throws {
        defer { clear() }
        let target = try capture(mode: .selectionOrCurrentLine)
        guard let saved = captured else { throw InputError.changed }
        try validate(saved)
        try setRange(target.replacementRange, on: saved.focus)
        guard try selectedRange(saved.focus, preferred: [target.replacementRange]) == target.replacementRange else { throw InputError.unsupported }
    }

    func capture(mode: CaptureMode) throws -> TextTarget {
        let focus = try expectedFocus ?? focusToken()
        guard hasFocus(focus) else { throw InputError.changed }
        let target: TextTarget
        var coordinates: TextCoordinates?
        switch focus {
        case .local(let view, _):
            target = try TextViewInput.capture(view, mode: mode)
        case .external(let element, _):
            AXUIElementSetMessagingTimeout(element, 0.5)
            try ensureEditable(element)
            if let ranges = attribute(element, kAXSelectedTextRangesAttribute) as? [Any], ranges.count > 1 {
                throw InputError.unsupported
            }
            let text = try textValue(focus)
            let mapping = try AXTextCoordinates.read(element, displayed: text)
            coordinates = mapping
            let nativeSelection = try nativeSelectedRange(focus)
            let candidates = try mapping.displayedRanges(for: nativeSelection)
            let selectedText = attribute(element, kAXSelectedTextAttribute) as? String
            let matching = candidates.compactMap { range -> TextTarget? in
                if range.length > 0 {
                    guard let selectedText,
                          (try? mapping.matchesSelectedText(selectedText, range: range)) == true else { return nil }
                }
                return try? TextTarget(text: text, selection: range, mode: mode)
            }
            if matching.count == 1 {
                target = matching[0]
                break
            }
            guard matching.isEmpty else { throw InputError.unsupported }
            guard candidates.count == 1 || mode != .selectionOrCurrentLine else { throw InputError.unsupported }
            let selection = candidates[0]
            if selection.length > 0 {
                guard let selectedText,
                      try mapping.matchesSelectedText(selectedText, range: selection) else { throw InputError.unsupported }
            }
            do {
                target = try TextTarget(text: text, selection: selection, mode: mode)
            } catch InputError.noTrigger {
                if let trigger = mode.trigger {
                    Diagnostics.captureRejected(text: text, selection: selection, trigger: trigger,
                                                wholeInput: mode.isWholeInput)
                }
                throw InputError.noTrigger
            }
        }
        captured = (focus, target, coordinates)
        Diagnostics.event("capture.succeeded", "full_length=\(target.fullText.utf16.count) selection=\(target.originalSelection.location),\(target.originalSelection.length) replacement=\(target.replacementRange.location),\(target.replacementRange.length)")
        return target
    }

    func replace(_ target: TextTarget, with translation: String) async throws {
        guard let saved = captured, saved.target == target else { throw InputError.changed }
        try validate(saved)
        if case .local(let view, _) = saved.focus {
            try TextViewInput.replace(view, target: target, translation: translation)
            return
        }
        guard case .external(let element, let pid) = saved.focus else { throw InputError.unsupported }
        // Arc accepts AXSelectedText writes without changing the field. Use the
        // editor's normal paste path rather than trusting the setter's success.
        Diagnostics.event("replacement.planned", "method=paste pid=\(pid)")
        let clipboard = try ClipboardTransaction()
        var submitted = false
        do {
            try validate(saved)
            Diagnostics.event("selection.requested")
            try setRange(target.replacementRange, on: saved.focus)
            try await SelectionConfirmation.wait(for: target.replacementRange, from: target.originalSelection) {
                try self.selectedRange(saved.focus, preferred: [target.originalSelection, target.replacementRange])
            } validate: {
                guard self.hasFocus(saved.focus), try self.textValue(saved.focus) == target.fullText else {
                    throw InputError.changed
                }
            }
            let selected = attribute(element, kAXSelectedTextAttribute) as? String
            let expectedSelection = (target.fullText as NSString).substring(with: target.replacementRange)
            let matches = try selected.map {
                try saved.coordinates?.matchesSelectedText($0, range: target.replacementRange)
                    ?? ($0 == expectedSelection)
            } ?? false
            Diagnostics.event("selection.confirmed", "selected_text_available=\(selected != nil) selected_text_matches=\(matches) selected_length=\(selected?.utf16.count ?? -1) expected_length=\(expectedSelection.utf16.count) indexed_length=\(saved.coordinates?.indexedLength ?? -1)")
            if selected != nil { guard matches else { throw InputError.changed } }
            else if saved.coordinates?.isIdentity == false { throw InputError.unsupported }
            try Task.checkCancellation()
            guard hasFocus(saved.focus), try textValue(saved.focus) == target.fullText,
                  try selectedRange(saved.focus, preferred: [target.replacementRange]) == target.replacementRange else { throw InputError.changed }
            let modifiers: CGEventFlags = [.maskControl, .maskShift, .maskCommand, .maskAlternate]
            guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else { throw InputError.changed }
            Diagnostics.event("paste.preflight", "post_event_allowed=\(CGPreflightPostEventAccess())")
            try clipboard.stage(translation)
            guard clipboard.isUnchanged() else { throw ClipboardError.changed }
            try await PasteShortcut.post(to: pid, onSubmit: {
                submitted = true
                Diagnostics.event("replacement.submitted", "method=paste pid=\(pid)")
            })
        } catch {
            Diagnostics.failure(submitted ? "replacement.submit_failed" : "replacement.preparation_failed", error)
            guard !submitted else { throw InputError.unconfirmed }
            if hasFocus(saved.focus), (try? textValue(saved.focus)) == target.fullText,
               (try? selectedRange(saved.focus, preferred: [target.replacementRange])) == target.replacementRange {
                try? setRange(target.originalSelection, on: saved.focus)
            }
            clipboard.restoreIfUnchanged()
            throw error
        }
        try await ReplacementConfirmation.wait(original: target.fullText, expected: target.replacing(with: translation)) {
            try self.textValue(saved.focus)
        } hasFocus: {
            self.hasFocus(saved.focus)
        } onObservation: { state in
            Diagnostics.event("replacement.observed", "state=\(state.rawValue)")
        }
        clipboard.restoreIfUnchanged()
    }

    func bounds(for focus: FocusToken, range requestedRange: NSRange? = nil) -> NSRect? {
        switch focus {
        case .local(let view, _):
            return view.firstRect(forCharacterRange: requestedRange ?? view.selectedRange(), actualRange: nil)
        case .external(let element, _):
            guard let range = requestedRange ?? (try? selectedRange(focus)) else { return nil }
            let indexed = (try? captured?.coordinates?.indexedRange(for: range)) ?? range
            var cfRange = CFRange(location: indexed.location, length: indexed.length)
            guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                             parameter, &result) == .success,
                  let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(unsafeDowncast(result, to: AXValue.self), .cgRect, &rect) else { return nil }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    private func validate(_ saved: Capture) throws {
        guard hasFocus(saved.focus),
              saved.target.matches(text: try textValue(saved.focus), selection: try selectedRange(saved.focus, preferred: [saved.target.originalSelection])) else {
            throw InputError.changed
        }
        if case .external(let element, _) = saved.focus { try ensureEditable(element) }
    }

    private func ensureEditable(_ element: AXUIElement) throws {
        if attribute(element, kAXSubroleAttribute, reportFailure: false) as? String == kAXSecureTextFieldSubrole { throw InputError.secure }
        let role = attribute(element, kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { throw ExternalInputError.role }
        let editable = attribute(element, kAXIsEditableAttribute, reportFailure: false) as? Bool
        var valueSettable: DarwinBoolean = false
        let canSetValue = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success
            && valueSettable.boolValue
        guard editable != false, editable == true || canSetValue else { throw ExternalInputError.readOnly }
        var settable: DarwinBoolean = false
        let selectionCapability = AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable)
        guard selectionCapability == .success, settable.boolValue else {
            Diagnostics.event("selection.unavailable", "capability_ax=\(selectionCapability.rawValue) settable=\(settable.boolValue)")
            throw ExternalInputError.selection
        }
    }

    private func focusedElement(in pid: pid_t) throws -> AXUIElement {
        try AXFocusedElement.read(in: pid)
    }

    private func attribute(_ element: AXUIElement, _ name: String, reportFailure: Bool = true) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            if reportFailure { Diagnostics.event("ax.read_failed", "attribute=\(name) ax=\(result.rawValue)") }
            return nil
        }
        return value
    }

    private func textValue(_ focus: FocusToken) throws -> String {
        if case .local(let view, _) = focus { return view.string }
        guard case .external(let element, _) = focus, let value = attribute(element, kAXValueAttribute) as? String else {
            throw ExternalInputError.contents
        }
        return value
    }

    private func selectedRange(_ focus: FocusToken, preferred: [NSRange] = []) throws -> NSRange {
        let native = try nativeSelectedRange(focus)
        guard let coordinates = captured?.coordinates else { return native }
        let candidates = try coordinates.displayedRanges(for: native)
        if candidates.count == 1 { return candidates[0] }
        if let match = preferred.first(where: { candidates.contains($0) }) { return match }
        throw InputError.unsupported
    }

    private func nativeSelectedRange(_ focus: FocusToken) throws -> NSRange {
        if case .local(let view, _) = focus { return view.selectedRange() }
        guard case .external(let element, _) = focus, let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { throw ExternalInputError.selection }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { throw InputError.invalidRange }
        return NSRange(location: range.location, length: range.length)
    }

    private func setRange(_ range: NSRange, on focus: FocusToken) throws {
        if case .local(let view, _) = focus { view.setSelectedRange(range); return }
        guard case .external(let element, _) = focus else { throw InputError.unsupported }
        let indexed = try captured?.coordinates?.indexedRange(for: range) ?? range
        var cfRange = CFRange(location: indexed.location, length: indexed.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { throw InputError.invalidRange }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        Diagnostics.event("selection.setter_returned", "ax=\(result.rawValue)")
        guard result == .success else {
            throw InputError.unsupported
        }
    }

}
