// ColorGradeSetting.swift — FX-003: the colour grade the user sets in Settings → Color (FX-003-R8, R9;
// specs/123-fx-003-color-grading, contracts/color-grade.md, research FX-003-D7).
//
// One global visual setting (not part of scenes or show cues): five Doubles under `settings.colorGrade.temperature`,
// `.lift`, `.gamma`, `.gain` and `.saturation`. Read rule: absent, not a number or NaN → the neutral value; out of
// range → the nearest bound (`ColorGrade.clamped`). `resetToNeutral()` removes the five keys. Every change calls
// `onChange`, through which `AppCoordinator` hands `grade` to the compositor-backed visuals (Camera, Photo, Video,
// Text); the native spectra and projectM are not graded (spec Clarifications). Readouts are built in typed steps.
// FX-004 (specs/126-fx-004-hue-shift): a sixth Double, `settings.colorGrade.hue` (degrees), read, clamped, stored and
// reset like the others; ACC-012 does not cap it (it keeps luminance; research FX-004-D7).
// ACC-012: the sensory safety profile's intensity limit caps the brightening part of gain (`effectiveGrade`;
// research FX-003-D10); Standard leaves the grade unchanged. The flash guard measures the graded output either way.
// FX-020 (specs/142-fx-020-effect-chains, research FX-020-D9): an on/off switch, `settings.colorGrade.enabled` (Bool,
// absent → on); off makes `effectiveGrade` neutral and keeps the values. Removed with the others by the reset.
import Compositor
import FlashSafety
import Foundation
import Observation

@MainActor
@Observable
final class ColorGradeSetting {
    static let temperatureKey = "settings.colorGrade.temperature"
    static let liftKey = "settings.colorGrade.lift"
    static let gammaKey = "settings.colorGrade.gamma"
    static let gainKey = "settings.colorGrade.gain"
    static let saturationKey = "settings.colorGrade.saturation"
    static let hueKey = "settings.colorGrade.hue"   // FX-004-R8
    static let enabledKey = "settings.colorGrade.enabled"   // FX-020-R8
    static let allKeys: [String] = [temperatureKey, liftKey, gammaKey, gainKey, saturationKey, hueKey, enabledKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) grade.
    @ObservationIgnored var onChange: ((ColorGrade) -> Void)?

    var temperature: Double {
        didSet { store(\.temperature, ColorGrade.temperatureRange, 0, Self.temperatureKey) }
    }

    var lift: Double {
        didSet { store(\.lift, ColorGrade.liftRange, 0, Self.liftKey) }
    }

    var gamma: Double {
        didSet { store(\.gamma, ColorGrade.gammaRange, 1, Self.gammaKey) }
    }

    var gain: Double {
        didSet { store(\.gain, ColorGrade.gainRange, 1, Self.gainKey) }
    }

    var saturation: Double {
        didSet { store(\.saturation, ColorGrade.saturationRange, 1, Self.saturationKey) }
    }

    /// FX-004: degrees, −180…180.
    var hue: Double {
        didSet { store(\.hue, ColorGrade.hueRange, 0, Self.hueKey) }
    }

