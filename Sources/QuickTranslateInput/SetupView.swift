import SwiftUI
import Translation
import TranslationCore
import Carbon
@preconcurrency import ApplicationServices

@MainActor final class AppModel: ObservableObject {
    @Published var sample = "こんにちは。今日は良い天気です。"
    @Published var status = "Type a line-end or whole-input trigger to translate."
    @Published var shortcutReady = false
    @Published var modelStatus = "Checking languages…"
    @Published var languages: [Locale.Language] = []
    @Published var modelsInstalled = false
    @Published var canPrepare = false
    @Published var hasPermission = AXIsProcessTrusted()
    @Published var monitorReady = false
    @Published var externalInputStatus = "No input received from other apps yet."
    @Published var secureInput = IsSecureEventInputEnabled()
    @Published var sourceID: String {
        didSet {
            guard sourceID != oldValue else { return }
            defaults.set(sourceID, forKey: "translationSource"); languageChanged()
        }
    }
    @Published var targetID: String {
        didSet {
            guard targetID != oldValue else { return }
            defaults.set(targetID, forKey: "translationTarget"); languageChanged()
        }
    }
    @Published private(set) var trigger: TranslationTrigger
    @Published private(set) var wholeInputTrigger: TranslationTrigger
    private let defaults: UserDefaults
    var onStatusChange: ((String) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?
    var onTriggerChange: (() -> Void)?
    var onLanguageChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sourceID = defaults.string(forKey: "translationSource") ?? "ja"
        targetID = defaults.string(forKey: "translationTarget") ?? "system"
        let line = TranslationTrigger(rawValue: defaults.string(forKey: "translationTrigger") ?? "") ?? .dots
        let whole = TranslationTrigger(rawValue: defaults.string(forKey: "wholeInputTranslationTrigger") ?? "")
        trigger = line
        wholeInputTrigger = whole.flatMap { $0 != line ? $0 : nil } ?? (line == .colons ? .atSigns : .colons)
        defaults.set(trigger.rawValue, forKey: "translationTrigger")
        defaults.set(wholeInputTrigger.rawValue, forKey: "wholeInputTranslationTrigger")
    }

    func setLineTrigger(_ value: TranslationTrigger) {
        guard value != trigger, value != wholeInputTrigger else { return }
        trigger = value
        defaults.set(value.rawValue, forKey: "translationTrigger")
        onTriggerChange?()
    }

    func setWholeInputTrigger(_ value: TranslationTrigger) {
        guard value != wholeInputTrigger, value != trigger else { return }
        wholeInputTrigger = value
        defaults.set(value.rawValue, forKey: "wholeInputTranslationTrigger")
        onTriggerChange?()
    }

    var selectionID: [String] { [sourceID, targetID] }
    var systemTarget: Locale.Language? { TranslationLanguages.systemTarget(supported: languages) }
    var pairTitle: String {
        guard let pair = try? selectedLanguages() else { return "Choose translation languages" }
        return "\(TranslationLanguages.name(pair.source)) → \(TranslationLanguages.name(pair.target))"
    }

    func selectedLanguages() throws -> TranslationLanguages {
        guard let source = TranslationLanguages.match(sourceID, in: languages),
              let target = targetID == "system" ? systemTarget : TranslationLanguages.match(targetID, in: languages)
        else { throw ModelError.unsupported }
        return .init(source: source, target: target)
    }

    private func languageChanged() {
        modelsInstalled = false
        canPrepare = false
        modelStatus = "Checking languages…"
        onLanguageChange?()
    }

    func setStatus(_ message: String) {
        status = message
        onStatusChange?(message)
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(options)
        onPermissionChange?(hasPermission)
    }

    func checkPermission(force: Bool = false) {
        let secure = IsSecureEventInputEnabled()
        if secureInput != secure { secureInput = secure }
        let allowed = AXIsProcessTrusted()
        guard force || allowed != hasPermission else { return }
        hasPermission = allowed
        onPermissionChange?(allowed)
    }

    func loadLanguages() async {
        languages = await TranslationLanguages.available().sorted {
            TranslationLanguages.name($0).localizedStandardCompare(TranslationLanguages.name($1)) == .orderedAscending
        }
        await refresh()
    }

