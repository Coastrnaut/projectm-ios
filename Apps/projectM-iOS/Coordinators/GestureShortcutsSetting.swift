// GestureShortcutsSetting.swift — UIX-006-R5, R8, R9: the "Gesture shortcuts" switch and mapping (Settings →
// Performance; specs/290-uix-006-touch-gesture-mapping, contract G4; research UIX-006-D6, D7).
//
// One String key, `settings.gestures.shortcuts` (the configuration's JSON; absent → off with the default mapping;
// written on change only). A preference: backed up with the library settings (FILE-005 `includedKeys`), erased with
// the Settings category (FILE-011), removed by `-uitestResetNotice`. Every write first asks the scene lock
// (SHOW-015 / SCN-015 `refusesEdit()`); performing a mapped action never does.
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class GestureShortcutsSetting {
    static let key = "settings.gestures.shortcuts"
    static let title = "Gesture shortcuts"
    static let footer = "Gestures on the visualization run the chosen action without showing the controls. When one touch matches several gestures, a three-finger tap wins over a two-finger swipe, and a swipe over a two-finger tap; a gesture set to None hands over to the next. One-finger taps still show and hide the controls."
    static let voiceOverNote = "Paused while VoiceOver is on: VoiceOver uses these gestures."

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lock: SceneLock?

    private(set) var configuration: GestureShortcutConfiguration

    init(defaults: UserDefaults, lock: SceneLock? = nil) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: off, default mapping
        }
        self.defaults = defaults
        self.lock = lock
        configuration = GestureShortcutConfiguration(json: defaults.string(forKey: Self.key))
    }

    var isEnabled: Bool { configuration.isEnabled }

    func action(for gesture: PerformanceGesture) -> GestureAction { configuration.action(for: gesture) }

    /// R8: refused (unchanged, reported by the lock) while the scene is locked.
    func setEnabled(_ enabled: Bool) {
        guard enabled != configuration.isEnabled, lock?.refusesEdit() != true else { return }
        configuration.isEnabled = enabled
        save()
    }

    /// R8: refused (unchanged, reported by the lock) while the scene is locked.
    func setAction(_ action: GestureAction, for gesture: PerformanceGesture) {
        guard action != configuration.action(for: gesture), lock?.refusesEdit() != true else { return }
        configuration.set(action, for: gesture)
        save()
    }

    private func save() { defaults.set(configuration.json, forKey: Self.key) }
}
