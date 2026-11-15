// CountdownOverlayStore.swift — the countdown overlay's settings in the app's settings (MED-012-R10; data-model
// "CountdownOverlaySettings").
//
// One UserDefaults key, `settings.countdown.overlay`, holds `CountdownOverlaySettings.encodedForStorage()` (JSON,
// `"version": 1`). Missing → the defaults (off, 5:00); damaged → the defaults and the key is removed; a newer version
// → the defaults, the key left untouched. A backed-up preference (FILE-005), erased with Settings (FILE-011), removed
// by `-uitestResetNotice` through `AppSettings.allKeys`. The running state is never stored. It stays on the device.
import Foundation
import TextLayer

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct CountdownOverlayStore: @unchecked Sendable {
    static let key = "settings.countdown.overlay"

    let defaults: UserDefaults

    func load() -> CountdownOverlaySettings {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        switch CountdownOverlaySettings.decodeStored(data) {
        case .settings(let settings): return settings
        case .unsupportedVersion: return .default
        case .damaged:
            defaults.removeObject(forKey: Self.key)
            return .default
        }
    }

    func save(_ settings: CountdownOverlaySettings) {
        defaults.set(settings.encodedForStorage(), forKey: Self.key)
    }
}