    func refresh() async {
        checkPermission(force: true)
        let selection = selectionID
        guard !languages.isEmpty else { return }
        guard let pair = try? selectedLanguages() else {
            modelStatus = "Selected language is unavailable"; canPrepare = false; modelsInstalled = false
            return
        }
        guard !pair.source.isEquivalent(to: pair.target) else {
            modelStatus = "Choose two different languages"; canPrepare = false; modelsInstalled = false
            return
        }
        let availability = await LanguageAvailability().status(from: pair.source, to: pair.target)
        guard selection == selectionID, !Task.isCancelled else { return }
        modelsInstalled = availability == .installed
        canPrepare = availability == .supported
        switch availability {
        case .installed: modelStatus = "Ready for translation"
        case .supported: modelStatus = "Language download required"
        case .unsupported: modelStatus = "This language pair is unavailable"
        @unknown default: modelStatus = "Language status is unavailable"
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var configuration: TranslationSession.Configuration?
    @State private var preparing = false
    @State private var preparationSelection: [String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Input Translator").font(.title2.weight(.semibold))
                        Text("Translate right where you’re writing.")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Translation") {
                    HStack(alignment: .bottom, spacing: 14) {
                        languagePicker("From", selection: $model.sourceID, includeSystem: false)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.bottom, 7)
                        languagePicker("To", selection: $model.targetID, includeSystem: true)
                    }
                    .disabled(preparing || model.languages.isEmpty)
                    Divider().padding(.vertical, 4)
                    HStack {
                        Label(model.modelStatus, systemImage: model.modelsInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(model.modelsInstalled ? Color.secondary : Color.primary)
                            .font(.callout)
                        Spacer()
                        if preparing { ProgressView().controlSize(.small) }
                        if !model.modelsInstalled {
                            Button(preparing ? "Preparing…" : "Prepare Languages") { prepare() }
                                .disabled(preparing || !model.canPrepare)
                        }
                    }
                    Divider().padding(.vertical, 4)
                    triggerPicker("Line-end trigger",
                                  selection: Binding(get: { model.trigger }, set: { model.setLineTrigger($0) }),
                                  unavailable: model.wholeInputTrigger)
                    Text("Type \(model.trigger.rawValue) at the end of a line. Only that line is replaced.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Also works with \(model.trigger.japaneseInputMarker) during Japanese input.")
                        .font(.caption).foregroundStyle(.secondary)
                    triggerPicker("Whole-input trigger",
                                  selection: Binding(get: { model.wholeInputTrigger }, set: { model.setWholeInputTrigger($0) }),
                                  unavailable: model.trigger)
                    Text("Type \(model.wholeInputTrigger.rawValue) at the end of the input field. The entire field is replaced.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Also works with \(model.wholeInputTrigger.japaneseInputMarker) during Japanese input.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                section("Access") {
                    HStack(spacing: 10) {
                        Image(systemName: model.hasPermission ? "checkmark.shield" : "lock")
                            .foregroundStyle(.secondary).font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.hasPermission ? "Accessibility enabled" : "Allow access to other apps")
                            Text(model.hasPermission ? "Ready to detect triggers in supported input fields." : "The test field below works without permission.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if !model.hasPermission {
                            Button("Allow Access") { model.requestPermission() }
                        }
                        Button("Open Settings") { openAccessibilitySettings() }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Try it").font(.headline)
                        Spacer()
                        Text("⌃⇧A selects the current line").font(.callout).foregroundStyle(.secondary)
                    }
                    TextEditor(text: $model.sample)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(height: 94)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .accessibilityLabel("Translation test field")
                    Text(model.status)
                        .font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Translation status: \(model.status)")
                }

                DisclosureGroup("Diagnostics") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Line selection shortcut: \(model.shortcutReady ? "registered" : "unavailable")")
                        Text("Trigger monitoring: \(model.monitorReady ? "active" : "inactive")")
                        Text(model.externalInputStatus)
                        if model.secureInput {
                            Label("Secure Input is blocking triggers in other apps.", systemImage: "exclamationmark.triangle")
                        }
                        Button("Refresh Status") { Task { await model.refresh() } }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout).foregroundStyle(.secondary)
                Text("On-device translation. Nothing is sent or posted. Pasting temporarily uses the clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 620, height: 690)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: model.selectionID) { await model.refresh() }
        .translationTask(configuration) { @Sendable session in
            do {
                try await session.prepareTranslation()
                await model.refresh()
                await MainActor.run {
                    if preparationSelection == model.selectionID {
                        model.setStatus("Languages are ready. Add a trigger to try translating.")
                    }
                }
            } catch {
                await MainActor.run {
                    if preparationSelection == model.selectionID {
                        model.setStatus("Couldn’t prepare languages: \(error.localizedDescription)")
                    }
                }
            }
            await MainActor.run { preparing = false }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10, content: content)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>, includeSystem: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                if includeSystem {
                    Text("System language\(model.systemTarget.map { " (\(TranslationLanguages.name($0)))" } ?? "")")
                        .tag("system")
                    Divider()
                }
                if !model.languages.contains(where: { $0.minimalIdentifier == selection.wrappedValue }),
                   selection.wrappedValue != "system" {
                    Text(TranslationLanguages.name(.init(identifier: selection.wrappedValue)))
                        .tag(selection.wrappedValue)
                }
                ForEach(model.languages, id: \.minimalIdentifier) { language in
                    Text(TranslationLanguages.name(language)).tag(language.minimalIdentifier)
                }
            }
            .labelsHidden().frame(maxWidth: .infinity)
            .accessibilityLabel(title == "From" ? "Source language" : "Target language")
        }
    }

    private func triggerPicker(_ title: String, selection: Binding<TranslationTrigger>,
                               unavailable: TranslationTrigger) -> some View {
        HStack {
            Text(title)
            Spacer()
            TriggerPicker(selection: selection, unavailable: unavailable, label: title)
            .frame(width: 240)
        }
    }

    private func prepare() {
        guard let pair = try? model.selectedLanguages(), model.canPrepare else { return }
        preparationSelection = model.selectionID
        preparing = true
        if configuration?.source == pair.source, configuration?.target == pair.target {
            configuration?.invalidate()
        } else {
            configuration = .init(source: pair.source, target: pair.target)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
