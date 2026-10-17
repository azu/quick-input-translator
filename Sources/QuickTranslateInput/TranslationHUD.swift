import AppKit

@MainActor final class TranslationHUD {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 28, height: 28),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let label = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let icon = NSImageView()
    private let background = NSVisualEffectView()
    private var anchor: NSRect?
    private var dismissal: Task<Void, Never>?

    init() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        panel.contentView = background
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 3
        label.isHidden = true
        icon.isHidden = true
        let row = NSStackView(views: [spinner, icon, label])
        row.detachesHiddenViews = true
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func showProgress(_ message: String, near anchor: NSRect? = nil) {
        show(message, state: .working, near: anchor)
    }

    func showSuccess() { show("Translated", state: .success) }

    func showFailure(_ message: String) { show(message, state: .failure) }

    private enum State { case working, success, failure }

    private func show(_ message: String, state: State, near requestedAnchor: NSRect? = nil) {
        dismissal?.cancel()
        if let requestedAnchor, requestedAnchor.height > 0 {
            anchor = requestedAnchor
        } else if !panel.isVisible {
            anchor = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        }
        let working = state == .working
        let failure = state == .failure
        let size = failure ? NSSize(width: 360, height: 72) : NSSize(width: 28, height: 28)
        panel.setContentSize(size)
        panel.title = message
        panel.setAccessibilityLabel(message)
        label.stringValue = message
        label.isHidden = !failure
        spinner.isHidden = !working
        spinner.setAccessibilityLabel(message)
        icon.isHidden = working
        icon.image = NSImage(systemSymbolName: failure ? "exclamationmark" : "checkmark",
                             accessibilityDescription: message)
        icon.contentTintColor = failure ? .systemOrange : .systemGreen
        background.layer?.cornerRadius = failure ? 12 : 14
        if working { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        position()
        panel.orderFrontRegardless()
        if !working {
            dismissal = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(failure ? 5 : 1))
                    hide()
                } catch {}
            }
        }
    }

    func hide() { dismissal?.cancel(); panel.orderOut(nil); anchor = nil }

    private func position() {
        guard let anchor else { return }
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        panel.setFrameOrigin(Self.origin(above: anchor, size: panel.frame.size, within: bounds))
    }

    static func origin(above anchor: NSRect, size: NSSize, within bounds: NSRect) -> NSPoint {
        let x = min(max(anchor.midX - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let above = anchor.maxY + 6
        let preferredY = above + size.height <= bounds.maxY - 8 ? above : anchor.minY - size.height - 6
        let y = min(max(preferredY, bounds.minY + 8), bounds.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }
}