    /// FX-020: Color on (the default) or off (neutral output, values kept).
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(grade)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let storedEnabled = defaults.object(forKey: Self.enabledKey) as? NSNumber
        isEnabled = storedEnabled.map { (n: NSNumber) -> Bool in CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : true } ?? true
        let stored = ColorGrade(temperature: Self.read(defaults, Self.temperatureKey, 0), lift: Self.read(defaults, Self.liftKey, 0),
                                gamma: Self.read(defaults, Self.gammaKey, 1), gain: Self.read(defaults, Self.gainKey, 1),
                                saturation: Self.read(defaults, Self.saturationKey, 1), hue: Self.read(defaults, Self.hueKey, 0))
        let valid: ColorGrade = stored.clamped
        temperature = valid.temperature
        lift = valid.lift
        gamma = valid.gamma
        gain = valid.gain
        saturation = valid.saturation
        hue = valid.hue
    }

    /// The grade the compositor applies.
    var grade: ColorGrade {
        ColorGrade(temperature: temperature, lift: lift, gamma: gamma, gain: gain, saturation: saturation, hue: hue)
    }

    var isNeutral: Bool { grade.isNeutral }

    /// What the compositors apply under `clamp` (ACC-012, research FX-003-D10): gain above 1 is an intensity-type
    /// boost, so its excursion is capped at the profile's intensity limit × (maximum gain − 1). Unchanged at limit 1.
    func effectiveGrade(clamp: SafetyClamp) -> ColorGrade {
        guard isEnabled else { return .neutral }   // FX-020
        return Self.effective(grade, clamp: clamp)
    }

    static func effective(_ grade: ColorGrade, clamp: SafetyClamp) -> ColorGrade {
        guard clamp.capsIntensity, grade.gain > 1 else { return grade }
        let boost: Float = Float(grade.gain - 1)
        let room: Float = Float(ColorGrade.gainRange.upperBound - 1)
        let capped: Float = clamp.intensity(boost, maximum: room)
        var out: ColorGrade = grade
        out.gain = 1 + Double(capped)
        return out
    }

    /// Every control back to neutral; the six keys are removed (absent = neutral).
    func resetToNeutral() {
        let neutral: ColorGrade = .neutral
        temperature = neutral.temperature
        lift = neutral.lift
        gamma = neutral.gamma
        gain = neutral.gain
        saturation = neutral.saturation
        hue = neutral.hue
        isEnabled = true
        for key in Self.allKeys { defaults.removeObject(forKey: key) }
        onChange?(grade)
    }

    /// Validates the field just set, writes it and reports the change. Re-assigning a corrected value re-enters
    /// once with a valid value, which is then stored.
    private func store(_ field: ReferenceWritableKeyPath<ColorGradeSetting, Double>, _ range: ClosedRange<Double>,
                       _ neutral: Double, _ key: String) {
        let value: Double = self[keyPath: field]
        let valid: Double = ColorGrade.clamp(value, to: range, neutral: neutral)
        if valid != value || value.isNaN {
            self[keyPath: field] = valid
            return
        }
        defaults.set(valid, forKey: key)
        onChange?(grade)
    }

    /// Absent, not a number or a Bool → `neutral` (NaN is handled by `clamped`). A Bool is told apart by its
    /// CFBoolean type, since a stored 0.0 or 1.0 would also bridge to Bool.
    private static func read(_ defaults: UserDefaults, _ key: String, _ neutral: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return neutral }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return neutral }
        return number.doubleValue
    }

    // MARK: - Readouts (typed steps)

    /// "Neutral", "Warm 25", "Cool 100" (the amount in percent of the range; no Kelvin, spec Clarifications).
    static func temperatureText(_ value: Double) -> String {
        let amount: Int = Int((abs(value) * 100).rounded())
        if amount == 0 { return "Neutral" }
        let word: String = value > 0 ? "Warm " : "Cool "
        return word + String(amount)
    }

    /// "+0.020", "0.000", "−0.050" (U+2212).
    static func liftText(_ value: Double) -> String {
        let magnitude: String = abs(value).formatted(.number.precision(.fractionLength(3)))
        let thousandths: Int = Int((value * 1000).rounded())
        if thousandths == 0 { return magnitude }
        let sign: String = thousandths > 0 ? "+" : "\u{2212}"
        return sign + magnitude
    }

    /// "1.00".
    static func gammaText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// "1.00×".
    static func gainText(_ value: Double) -> String {
        let number: String = value.formatted(.number.precision(.fractionLength(2)))
        return number + "\u{00D7}"
    }

    /// "100%".
    static func saturationText(_ value: Double) -> String {
        let percent: Int = Int((value * 100).rounded())
        return String(percent) + "%"
    }

    /// FX-004: "+30°", "0°", "−120°" (whole degrees, U+2212).
    static func hueText(_ value: Double) -> String {
        let whole: Int = Int(value.rounded())
        let magnitude: String = String(abs(whole)) + "\u{00B0}"
        if whole == 0 { return magnitude }
        let sign: String = whole > 0 ? "+" : "\u{2212}"
        return sign + magnitude
    }
}
