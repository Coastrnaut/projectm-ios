// TextOverlayStore.swift — the Text visual's message and style in the app's settings (MED-009-R10,
// R12; research MED-009-D9; spec Clarifications).
//
// One UserDefaults key, `settings.text.overlay`, holds `TextOverlaySpec.encodedForStorage()` (JSON,
// `"version": 1`). Reading: missing → the default spec; damaged → the default spec and the key is
// removed; a newer version → the default spec, the key left untouched (the next edit overwrites
// it, as for any setting). The value is a "user setting" in the FR-065 list; it stays on the
// device (no network, MED-009-R15).
import Foundation
import TextLayer

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct TextOverlayStore: @unchecked Sendable {
    static let key = "settings.text.overlay"

    let defaults: UserDefaults

    /// The stored spec, or the default.
    func load() -> TextOverlaySpec {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        switch TextOverlaySpec.decodeStored(data) {
        case .spec(let spec): return spec
        case .unsupportedVersion: return .default
        case .damaged:
            defaults.removeObject(forKey: Self.key)
            return .default
        }
    }

    func save(_ spec: TextOverlaySpec) {
        defaults.set(spec.encodedForStorage(), forKey: Self.key)
    }

    /// Reset Text: the defaults, stored (MED-009-R12).
    func reset() {
        save(.default)
    }
}
