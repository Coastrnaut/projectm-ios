// RecordingTimedStop.swift — REC-008 (specs/180-rec-008-timed-stop, contract C3, research REC-008-D4, D5): the
// recording lengths and the stored preference (Settings → Stop recording after).
//
// The length becomes the recording's `RecordingSettings.maxDurationSeconds` (media time on the REC-006 grid), so
// the recorder writes exactly the frames below it and finishes off the frame loop. One String, key
// `settings.recording.timedStop` (`off`, `10`, `30`, `60`, `300`; absent or unknown → Off; nothing stored until
// changed). A preference: backed up with the library settings (FILE-005 `includedKeys`), erased with the Settings
// category, removed by `-uitestResetNotice`. DEBUG `-uitestTimedStop <raw>` sets it at launch (UI tests).
import Foundation
import Observation

/// REC-008-R1: Off (default), 10 s, 30 s, 1 min, 5 min.
enum RecordingTimedStopLength: String, CaseIterable, Sendable {
    case off = "off"
    case ten = "10"
    case thirty = "30"
    case oneMinute = "60"
    case fiveMinutes = "300"

    static let defaultLength: RecordingTimedStopLength = .off

    var seconds: Int {
        switch self {
        case .off: 0
        case .ten: 10
        case .thirty: 30
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }

    /// "Off", "10 seconds", "1 minute", "5 minutes".
    var title: String {
        switch self {
        case .off: "Off"
        case .ten, .thirty: "\(seconds) seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        }
    }

    /// REC-008-R7: the notice of a timed stop (row X13).
    var stoppedNotice: String { Self.stoppedPrefix + title + "." }

    static let stoppedPrefix = "Recording stopped after "

    /// The length as the indicator shows it ("0:10", "5:00"); nil for Off.
    var indicatorText: String? {
        seconds > 0 ? VideoRecordingCoordinator.elapsedText(Double(seconds)) : nil
    }
}

@MainActor
@Observable
final class RecordingTimedStopSetting {
    static let key = "settings.recording.timedStop"
    static let sectionTitle = "Stop recording after"
    static let footer = "A recording stops by itself at this length and is offered as usual. Stop ends it earlier."

    @ObservationIgnored private let defaults: UserDefaults

    var length: RecordingTimedStopLength {
        didSet { defaults.set(length.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults, arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: Off
        }
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestTimedStop"), i + 1 < arguments.count,
           let length = RecordingTimedStopLength(rawValue: arguments[i + 1]) {
            defaults.set(length.rawValue, forKey: Self.key)
        }
        #endif
        self.defaults = defaults
        length = Self.stored(in: defaults)
    }

    /// The stored length, Off when absent or unknown.
    static func stored(in defaults: UserDefaults) -> RecordingTimedStopLength {
        defaults.string(forKey: key).flatMap(RecordingTimedStopLength.init(rawValue:)) ?? .defaultLength
    }
}
