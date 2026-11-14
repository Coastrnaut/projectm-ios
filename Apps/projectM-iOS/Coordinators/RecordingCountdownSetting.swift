// RecordingCountdownSetting.swift — REC-007-R8: the recording countdown preference (Settings → Recording
// countdown; specs/175-rec-007-countdown, contract C4).
//
// One String, key `settings.recording.countdown` (`off`, `3`, `5`, `10`; absent or unknown → Off; nothing
// stored until changed). A preference, not a device capability: backed up with the library settings
// (FILE-005 `includedKeys`), erased with the Settings category, removed by `-uitestResetNotice`.
import Foundation
import Observation

@MainActor
@Observable
final class RecordingCountdownSetting {
    static let key = "settings.recording.countdown"
    static let sectionTitle = "Recording countdown"
    static let footer = "Record starts after this countdown. Tap Record or Cancel during the countdown to stop it; nothing is recorded until it ends."

    @ObservationIgnored private let defaults: UserDefaults

    var length: RecordingCountdownLength {
        didSet { defaults.set(length.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: Off
        }
        self.defaults = defaults
        length = Self.stored(in: defaults)
    }

    /// The stored length, Off when absent or unknown.
    static func stored(in defaults: UserDefaults) -> RecordingCountdownLength {
        defaults.string(forKey: key).flatMap(RecordingCountdownLength.init(rawValue:)) ?? .defaultLength
    }
}
