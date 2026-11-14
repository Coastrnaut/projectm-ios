// NoiseGateSetting.swift — AUD-011: the input noise gate the user sets in Settings (AUD-011-R3, R7,
// R8, R9; specs/091-aud-011-input-noise-gate, contract C5).
//
// Two global values: on/off (key `settings.noiseGate.enabled`, Bool, default off; not a Bool → off)
// and the open threshold in whole dBFS, −80…−20, default −50 (key
// `settings.noiseGate.thresholdDecibels`, a Double; absent, NaN or not a number → −50; out of range →
// clamped). They are user settings under FR-065 as amended by AUD-011-R8 and are not part of scenes
// or show cues. Both are mirrored into a `NoiseGateControl` that every analysis reader shares
// (`gated(_:)`); `AppCoordinator` sets the control's microphone flag when it starts a source, so the
// gate acts only on the Microphone source. It acts only on the analysis tap's copy: projectM, the
// audio-state indicator and playback never see it.
import AudioCore
import Foundation
import Observation

@MainActor
@Observable
final class NoiseGateSetting {
    static let enabledKey = "settings.noiseGate.enabled"
    static let thresholdKey = "settings.noiseGate.thresholdDecibels"
    static let defaultThreshold: Double = Double(NoiseGate.defaultThresholdDecibels)
    static let range: ClosedRange<Double> = Double(NoiseGate.minimumThresholdDecibels)...Double(NoiseGate.maximumThresholdDecibels)

    @ObservationIgnored private let defaults: UserDefaults
    /// Read by the analysis readers (any thread).
    @ObservationIgnored let control: NoiseGateControl

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            control.isEnabled = isEnabled
        }
    }

    /// Whole dBFS within `range`.
    var thresholdDecibels: Double {
        didSet {
            let valid = Self.validated(thresholdDecibels)
            // NaN != NaN, so a NaN is always replaced. Storing below is idempotent.
            if valid != thresholdDecibels || thresholdDecibels.isNaN { thresholdDecibels = valid }
            defaults.set(valid, forKey: Self.thresholdKey)
            control.openDecibels = Float(valid)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let storedEnabled = defaults.object(forKey: Self.enabledKey) as? Bool
        let storedThreshold = defaults.object(forKey: Self.thresholdKey) as? Double
        let enabled: Bool = storedEnabled ?? false
        let threshold: Double = Self.validated(storedThreshold ?? Self.defaultThreshold)
        isEnabled = enabled
        thresholdDecibels = threshold
        control = NoiseGateControl(isEnabled: enabled, isMicrophoneSource: false, openDecibels: Float(threshold))
    }

    /// The (trimmed) analysis tap seen through this gate; nil without a tap. One reader per consumer.
    func gated(_ reader: (any NormalizedPCMReader)?) -> (any NormalizedPCMReader)? {
        guard let reader else { return nil }
        return NoiseGateReader(reader, control: control)
    }

    /// NaN → −50; clamped; rounded to whole dB.
    static func validated(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultThreshold }
        let clamped: Double = min(max(value, range.lowerBound), range.upperBound)
        return clamped.rounded()
    }

    /// "−50 dBFS" (U+2212 minus sign; the range is all negative).
    static func text(for value: Double) -> String {
        let whole: Int = Int(validated(value))
        let magnitude: String = String(abs(whole))
        let sign: String = whole < 0 ? "\u{2212}" : ""
        let number: String = sign + magnitude
        return number + " dBFS"
    }
}
