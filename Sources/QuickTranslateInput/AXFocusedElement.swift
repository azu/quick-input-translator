import ApplicationServices
import TranslationCore

@MainActor enum AXFocusedElement {
    static func read(in pid: pid_t) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        if result != .success {
            Diagnostics.event("ax.read_failed", "attribute=AXFocusedUIElement ax=\(result.rawValue)")
        }
        return try decode(result: result, value: value)
    }

    static func decode(result: AXError, value: CFTypeRef?) throws -> AXUIElement {
        // The trust preflight may still return true after an app bundle update.
        // Preserve the API's explicit denial rather than reporting missing focus.
        if result == .apiDisabled { throw InputError.permission }
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw ExternalInputError.focus
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
