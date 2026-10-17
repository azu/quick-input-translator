import ApplicationServices
import TranslationCore

@MainActor enum AXTextCoordinates {
    static func read(_ element: AXUIElement, displayed: String) throws -> TextCoordinates {
        let length = displayed.utf16.count
        func read(_ length: Int) -> String? {
            var range = CFRange(location: 0, length: length)
            guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                              parameter, &result) == .success else { return nil }
            return result as? String
        }
        if let indexed = read(length) {
            return try TextCoordinates(displayed: displayed, indexed: indexed)
        }
        // Unsupported range reads retain the existing AXValue coordinate system.
        guard length > 0, read(1) != nil else { return try TextCoordinates(displayed: displayed, indexed: displayed) }
        // The browser may count fewer characters than AXValue, due to generated
        // paragraph separators. Locate the supported endpoint without editing.
        var lower = 1, upper = length - 1
        while lower < upper {
            let middle = lower + (upper - lower + 1) / 2
            if read(middle) != nil { lower = middle } else { upper = middle - 1 }
        }
        guard let indexed = read(lower) else { throw InputError.unsupported }
        return try TextCoordinates(displayed: displayed, indexed: indexed)
    }
}
