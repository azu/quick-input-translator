import AppKit
import ApplicationServices
import TranslationCore

@MainActor final class AccessibilityInput: InputAccess {
    struct FocusToken {
        fileprivate let element: AXUIElement
        fileprivate let pid: pid_t
    }
    private struct CapturedInput {
        let element: AXUIElement
        let pid: pid_t
        let target: TextTarget
    }
    private var captured: CapturedInput?
    private var expectedFocus: FocusToken?

    func clear() {
        captured = nil
        expectedFocus = nil
    }

    func focusToken() throws -> FocusToken {
        guard AXIsProcessTrusted() else { throw InputError.permission }
        let element = try focusedElement()
        try ensureEditable(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw InputError.changed }
        return FocusToken(element: element, pid: pid)
    }

    func hasFocus(_ token: FocusToken) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == token.pid
            && (try? focusedElement()).map { CFEqual($0, token.element) } == true
    }

    func expectFocus(_ token: FocusToken) { expectedFocus = token }

    func selectCurrentLine() throws {
        defer { clear() }
        let target = try capture(mode: .selectionOrCurrentLine)
        guard let saved = captured else { throw InputError.changed }
        try validate(saved)
        try setRange(target.replacementRange, on: saved.element)
        guard try selectedRange(saved.element) == target.replacementRange else { throw InputError.unsupported }
    }

    func capture(mode: CaptureMode) throws -> TextTarget {
        guard AXIsProcessTrusted() else { throw InputError.permission }
        let element = try focusedElement()
        if let expectedFocus {
            guard hasFocus(expectedFocus), CFEqual(element, expectedFocus.element) else { throw InputError.changed }
        }
        AXUIElementSetMessagingTimeout(element, 0.5)
        try ensureEditable(element)
        let text = try textValue(element)
        let selection = try selectedRange(element)
        // Do not silently use the primary selection of a multi-selection editor.
        if let ranges = attribute(element, kAXSelectedTextRangesAttribute as String) as? [Any], ranges.count > 1 {
            throw InputError.unsupported
        }
        let target = try TextTarget(text: text, selection: selection, mode: mode)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw InputError.changed
        }
        captured = CapturedInput(element: element, pid: pid, target: target)
        return target
    }

    func replace(_ target: TextTarget, with translation: String) async throws {
        guard let saved = captured, saved.target == target else { throw InputError.changed }
        try validate(saved)
        let clipboard = try ClipboardTransaction()
        try clipboard.stage(translation)
        var posted = false
        do {
            // Recheck after saving clipboard data: providers may take time to supply it.
            try validate(saved)
            try setRange(target.replacementRange, on: saved.element)
            guard try selectedRange(saved.element) == target.replacementRange,
                  try textValue(saved.element) == target.fullText,
                  try isFocused(saved) else { throw InputError.changed }
            let modifiers: CGEventFlags = [.maskControl, .maskShift, .maskCommand, .maskAlternate]
            guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else {
                throw InputError.changed
            }
            guard clipboard.isUnchanged() else { throw ClipboardError.changed }
            try postPaste()
            posted = true
        } catch {
            if !posted {
                // Restore selection only if it is still the one we set on the same text.
                if (try? isFocused(saved)) == true,
                   (try? textValue(saved.element)) == target.fullText,
                   (try? selectedRange(saved.element)) == target.replacementRange {
                    try? setRange(target.originalSelection, on: saved.element)
                }
                clipboard.restoreIfUnchanged()
            }
            throw error
        }

        let expected = target.replacing(with: translation)
        // Restore only once the target has consumed the staged text, never after a fixed delay.
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(20))
            guard (try? isFocused(saved)) == true else { throw InputError.unconfirmed }
            if (try? textValue(saved.element)) == expected {
                clipboard.restoreIfUnchanged()
                return
            }
        }
        throw InputError.unconfirmed
    }

    private func validate(_ saved: CapturedInput) throws {
        guard try isFocused(saved),
              saved.target.matches(text: try textValue(saved.element), selection: try selectedRange(saved.element)) else {
            throw InputError.changed
        }
        try ensureEditable(saved.element)
    }

    private func isFocused(_ saved: CapturedInput) throws -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.pid else { return false }
        return CFEqual(try focusedElement(), saved.element)
    }

    private func ensureEditable(_ element: AXUIElement) throws {
        if attribute(element, kAXSubroleAttribute as String) as? String == kAXSecureTextFieldSubrole as String {
            throw InputError.secure
        }
        let role = attribute(element, kAXRoleAttribute as String) as? String
        guard [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role ?? "") else {
            throw InputError.unsupported
        }
        let editable = attribute(element, kAXIsEditableAttribute as String) as? Bool
        var valueSettable: DarwinBoolean = false
        let canSetValue = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success
            && valueSettable.boolValue
        guard editable != false, editable == true || canSetValue else { throw InputError.unsupported }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue else { throw InputError.unsupported }
    }

    private func focusedElement() throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.5)
        guard let value = attribute(system, kAXFocusedUIElementAttribute as String),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw InputError.unsupported }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func textValue(_ element: AXUIElement) throws -> String {
        guard let value = attribute(element, kAXValueAttribute as String) as? String else { throw InputError.unsupported }
        return value
    }

    private func selectedRange(_ element: AXUIElement) throws -> NSRange {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute as String),
              CFGetTypeID(value) == AXValueGetTypeID() else { throw InputError.unsupported }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            throw InputError.invalidRange
        }
        return NSRange(location: range.location, length: range.length)
    }

    private func setRange(_ range: NSRange, on element: AXUIElement) throws {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw InputError.unsupported
        }
    }

    private func postPaste() throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw InputError.unsupported
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
