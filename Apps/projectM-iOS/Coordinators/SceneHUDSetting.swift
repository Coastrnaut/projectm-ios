// SceneHUDSetting.swift — UIX-013-R1, R11: the "Show HUD" preference (Settings → Performance; specs/233-uix-013-
// performance-hud, contract C5).
//
// One Bool, key `settings.visualizer.sceneHUD` (absent → off; written on change only). A preference, not a device
// capability: backed up with the library settings (FILE-005 `includedKeys`), erased with the Settings category
// (FILE-011), removed by `-uitestResetNotice`.
import Foundation
import Observation

@MainActor
@Observable
final class SceneHUDSetting {
    static let key = "settings.visualizer.sceneHUD"
    static let title = "Show HUD"
    static let footer = "Shows the current and next cue, the tempo and the audio source at the top of this screen. The HUD is never on an external display, in recordings or in saved frames."

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool {
        didSet { if isEnabled != oldValue { defaults.set(isEnabled, forKey: Self.key) } }
    }

    init(defaults: UserDefaults) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: off
        }
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.key)
    }
}
