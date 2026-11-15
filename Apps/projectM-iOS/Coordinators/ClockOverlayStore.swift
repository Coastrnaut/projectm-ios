// ClockOverlayStore.swift — the clock overlay's settings in the app's settings (MED-011-R8, R9; data-model
// "ClockOverlaySettings").
//
// One UserDefaults key, `settings.clock.overlay`, holds `ClockOverlaySettings.encodedForStorage()` (JSON,
// `"version": 1`). Missing → the defaults (off); damaged → the defaults and the key is removed; a newer version →
// the defaults, the key left untouched. A backed-up preference (FILE-005), erased with Settings (FILE-011),
// removed by `-uitestResetNotice` through `AppSettings.allKeys`. It stays on the device.
import Foundation
import TextLayer

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct ClockOverlayStore: @unchecked Sendable {
    static let key = "settings.clock.overlay"

    let defaults: UserDefaults

    func load() -> ClockOverlaySettings {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        switch ClockOverlaySettings.decodeStored(data) {
        case .settings(let settings): return settings
        case .unsupportedVersion: return .default
        case .damaged:
            defaults.removeObject(forKey: Self.key)
            return .default
        }
    }

    func save(_ settings: ClockOverlaySettings) {
        defaults.set(settings.encodedForStorage(), forKey: Self.key)
    }
}
