import AppKit
import SwiftUI
import TranslationCore

/// SwiftUI's segmented Picker doesn't propagate disabled state to individual segments.
@MainActor struct TriggerPicker: NSViewRepresentable {
    @Binding var selection: TranslationTrigger
    let unavailable: TranslationTrigger
    let label: String

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: TranslationTrigger.allCases.map(\.rawValue),
                                         trackingMode: .selectOne, target: context.coordinator,
                                         action: #selector(Coordinator.select(_:)))
        control.setAccessibilityLabel(label)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, trigger) in TranslationTrigger.allCases.enumerated() {
            control.setEnabled(trigger != unavailable, forSegment: index)
        }
        control.selectedSegment = TranslationTrigger.allCases.firstIndex(of: selection) ?? -1
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<TranslationTrigger>
        init(selection: Binding<TranslationTrigger>) { self.selection = selection }

        @objc func select(_ control: NSSegmentedControl) {
            let choices = TranslationTrigger.allCases
            let index = control.selectedSegment
            guard choices.indices.contains(index), control.isEnabled(forSegment: index) else { return }
            selection.wrappedValue = choices[index]
            control.selectedSegment = choices.firstIndex(of: selection.wrappedValue) ?? -1
        }
    }
}
