// ChromaticSplitSetting.swift — FX-006: the chromatic split as the user sets it in Settings → Chromatic split
// (FX-006-R8, R9; specs/293-fx-006-chromatic-split, contracts/chromatic-split.md C4, research FX-006-D9; ADR-0104).
//
// One global visual setting: `settings.chromatic.enabled` (Bool, absent → off), `settings.chromatic.amount` (Double
// fraction of the shorter side, absent/NaN → 0.005, out of range → the nearest bound), `settings.chromatic.angle`
// (Double degrees, absent/NaN → 0, wraps into 0…360) and `settings.chromatic.radial` (Bool, absent → off). Values are
// written only when changed. Every change calls `onChange`, through which `AppCoordinator` hands the value to the
// compositor-backed visuals (Camera, Photo, Video, Text). No safety cap (the split adds no brightness; ADR-0104).
// Scenes and effect-chain presets with an `fx.chromatic` entry set these values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class ChromaticSplitSetting {
    static let enabledKey = "settings.chromatic.enabled"
    static let amountKey = "settings.chromatic.amount"
    static let angleKey = "settings.chromatic.angle"
    static let radialKey = "settings.chromatic.radial"
    static let allKeys: [String] = [enabledKey, amountKey, angleKey, radialKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((ChromaticSplit) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(split)
        }
    }

    /// Fraction of the shorter side, 0…0.02.
    var amount: Double {
        didSet {
            let valid: Double = ChromaticSplit.clampAmount(amount)
            if valid != amount || amount.isNaN {
                amount = valid   // re-enters once with the valid value
                return
            }
            guard amount != oldValue else { return }
            defaults.set(amount, forKey: Self.amountKey)
            onChange?(split)
        }
    }

    /// Degrees, 0…360.
    var angleDegrees: Double {
        didSet {
            let valid: Double = ChromaticSplit.clampAngle(angleDegrees)
            if valid != angleDegrees || angleDegrees.isNaN {
                angleDegrees = valid
                return
            }
            guard angleDegrees != oldValue else { return }
            defaults.set(angleDegrees, forKey: Self.angleKey)
            onChange?(split)
        }
    }

    var isRadial: Bool {
        didSet {
            guard isRadial != oldValue else { return }
            defaults.set(isRadial, forKey: Self.radialKey)
            onChange?(split)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        amount = ChromaticSplit.clampAmount(Self.readDouble(defaults, Self.amountKey, ChromaticSplit.defaultAmount))
        angleDegrees = ChromaticSplit.clampAngle(Self.readDouble(defaults, Self.angleKey, ChromaticSplit.defaultAngle))
        isRadial = Self.readBool(defaults, Self.radialKey)
    }

    /// The user's value (what the compositors apply).
    var split: ChromaticSplit {
        ChromaticSplit(isEnabled: isEnabled, amount: amount, angleDegrees: angleDegrees, isRadial: isRadial)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: ChromaticSplit) {
        if amount != value.amount { amount = value.amount }
        if angleDegrees != value.angleDegrees { angleDegrees = value.angleDegrees }
        if isRadial != value.isRadial { isRadial = value.isRadial }
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
    static func amountText(_ fraction: Double) -> String {
        let percent: Double = fraction * 100
        return percent.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// "45°" (whole degrees).
    static func angleText(_ degrees: Double) -> String {
        String(Int(degrees.rounded())) + "\u{00B0}"
    }
}
