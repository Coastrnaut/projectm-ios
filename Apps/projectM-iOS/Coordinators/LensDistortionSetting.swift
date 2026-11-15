// LensDistortionSetting.swift — FX-016: the lens distortion as the user sets it in Settings → Lens distortion
// (FX-016-R8, R9; specs/306-fx-016-lens-distortion, contracts/lens-distortion.md C4, research FX-016-D7; ADR-0117).
//
// One global visual setting: `settings.lensDistortion.enabled` (Bool, absent → off), `settings.lensDistortion.strength`
// (−1…1, absent/unreadable/NaN → +0.3, out of range → the nearest bound) and `settings.lensDistortion.zoomToFill` (Bool,
// absent or not a Bool → on). Values are written only when changed. Every change calls `onChange`, through which
// `AppCoordinator` hands the value to the compositor-backed visuals (Camera, Photo, Video, Text). No safety cap (the
// warp adds no brightness; ADR-0117). Scenes and effect-chain presets with an `fx.lensDistortion` entry set these values
// when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class LensDistortionSetting {
    static let enabledKey = "settings.lensDistortion.enabled"
    static let strengthKey = "settings.lensDistortion.strength"
    static let zoomToFillKey = "settings.lensDistortion.zoomToFill"
    static let allKeys: [String] = [enabledKey, strengthKey, zoomToFillKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((LensDistortion) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(lens)
        }
    }

    /// Signed fraction, −1 (pincushion)…+1 (barrel).
    var strength: Double {
        didSet {
            let valid: Double = LensDistortion.clampStrength(strength)
            if valid != strength || strength.isNaN {
                strength = valid   // re-enters once with the valid value
                return
            }
            guard strength != oldValue else { return }
            defaults.set(strength, forKey: Self.strengthKey)
            onChange?(lens)
        }
    }

    var zoomToFill: Bool {
        didSet {
            guard zoomToFill != oldValue else { return }
            defaults.set(zoomToFill, forKey: Self.zoomToFillKey)
            onChange?(lens)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey) ?? false
        strength = LensDistortion.clampStrength(Self.readDouble(defaults, Self.strengthKey, LensDistortion.defaultStrength))
        zoomToFill = Self.readBool(defaults, Self.zoomToFillKey) ?? LensDistortion.defaultZoomToFill
    }

    /// The user's value (what the compositors apply).
    var lens: LensDistortion {
        LensDistortion(isEnabled: isEnabled, strength: strength, zoomToFill: zoomToFill)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: LensDistortion) {
        if strength != value.strength { strength = value.strength }
        if zoomToFill != value.zoomToFill { zoomToFill = value.zoomToFill }
        isEnabled = value.isEnabled
    }

    /// Only a real Bool counts (a stored number or string reads as absent).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → `fallback` (NaN is handled by the clamp).
    private static func readDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return fallback }
        return number.doubleValue
    }

    /// "+30%", "0%", "-30%" (whole percent, signed).
    static func strengthText(_ fraction: Double) -> String {
        let percent: Int = Int((fraction * 100).rounded())
        let sign: String = percent > 0 ? "+" : ""
        return sign + String(percent) + "%"
    }
}
