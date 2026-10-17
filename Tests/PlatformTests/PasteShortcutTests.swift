import CoreGraphics
import Testing
@testable import QuickTranslateInput

@Test @MainActor func pasteIsSentOnlyOnceToSpecifiedProcess() async throws {
    var posted: [(CGEvent, pid_t)] = []
    var submissions = 0
    try await PasteShortcut.post(to: 123, onSubmit: { submissions += 1 }) { event, pid in
        #expect(submissions == 1)
        posted.append((event, pid))
    }
    #expect(submissions == 1)
    #expect(posted.map { $0.0.type } == [.keyDown, .keyUp])
    #expect(posted.allSatisfy { $0.1 == 123 })
    #expect(posted.allSatisfy { $0.0.getIntegerValueField(.keyboardEventKeycode) == 9 })
    #expect(posted.allSatisfy { $0.0.flags == .maskCommand })
}

@Test @MainActor func cancelledPasteStillReleasesKeyInSameProcess() async {
    var posted: [(CGEventType, pid_t)] = []
    let cancelled = await Task { @MainActor in
        do {
            try await PasteShortcut.post(to: 123) { } send: { event, pid in
                posted.append((event.type, pid))
                if event.type == .keyDown { withUnsafeCurrentTask { $0?.cancel() } }
            }
            return false
        } catch is CancellationError {
            return true
        } catch {
            Issue.record("Unexpected error: \(error)")
            return false
        }
    }.value
    #expect(cancelled)
    #expect(posted.map { $0.0 } == [.keyDown, .keyUp])
    #expect(posted.allSatisfy { $0.1 == 123 })
}
