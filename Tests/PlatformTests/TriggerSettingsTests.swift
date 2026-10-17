import Foundation
import Testing
import TranslationCore
@testable import QuickTranslateInput

@Test @MainActor func triggerSettingsPersistIndependentlyAndRejectDuplicates() throws {
    let name = "TriggerSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let model = AppModel(defaults: defaults)
    #expect(model.trigger == .dots)
    #expect(model.wholeInputTrigger == .colons)
    var changes = 0
    model.onTriggerChange = { changes += 1 }
    model.setLineTrigger(.colons)
    model.setWholeInputTrigger(.dots)
    model.setLineTrigger(.dots)
    #expect(model.trigger == .dots)
    #expect(model.wholeInputTrigger == .colons)
    #expect(changes == 0)

    model.setWholeInputTrigger(.atSigns)
    model.setLineTrigger(.semicolons)
    #expect(changes == 2)
    let restored = AppModel(defaults: defaults)
    #expect(restored.trigger == .semicolons)
    #expect(restored.wholeInputTrigger == .atSigns)
    restored.setWholeInputTrigger(.dots)
    #expect(restored.trigger == .semicolons)
    #expect(restored.wholeInputTrigger == .dots)
}

@Test(arguments: TranslationTrigger.allCases)
@MainActor func existingLineTriggerSurvivesWholeInputMigration(line: TranslationTrigger) throws {
    let name = "TriggerMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(line.rawValue, forKey: "translationTrigger")
    let model = AppModel(defaults: defaults)
    #expect(model.trigger == line)
    #expect(model.wholeInputTrigger == (line == .colons ? .atSigns : .colons))
    let restored = AppModel(defaults: defaults)
    #expect(restored.trigger == line)
    #expect(restored.wholeInputTrigger == model.wholeInputTrigger)
}

@Test(arguments: ["invalid", "..."])
@MainActor func corruptOrConflictingWholeInputSettingIsRepaired(saved: String) throws {
    let name = "TriggerRepairTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("...", forKey: "translationTrigger")
    defaults.set(saved, forKey: "wholeInputTranslationTrigger")
    let model = AppModel(defaults: defaults)
    #expect(model.trigger == .dots)
    #expect(model.wholeInputTrigger == .colons)
    #expect(defaults.string(forKey: "wholeInputTranslationTrigger") == ":::")
}
