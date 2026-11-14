// MotionFeedbackSetting.swift — FX-009: Trails as the user sets them in Settings → Trails (FX-009-R9, R11;
// specs/130-fx-009-motion-feedback, contracts/motion-feedback.md, research FX-009-D9).
//
// One global visual setting (not part of scenes or show cues): `settings.feedback.enabled` (Bool, absent → off) and
// `settings.feedback.halfLife` (Double seconds, absent, not a number or NaN → 0.20, out of range → the nearest bound).
// Every change calls `onChange`, through which `AppCoordinator` hands `effective(clamp:)` to the compositor-backed
// visuals (Camera, Photo, Video, Text); the native spectra and projectM have no trails. ACC-012: the sensory safety
// profile's intensity limit and Reduce flashing cap the length (`MotionFeedback.limited(by:)`, research FX-009-D6).
import Compositor
import FlashSafety
import Foundation
import Observation

@MainActor
@Observable
final class MotionFeedbackSetting {
    static let enabledKey = "settings.feedback.enabled"
    static let halfLifeKey = "settings.feedback.halfLife"
    static let allKeys: [String] = [enabledKey, halfLifeKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) user value.
    @ObservationIgnored var onChange: ((MotionFeedback) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(feedback)
        }
    }

    /// Seconds, 0.05…0.50.
    var halfLifeSeconds: Double {
        didSet {
            let valid: Double = MotionFeedback.clampHalfLife(halfLifeSeconds)
            if valid != halfLifeSeconds || halfLifeSeconds.isNaN {
                halfLifeSeconds = valid   // re-enters once with the valid value
                return
            }
            guard halfLifeSeconds != oldValue else { return }
            defaults.set(halfLifeSeconds, forKey: Self.halfLifeKey)
            onChange?(feedback)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        halfLifeSeconds = MotionFeedback.clampHalfLife(Self.readDouble(defaults, Self.halfLifeKey, MotionFeedback.defaultHalfLife))
    }

    /// The user's value.
    var feedback: MotionFeedback { MotionFeedback(isEnabled: isEnabled, halfLifeSeconds: halfLifeSeconds) }

    /// What the compositors apply under `clamp` (ACC-012; research FX-009-D6).
    func effective(clamp: SafetyClamp) -> MotionFeedback { feedback.limited(by: clamp) }

    /// Only a real Bool counts (a stored number or string reads as off).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → `fallback` (NaN is handled by the clamp).
    private static func readDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return fallback }
        return number.doubleValue
    }

    // MARK: - Readouts (typed steps)

    /// "0.20 s" (hundredths rounded half away from zero, so Strict's 0.125 s reads "0.13 s").
    static func halfLifeText(_ seconds: Double) -> String {
        let hundredths: Double = (seconds * 100).rounded()
        let number: String = (hundredths / 100).formatted(.number.precision(.fractionLength(2)))
        return number + " s"
    }

    /// What the safety caps leave, for the help line when they shorten the user's value ("" when unchanged).
    static func capText(user: MotionFeedback, effective: MotionFeedback) -> String {
        guard user.isEnabled else { return "" }
        if !effective.isActive { return "Your safety settings turn Trails off." }
        guard effective.halfLifeSeconds < user.halfLifeSeconds else { return "" }
        return "Your safety settings shorten Trails to " + halfLifeText(effective.halfLifeSeconds) + "."
    }
}
