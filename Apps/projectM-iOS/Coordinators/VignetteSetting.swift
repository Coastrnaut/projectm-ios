// VignetteSetting.swift — FX-015: the vignette as the user sets it in Settings → Vignette (FX-015-R8, R9;
// specs/305-fx-015-vignette, contracts/vignette.md C4, research FX-015-D6; ADR-0116).
//
// One global visual setting: `settings.vignette.enabled` (Bool, absent → off), `settings.vignette.intensity` (0…1,
// absent/NaN → 0.5), `settings.vignette.softness` (0.1…0.9, absent/NaN → 0.5), `settings.vignette.centerX` and
// `settings.vignette.centerY` (fractions of the frame, 0 = left/top, absent/NaN → 0.5); out of range → the nearest bound.
// Values are written only when changed. Every change calls `onChange`, through which `AppCoordinator` hands the value to
// the compositor-backed visuals (Camera, Photo, Video, Text). No safety cap (darkening adds no brightness; ADR-0116).
// Scenes and effect-chain presets with an `fx.vignette` entry set these values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class VignetteSetting {
    static let enabledKey = "settings.vignette.enabled"
    static let intensityKey = "settings.vignette.intensity"
    static let softnessKey = "settings.vignette.softness"
    static let centerXKey = "settings.vignette.centerX"
    static let centerYKey = "settings.vignette.centerY"
    static let allKeys: [String] = [enabledKey, intensityKey, softnessKey, centerXKey, centerYKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((Vignette) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(vignette)
        }
    }

    /// Fraction, 0…1.
    var intensity: Double {
        didSet {
            if let valid = Self.repaired(intensity, Vignette.clampIntensity) {
                intensity = valid   // re-enters once with the valid value
                return
            }
            stored(intensity, oldValue, Self.intensityKey)
        }
    }

    /// Fraction, 0.1…0.9.
    var softness: Double {
        didSet {
            if let valid = Self.repaired(softness, Vignette.clampSoftness) {
                softness = valid   // re-enters once with the valid value
                return
            }
            stored(softness, oldValue, Self.softnessKey)
        }
    }

    /// Fraction of the width, 0 (left)…1.
    var centerX: Double {
        didSet {
            if let valid = Self.repaired(centerX, Vignette.clampCenter) {
                centerX = valid   // re-enters once with the valid value
                return
            }
            stored(centerX, oldValue, Self.centerXKey)
        }
    }

    /// Fraction of the height, 0 (top)…1.
    var centerY: Double {
        didSet {
            if let valid = Self.repaired(centerY, Vignette.clampCenter) {
                centerY = valid   // re-enters once with the valid value
                return
            }
            stored(centerY, oldValue, Self.centerYKey)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        intensity = Vignette.clampIntensity(Self.readDouble(defaults, Self.intensityKey, Vignette.defaultIntensity))
        softness = Vignette.clampSoftness(Self.readDouble(defaults, Self.softnessKey, Vignette.defaultSoftness))
        centerX = Vignette.clampCenter(Self.readDouble(defaults, Self.centerXKey, Vignette.defaultCenter))
        centerY = Vignette.clampCenter(Self.readDouble(defaults, Self.centerYKey, Vignette.defaultCenter))
    }

    /// The user's value (what the compositors apply).
    var vignette: Vignette {
        Vignette(isEnabled: isEnabled, intensity: intensity, softness: softness, centerX: centerX, centerY: centerY)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: Vignette) {
        if intensity != value.intensity { intensity = value.intensity }
        if softness != value.softness { softness = value.softness }
        if centerX != value.centerX { centerX = value.centerX }
        if centerY != value.centerY { centerY = value.centerY }
        isEnabled = value.isEnabled
    }

    /// The valid value when `value` is out of range or NaN, else nil.
    private static func repaired(_ value: Double, _ clamp: (Double) -> Double) -> Double? {
        let valid: Double = clamp(value)
        return valid != value || value.isNaN ? valid : nil
    }

    /// A valid Double changed: stored and sent.
    private func stored(_ value: Double, _ oldValue: Double, _ key: String) {
        guard value != oldValue else { return }
        defaults.set(value, forKey: key)
        onChange?(vignette)
    }

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

    /// "50%" (whole percent).
    static func percentText(_ fraction: Double) -> String {
        let percent: Double = (fraction * 100).rounded()
        return String(Int(percent)) + "%"
    }

    /// "0.50".
    static func fractionText(_ fraction: Double) -> String {
        let hundredths: Int = Int((fraction * 100).rounded())
        let whole: Int = hundredths / 100
        let rest: Int = hundredths % 100
        let padded: String = rest < 10 ? "0" + String(rest) : String(rest)
        return String(whole) + "." + padded
    }
}
