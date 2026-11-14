// SensorySafetySetting.swift — ACC-012-R1, R8, R11: the stored sensory safety profile
// (specs/121-acc-012-sensory-safety-profile, data-model.md "Storage"; ADR-0049).
//
// Four user settings under FR-065 as amended by ACC-012-R8, local only:
// * `settings.sensorySafety.profile` (String: standard/reduced/strict/custom; absent or unknown → standard);
// * `settings.sensorySafety.flashesPerSecond` (Int 1…3; absent → Reduced's 2);
// * `settings.sensorySafety.riseLimit` (Double per second; 0 = none; absent → Reduced's 0.25);
// * `settings.sensorySafety.intensityLimit` (Double 0…1; absent → Reduced's 0.5).
// The three custom keys are written only once Custom is chosen (the first time from the preset selected
// before, clarify Q3) or a custom value is edited. Out-of-range values are clamped by
// `SensorySafetyLimits`. All four are cleared by `-uitestResetNotice` (AppSettings.allKeys), allowed in
// `scripts/run_device_tests.py` and included in the FILE-005 backup. Never in scenes, cues, MIDI, OSC or
// modulation (ACC-012-R11).
import FlashSafety
import Foundation
import Observation

@MainActor
@Observable
final class SensorySafetySetting {
    static let profileKey = "settings.sensorySafety.profile"
    static let flashesPerSecondKey = "settings.sensorySafety.flashesPerSecond"
    static let riseLimitKey = "settings.sensorySafety.riseLimit"
    static let intensityLimitKey = "settings.sensorySafety.intensityLimit"
    static let allKeys: [String] = [profileKey, flashesPerSecondKey, riseLimitKey, intensityLimitKey]

    /// The custom controls' grids (ACC-005 steps): rise 0 (none) or 0.05…1.0 by 0.05; intensity 0…1 by 0.05.
    static let riseSliderRange: ClosedRange<Double> = 0...1
    static let riseStep: Double = 0.05
    static let intensityStep: Double = 0.05

    @ObservationIgnored private let defaults: UserDefaults

    /// The chosen profile; choosing Custom the first time seeds it from the previous preset.
    var preset: SensorySafetyPreset {
        didSet {
            guard preset != oldValue else { return }
            if preset == .custom && !hasStoredCustom {
                custom = SensorySafetyProfile.limits(of: oldValue, custom: custom)
                storeCustom()
            }
            defaults.set(preset.rawValue, forKey: Self.profileKey)
        }
    }

    /// The custom limits (stored when edited).
    private(set) var custom: SensorySafetyLimits

    var profile: SensorySafetyProfile { SensorySafetyProfile(preset: preset, custom: custom) }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        preset = defaults.string(forKey: Self.profileKey).flatMap(SensorySafetyPreset.init(rawValue:)) ?? .standard
        custom = Self.storedCustom(defaults)
    }

    // MARK: Custom values (each setter writes the clamped value)

    var flashesPerSecond: Int {
        get { custom.flashesPerSecond }
        set { updateCustom(SensorySafetyLimits(flashesPerSecond: newValue, riseLimitPerSecond: custom.riseLimitPerSecond,
                                               intensityLimit: custom.intensityLimit)) }
    }

    /// The rise limit as the slider sees it: 0 = none.
    var riseLimitSliderValue: Double {
        get { custom.riseLimitPerSecond ?? 0 }
        set {
            let rise: Double? = newValue < SensorySafetyLimits.riseRange.lowerBound / 2 ? nil : newValue
            updateCustom(SensorySafetyLimits(flashesPerSecond: custom.flashesPerSecond, riseLimitPerSecond: rise,
                                             intensityLimit: custom.intensityLimit))
        }
    }

    var intensityLimit: Double {
        get { custom.intensityLimit }
        set { updateCustom(SensorySafetyLimits(flashesPerSecond: custom.flashesPerSecond,
                                               riseLimitPerSecond: custom.riseLimitPerSecond, intensityLimit: newValue)) }
    }

    private func updateCustom(_ limits: SensorySafetyLimits) {
        custom = limits
        storeCustom()
    }

    private var hasStoredCustom: Bool { defaults.object(forKey: Self.flashesPerSecondKey) != nil }

    private func storeCustom() {
        defaults.set(custom.flashesPerSecond, forKey: Self.flashesPerSecondKey)
        defaults.set(custom.riseLimitPerSecond ?? 0, forKey: Self.riseLimitKey)
        defaults.set(custom.intensityLimit, forKey: Self.intensityLimitKey)
    }

    private static func storedCustom(_ defaults: UserDefaults) -> SensorySafetyLimits {
        let fallback: SensorySafetyLimits = .reduced
        let flashes: Int = (defaults.object(forKey: flashesPerSecondKey) as? Int) ?? fallback.flashesPerSecond
        let storedRise: Double? = defaults.object(forKey: riseLimitKey) as? Double
        let rise: Double? = storedRise.map { (value: Double) -> Double? in value > 0 ? value : nil } ?? fallback.riseLimitPerSecond
        let intensity: Double = (defaults.object(forKey: intensityLimitKey) as? Double) ?? fallback.intensityLimit
        return SensorySafetyLimits(flashesPerSecond: flashes, riseLimitPerSecond: rise, intensityLimit: intensity)
    }

    // MARK: Text (typed steps)

    /// "1 flash per second" / "3 flashes per second".
    static func flashesText(_ flashes: Int) -> String {
        let noun: String = flashes == 1 ? "flash" : "flashes"
        return String(flashes) + " " + noun + " per second"
    }

    /// "None" or "0.25 per second".
    static func riseText(_ rise: Double?) -> String {
        guard let rise else { return "None" }
        let number: String = rise.formatted(.number.precision(.fractionLength(2)))
        return number + " per second"
    }

    /// "50%".
    static func intensityText(_ limit: Double) -> String {
        let percent: Int = Int((limit * 100).rounded())
        return String(percent) + "%"
    }
}
