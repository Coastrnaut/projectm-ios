// RadialBlurSetting.swift — FX-008: the radial blur as the user sets it in Settings → Radial blur (FX-008-R8, R9;
// specs/296-fx-008-radial-blur, contracts/radial-blur.md C4, research FX-008-D8; ADR-0107).
//
// One global visual setting: `settings.radialBlur.enabled` (Bool, absent → off), `settings.radialBlur.strength`
// (Double fraction, absent/NaN → 0.1, out of range → the nearest bound of 0…0.25), `settings.radialBlur.centerX` and
// `settings.radialBlur.centerY` (Double fractions of the frame, 0 = left/top, absent/NaN → 0.5, clamped to 0…1). Values
// are written only when changed. Every change calls `onChange`, through which `AppCoordinator` hands the value to the
// compositor-backed visuals (Camera, Photo, Video, Text). No safety cap (averaging adds no brightness; ADR-0107).
// Scenes and effect-chain presets with an `fx.radialBlur` entry set these values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class RadialBlurSetting {
    static let enabledKey = "settings.radialBlur.enabled"
    static let strengthKey = "settings.radialBlur.strength"
    static let centerXKey = "settings.radialBlur.centerX"
    static let centerYKey = "settings.radialBlur.centerY"
    static let allKeys: [String] = [enabledKey, strengthKey, centerXKey, centerYKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((RadialBlur) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(blur)
        }
    }

    /// Fraction, 0…0.25.
    var strength: Double {
        didSet {
            let valid: Double = RadialBlur.clampStrength(strength)
            if valid != strength || strength.isNaN {
                strength = valid   // re-enters once with the valid value
                return
            }
            guard strength != oldValue else { return }
            defaults.set(strength, forKey: Self.strengthKey)
            onChange?(blur)
        }
    }

    /// Fraction of the width, 0 (left)…1.
    var focusX: Double {
        didSet {
            let valid: Double = RadialBlur.clampFocus(focusX)
            if valid != focusX || focusX.isNaN {
                focusX = valid
                return
            }
            guard focusX != oldValue else { return }
            defaults.set(focusX, forKey: Self.centerXKey)
            onChange?(blur)
        }
    }

    /// Fraction of the height, 0 (top)…1.
    var focusY: Double {
        didSet {
            let valid: Double = RadialBlur.clampFocus(focusY)
            if valid != focusY || focusY.isNaN {
                focusY = valid
                return
            }
            guard focusY != oldValue else { return }
            defaults.set(focusY, forKey: Self.centerYKey)
            onChange?(blur)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        strength = RadialBlur.clampStrength(Self.readDouble(defaults, Self.strengthKey, RadialBlur.defaultStrength))
        focusX = RadialBlur.clampFocus(Self.readDouble(defaults, Self.centerXKey, RadialBlur.defaultFocus))
        focusY = RadialBlur.clampFocus(Self.readDouble(defaults, Self.centerYKey, RadialBlur.defaultFocus))
    }

    /// The user's value (what the compositors apply).
    var blur: RadialBlur {
        RadialBlur(isEnabled: isEnabled, strength: strength, focusX: focusX, focusY: focusY)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: RadialBlur) {
        if strength != value.strength { strength = value.strength }
        if focusX != value.focusX { focusX = value.focusX }
        if focusY != value.focusY { focusY = value.focusY }
        isEnabled = value.isEnabled
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

    /// "10%" (whole percent).
    static func percentText(_ fraction: Double) -> String {
        let percent: Double = (fraction * 100).rounded()
        return String(Int(percent)) + "%"
    }
}
