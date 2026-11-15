// DirectionalBlurSetting.swift — FX-007: the directional blur as the user sets it in Settings → Directional blur
// (FX-007-R9, R10; specs/295-fx-007-directional-blur, contracts/directional-blur.md C4, research FX-007-D7; ADR-0106).
//
// One global visual setting: `settings.directionalBlur.enabled` (Bool, absent → off), `settings.directionalBlur.radius`
// (Double fraction of the shorter side, absent/NaN → 0.005, out of range → the nearest bound) and
// `settings.directionalBlur.angle` (Double degrees, absent/NaN → 0, folds into 0…180). Values are written only when
// changed. Every change calls `onChange`, through which `AppCoordinator` hands the value to the compositor-backed
// visuals (Camera, Photo, Video, Text). No safety cap (the blur averages, adds no brightness; ADR-0106). Scenes and
// effect-chain presets with an `fx.directionalBlur` entry set these values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class DirectionalBlurSetting {
    static let enabledKey = "settings.directionalBlur.enabled"
    static let radiusKey = "settings.directionalBlur.radius"
    static let angleKey = "settings.directionalBlur.angle"
    static let allKeys: [String] = [enabledKey, radiusKey, angleKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((DirectionalBlur) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(blur)
        }
    }

    /// Fraction of the shorter side, 0…0.02.
    var radius: Double {
        didSet {
            let valid: Double = DirectionalBlur.clampRadius(radius)
            if valid != radius || radius.isNaN {
                radius = valid   // re-enters once with the valid value
                return
            }
            guard radius != oldValue else { return }
            defaults.set(radius, forKey: Self.radiusKey)
            onChange?(blur)
        }
    }

    /// Degrees, 0…180.
    var angleDegrees: Double {
        didSet {
            let valid: Double = DirectionalBlur.clampAngle(angleDegrees)
            if valid != angleDegrees || angleDegrees.isNaN {
                angleDegrees = valid
                return
            }
            guard angleDegrees != oldValue else { return }
            defaults.set(angleDegrees, forKey: Self.angleKey)
            onChange?(blur)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        radius = DirectionalBlur.clampRadius(Self.readDouble(defaults, Self.radiusKey, DirectionalBlur.defaultRadius))
        angleDegrees = DirectionalBlur.clampAngle(Self.readDouble(defaults, Self.angleKey, DirectionalBlur.defaultAngle))
    }

    /// The user's value (what the compositors apply).
    var blur: DirectionalBlur {
        DirectionalBlur(isEnabled: isEnabled, radius: radius, angleDegrees: angleDegrees)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: DirectionalBlur) {
        if radius != value.radius { radius = value.radius }
        if angleDegrees != value.angleDegrees { angleDegrees = value.angleDegrees }
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

    /// "0.5%" (one decimal).
    static func radiusText(_ fraction: Double) -> String {
        let percent: Double = fraction * 100
        return percent.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// "45°" (whole degrees).
    static func angleText(_ degrees: Double) -> String {
        String(Int(degrees.rounded())) + "\u{00B0}"
    }
}
