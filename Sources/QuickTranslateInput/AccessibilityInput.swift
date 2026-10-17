import AppKit
import ApplicationServices
import TranslationCore

@MainActor final class AccessibilityInput: InputAccess {
    enum FocusToken {
        case local(NSTextView, frontmostPID: pid_t?)
        case external(AXUIElement, pid: pid_t)
    }
    private var captured: (focus: FocusToken, target: TextTarget)?
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
        let element = try focusedElement()
        try ensureEditable(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, frontmostPID == pid else { throw InputError.changed }
        return .external(element, pid: pid)
    }

    func hasFocus(_ token: FocusToken) -> Bool {
        switch token {
        case .local(let view, let pid):
            return view.window?.firstResponder === view && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        case .external(let element, let pid):
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                && (try? focusedElement()).map { CFEqual($0, element) } == true
        }
    }

    func selectCurrentLine() throws {
        defer { clear() }
        let target = try capture(mode: .selectionOrCurrentLine)
        guard let saved = captured else { throw InputError.changed }
        try validate(saved)
        try setRange(target.replacementRange, on: saved.focus)
        guard try selectedRange(saved.focus) == target.replacementRange else { throw InputError.unsupported }
    }

    func capture(mode: CaptureMode) throws -> TextTarget {
        let focus = try expectedFocus ?? focusToken()
        guard hasFocus(focus) else { throw InputError.changed }
        let target: TextTarget
        switch focus {
        case .local(let view, _):
            target = try TextViewInput.capture(view, mode: mode)
        case .external(let element, _):
            AXUIElementSetMessagingTimeout(element, 0.5)
            try ensureEditable(element)
            if let ranges = attribute(element, kAXSelectedTextRangesAttribute) as? [Any], ranges.count > 1 {
                throw InputError.unsupported
            }
            target = try TextTarget(text: textValue(focus), selection: selectedRange(focus), mode: mode)
        }
        captured = (focus, target)
        return target
    }

    func replace(_ target: TextTarget, with translation: String) async throws {
        guard let saved = captured, saved.target == target else { throw InputError.changed }
        try validate(saved)
        if case .local(let view, _) = saved.focus {
            try TextViewInput.replace(view, target: target, translation: translation)
            return
        }
        let clipboard = try ClipboardTransaction()
        try clipboard.stage(translation)
        do {
            try validate(saved)
            try setRange(target.replacementRange, on: saved.focus)
            guard try selectedRange(saved.focus) == target.replacementRange,
                  try textValue(saved.focus) == target.fullText, hasFocus(saved.focus) else { throw InputError.changed }
            let modifiers: CGEventFlags = [.maskControl, .maskShift, .maskCommand, .maskAlternate]
            guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else { throw InputError.changed }
            guard clipboard.isUnchanged() else { throw ClipboardError.changed }
            try postPaste()
        } catch {
            if hasFocus(saved.focus), (try? textValue(saved.focus)) == target.fullText,
               (try? selectedRange(saved.focus)) == target.replacementRange {
                try? setRange(target.originalSelection, on: saved.focus)
            }
            clipboard.restoreIfUnchanged()
            throw error
        }
        let expected = target.replacing(with: translation)
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(20))
            guard hasFocus(saved.focus) else { throw InputError.unconfirmed }
            if (try? textValue(saved.focus)) == expected {
                clipboard.restoreIfUnchanged()
                return
            }
        }
        throw InputError.unconfirmed
    }

    func bounds(for focus: FocusToken) -> NSRect? {
        switch focus {
        case .local(let view, _):
            return view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil)
        case .external(let element, _):
            guard let range = try? selectedRange(focus) else { return nil }
            var cfRange = CFRange(location: range.location, length: range.length)
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

    private func validate(_ saved: (focus: FocusToken, target: TextTarget)) throws {
        guard hasFocus(saved.focus),
              saved.target.matches(text: try textValue(saved.focus), selection: try selectedRange(saved.focus)) else {
            throw InputError.changed
        }
        if case .external(let element, _) = saved.focus { try ensureEditable(element) }
    }

    private func ensureEditable(_ element: AXUIElement) throws {
        if attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { throw InputError.secure }
        let role = attribute(element, kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { throw InputError.unsupported }
        let editable = attribute(element, kAXIsEditableAttribute) as? Bool
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
        guard let value = attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw InputError.unsupported
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func textValue(_ focus: FocusToken) throws -> String {
        if case .local(let view, _) = focus { return view.string }
        guard case .external(let element, _) = focus, let value = attribute(element, kAXValueAttribute) as? String else {
            throw InputError.unsupported
        }
        return value
    }

    private func selectedRange(_ focus: FocusToken) throws -> NSRange {
        if case .local(let view, _) = focus { return view.selectedRange() }
        guard case .external(let element, _) = focus, let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { throw InputError.unsupported }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { throw InputError.invalidRange }
        return NSRange(location: range.location, length: range.length)
    }

    private func setRange(_ range: NSRange, on focus: FocusToken) throws {
        if case .local(let view, _) = focus { view.setSelectedRange(range); return }
        guard case .external(let element, _) = focus else { throw InputError.unsupported }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw InputError.unsupported
        }
    }

    private func postPaste() throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw InputError.unsupported }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
