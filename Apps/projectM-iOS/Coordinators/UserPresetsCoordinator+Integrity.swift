// UserPresetsCoordinator+Integrity.swift — roadmap PRE-018 (R6-R8, R10; research D4): the user preset side
// of the library check's fixes. Each goes through UserPresetLibrary (an actor, off the main thread) and
// ends with a refresh, so My Presets and the library list what is now true. Nothing announces here.
import Foundation
import PresetLibrary

extension UserPresetsCoordinator {
    /// Every user preset record, in any state.
    var allRecords: [UserPreset] { playable + pending + needsUnlock + quarantined }

    /// R7: writes a missing or damaged stored copy back from bytes with the record's checksum.
    func relink(_ id: String, with data: Data) async -> PresetRelinkOutcome {
        let outcome = await library.relink(id, with: data)
        if case .restored = outcome { await refresh() }
        return outcome
    }

    /// R6, R8: moves a waiting or playable preset to Quarantine (after the screen's confirmation).
    func quarantineByUser(_ id: String, detail: String) async -> Bool {
        let moved = await library.quarantineByUser(id, detail: detail)
        if moved { await refresh() }
        return moved
    }

    /// R10: removes a preset and its stored copy (after the screen's confirmation), with its tags and
    /// adjustments, through My Presets' own Remove. True when the record is gone.
    func removeForIntegrity(_ id: String) async -> Bool {
        if allRecords.isEmpty { await refresh() }
        guard let record = allRecords.first(where: { (preset: UserPreset) -> Bool in preset.id == id }) else { return false }
        await remove(record)
        return !allRecords.contains { (preset: UserPreset) -> Bool in preset.id == id }
    }
}
