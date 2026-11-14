// ChannelSelectionSetting.swift — AUD-009: the analysis channel the user chooses in Settings
// (AUD-009-R5, R6, R8, R10; specs/089-aud-009-channel-selection, contracts C4, C5).
//
// One global mode, default Mix, key `settings.analysisChannel.mode` (a String: mix, left, right, mid,
// side; missing or unknown → Mix). It is a user setting under FR-065 as amended by AUD-009-R6, and it
// is not part of scenes or show cues. The mode is mirrored into a `ChannelSelectionControl` that every
// analysis reader shares (`selected(_:)`), so a change reaches the running analysis at its next read.
// The selection acts only on the analysis tap's copy, inside the input trim: projectM, the audio-state
// indicator and playback never see it.
import AudioCore
import Foundation
import Observation

@MainActor
@Observable
final class ChannelSelectionSetting {
    static let modeKey = "settings.analysisChannel.mode"

    @ObservationIgnored private let defaults: UserDefaults
    /// Read by the analysis readers (any thread).
    @ObservationIgnored let control: ChannelSelectionControl

    var mode: AnalysisChannelMode {
        didSet {
            defaults.set(mode.storedValue, forKey: Self.modeKey)
            control.mode = mode
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored: String? = defaults.object(forKey: Self.modeKey) as? String
        let initial = AnalysisChannelMode(storedValue: stored)
        mode = initial
        control = ChannelSelectionControl(mode: initial)
    }

    /// The analysis tap seen through this selection; nil without a tap. One reader per consumer.
    func selected(_ tap: (any NormalizedPCMReader)?) -> (any NormalizedPCMReader)? {
        guard let tap else { return nil }
        return ChannelSelectionReader(tap, control: control)
    }

    /// The segment's short title.
    static func title(for mode: AnalysisChannelMode) -> String {
        switch mode {
        case .mix: return "Mix"
        case .left: return "Left"
        case .right: return "Right"
        case .mid: return "Mid"
        case .side: return "Side"
        }
    }

    /// What VoiceOver reads for the segment and the readout.
    static func spokenName(for mode: AnalysisChannelMode) -> String {
        switch mode {
        case .mix: return "Stereo mix"
        default: return title(for: mode)
        }
    }
}
