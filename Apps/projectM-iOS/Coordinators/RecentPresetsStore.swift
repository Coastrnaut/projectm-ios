// RecentPresetsStore.swift — roadmap PRE-006 (specs/159-pre-006-recent-history; R1, R3, R8; research
// PRE-006-D1, D4; ADR-0055): the recently played list and its switch, in UserDefaults beside `favorites`
// and `lastPresetID`.
//
// * `recentPresets`: preset IDs only, most recent first, at most 50 (read leniently). No times.
// * `settings.recentPresets.enabled`: "Remember Recently Played"; absent means off (opt-in, integrator decision
//   2026-11-14). Turning it off removes
//   the list. An off switch found at launch (for example restored from a backup) removes any list too.
// * Nothing else is read or written: favorites, the last preset, the scope, tags and collections are
//   never touched here (R4).
import Foundation
import PresetLibrary

final class RecentPresetsStore {
    /// Equal to LibrarySettingsPolicy.recentPresetsKey (a test checks).
    static let historyKey = "recentPresets"
    /// Equal to LibrarySettingsPolicy.recentPresetsEnabledKey (a test checks).
    static let enabledKey = "settings.recentPresets.enabled"
    static let allKeys: [String] = [historyKey, enabledKey]

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if !isEnabled, defaults.object(forKey: Self.historyKey) != nil { defaults.removeObject(forKey: Self.historyKey) }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }   // absent: false; also reads "YES" from launch arguments
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { defaults.removeObject(forKey: Self.historyKey) }
        }
    }

    var history: RecentPresetHistory { RecentPresetHistory(storedValue: defaults.object(forKey: Self.historyKey)) }

    /// Moves `id` to the front and saves at once; nothing while the switch is off.
    @discardableResult
    func record(_ id: String) -> RecentPresetHistory {
        var updated = history
        guard isEnabled else { return updated }
        updated.record(id)
        defaults.set(updated.ids, forKey: Self.historyKey)
        return updated
    }

    /// Removes the list only (R4).
    func clear() { defaults.removeObject(forKey: Self.historyKey) }
}
