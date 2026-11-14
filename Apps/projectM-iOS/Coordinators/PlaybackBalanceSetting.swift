// PlaybackBalanceSetting.swift — AUD-010: the left/right balance of what In-App Playback plays aloud
// (AUD-010-R1, R6, R7; specs/138-aud-010-channel-balance, contract C2).
//
// One global value, −1 (full left) … +1 (full right), default 0, key `settings.playbackBalance.position`
// (a Double; missing or not a number → 0; validated with `MonitorBalance`: clamped, whole percent,
// ±3 % centre detent). It is a user setting under FR-065 like AUD-008-R6, not part of scenes, show cues
// or the undo history. `onChange` pushes it into `InAppPlaybackSource.monitorBalance`, which changes
// only what is heard: the analysis, projectM and recordings get the unbalanced PCM (AUD-010-R3).
import AudioCore
import CaptureKit
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackBalanceSetting {
    static let positionKey = "settings.playbackBalance.position"
    static let range: ClosedRange<Double> = MonitorBalance.range

    @ObservationIgnored private let defaults: UserDefaults
    /// Called with every stored value (AppCoordinator: into the In-App Playback source).
    @ObservationIgnored var onChange: (@MainActor (Double) -> Void)?

    var position: Double {
        didSet {
            let valid: Double = MonitorBalance.validated(position)
            // NaN != NaN, so a NaN is always replaced. @Observable's generated setter re-enters this
            // observer on that assignment, which then stores and pushes the valid value once.
            if valid != position || position.isNaN {
                position = valid
                return
            }
            defaults.set(valid, forKey: Self.positionKey)
            onChange?(valid)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored: Double? = defaults.object(forKey: Self.positionKey) as? Double
        position = MonitorBalance.validated(stored ?? 0)
    }

    /// Back to centre (stored).
    func reset() { position = 0 }

    /// AUD-010-R6: only In-App Playback is played aloud by the app.
    nonisolated static func isAvailable(for mode: AudioSourceMode?) -> Bool {
        mode == .inAppPlayback
    }

    /// "Centered", "30% left", "30% right".
    nonisolated static func text(for value: Double) -> String {
        let percent: Int = Int((MonitorBalance.validated(value) * 100).rounded())
        if percent == 0 { return "Centered" }
        let side: String = percent < 0 ? "left" : "right"
        return String(abs(percent)) + "% " + side
    }

    /// VoiceOver: "centered", "30 percent left", "30 percent right".
    nonisolated static func spokenText(for value: Double) -> String {
        let percent: Int = Int((MonitorBalance.validated(value) * 100).rounded())
        if percent == 0 { return "centered" }
        let side: String = percent < 0 ? "left" : "right"
        return String(abs(percent)) + " percent " + side
    }
}
