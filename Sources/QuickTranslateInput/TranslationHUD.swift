import AppKit

@MainActor final class TranslationHUD {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    private let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 72),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let label = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var dismissal: Task<Void, Never>?

    init() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.maximumNumberOfLines = 3
        let row = NSStackView(views: [spinner, label])
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func show(_ message: String, working: Bool, near anchor: NSRect? = nil) {
        dismissal?.cancel()
        label.stringValue = message
        if working { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if let anchor, !anchor.isEmpty {
            position(near: NSPoint(x: anchor.minX, y: anchor.minY))
        } else if !panel.isVisible {
            position(near: NSEvent.mouseLocation)
        }
        panel.orderFrontRegardless()
        if !working {
            dismissal = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(5))
                    panel.orderOut(nil)
                } catch {}
            }
        }
    }

    func hide() { dismissal?.cancel(); panel.orderOut(nil) }

    private func position(near point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let x = min(max(point.x, bounds.minX + 8), bounds.maxX - panel.frame.width - 8)
        let y = min(max(point.y - panel.frame.height - 10, bounds.minY + 8), bounds.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
