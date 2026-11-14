// InputTrimSetting.swift — AUD-008: the input trim the user sets in Settings (AUD-008-R4, R6, R8,
// R11; specs/086-aud-008-input-trim, contract C5).
//
// One global value in whole dB, −12…+24, default 0, key `settings.inputTrim.decibels` (a Double; absent,
// NaN or not a number → 0; out of range → clamped). It is a user setting under FR-065 as amended by
// AUD-008-R6, and it is not part of scenes or show cues. The value is mirrored into an
// `InputTrimControl` that every analysis reader shares (`trimmed(_:)`), so a change reaches the running
// analysis at its next read without restarting the source or the visual. The trim acts only on the
// analysis tap's copy: projectM, the audio-state indicator and playback never see it.
import AudioCore
import Foundation
import Observation

@MainActor
@Observable
final class InputTrimSetting {
    static let decibelsKey = "settings.inputTrim.decibels"
    static let range: ClosedRange<Double> = Double(InputTrim.minimumDecibels)...Double(InputTrim.maximumDecibels)

    @ObservationIgnored private let defaults: UserDefaults
    /// Read by the analysis readers (any thread).
    @ObservationIgnored let control: InputTrimControl

    /// Whole dB within `range`.
    var decibels: Double {
        didSet {
            let valid = Self.validated(decibels)
            // NaN != NaN, so a NaN is always replaced. Storing below is idempotent whether or not
            // this assignment re-enters the observer.
            if valid != decibels || decibels.isNaN { decibels = valid }
            defaults.set(valid, forKey: Self.decibelsKey)
            control.decibels = Float(valid)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.decibelsKey) as? Double
        let initial = Self.validated(stored ?? 0)
        decibels = initial
        control = InputTrimControl(decibels: Float(initial))
    }

    /// Back to 0 dB (stored).
    func reset() { decibels = 0 }

    /// The analysis tap seen through this trim; nil without a tap. One reader per consumer.
    func trimmed(_ tap: (any NormalizedPCMReader)?) -> (any NormalizedPCMReader)? {
        guard let tap else { return nil }
        return InputTrimReader(tap, control: control)
    }

    /// NaN → 0; clamped; rounded to whole dB.
    static func validated(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        let clamped: Double = min(max(value, range.lowerBound), range.upperBound)
        return clamped.rounded()
    }

    /// "+6 dB", "0 dB", "−12 dB" (U+2212 minus sign).
    static func text(for value: Double) -> String {
        let whole: Int = Int(validated(value))
        let magnitude: String = String(abs(whole))
        let sign: String
        if whole > 0 {
            sign = "+"
        } else if whole < 0 {
            sign = "\u{2212}"
        } else {
            sign = ""
        }
        return sign + magnitude + " dB"
    }
}
