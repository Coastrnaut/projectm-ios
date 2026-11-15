// ScanlinesSetting.swift — FX-018: the scanlines as the user sets them in Settings → Scanlines (FX-018-R8, R9;
// specs/312-fx-018-scanline-texture, contracts/scanlines.md C4, research FX-018-D7; ADR-0123).
//
// One global visual setting: `settings.scanlines.enabled` (Bool, absent → off), `settings.scanlines.spacing` (whole
// pixels 2…16, absent → 3), `settings.scanlines.thickness` (whole pixels 1…spacing − 1, absent → 1),
// `settings.scanlines.intensity` (0…1, absent/NaN → 0.5) and `settings.scanlines.vertical` (Bool, absent → horizontal);
// out of range → the nearest bound, numbers rounded to whole pixels. Lowering the spacing lowers a larger thickness to
// spacing − 1, so the slider shows what is drawn. Values are written only when changed. Every change calls `onChange`,
// through which `AppCoordinator` hands the value to the compositor-backed visuals (Camera, Photo, Video, Text). No
// safety cap (static, darkening only; ADR-0123). Scenes and effect-chain presets with an `fx.scanlines` entry set these
// values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class ScanlinesSetting {
    static let enabledKey = "settings.scanlines.enabled"
    static let spacingKey = "settings.scanlines.spacing"
    static let thicknessKey = "settings.scanlines.thickness"
    static let intensityKey = "settings.scanlines.intensity"
    static let verticalKey = "settings.scanlines.vertical"
    static let allKeys: [String] = [enabledKey, spacingKey, thicknessKey, intensityKey, verticalKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((Scanlines) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(scanlines)
        }
    }

    /// Whole pixels, 2…16.
    var spacing: Int {
        didSet {
            let valid: Int = Scanlines.clampSpacing(spacing)
            if valid != spacing {
                spacing = valid   // re-enters once with the valid value
                return
            }
            guard spacing != oldValue else { return }
            defaults.set(spacing, forKey: Self.spacingKey)
            if thickness > spacing - 1 {
                thickness = spacing - 1   // stores and sends
            } else {
                onChange?(scanlines)
            }
        }
    }

    /// Whole pixels, 1…spacing − 1.
    var thickness: Int {
        didSet {
            let valid: Int = Self.validThickness(thickness, spacing: spacing)
            if valid != thickness {
                thickness = valid   // re-enters once with the valid value
                return
            }
            guard thickness != oldValue else { return }
            defaults.set(thickness, forKey: Self.thicknessKey)
            onChange?(scanlines)
        }
    }

    /// Fraction, 0…1.
    var intensity: Double {
        didSet {
            let valid: Double = Scanlines.clampIntensity(intensity)
            if valid != intensity || intensity.isNaN {
                intensity = valid   // re-enters once with the valid value
                return
            }
            guard intensity != oldValue else { return }
            defaults.set(intensity, forKey: Self.intensityKey)
            onChange?(scanlines)
        }
    }

    var isVertical: Bool {
        didSet {
            guard isVertical != oldValue else { return }
            defaults.set(isVertical, forKey: Self.verticalKey)
            onChange?(scanlines)
        }
    }

    /// The sliders' views of the whole-pixel values (rounded on the way in).
    var spacingValue: Double {
        get { Double(spacing) }
        set { spacing = Scanlines.clampSpacing(newValue) }
    }

    var thicknessValue: Double {
        get { Double(thickness) }
        set { thickness = Scanlines.clampThickness(newValue) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        let storedSpacing: Int = Scanlines.clampSpacing(Self.readDouble(defaults, Self.spacingKey, Double(Scanlines.defaultSpacing)))
        spacing = storedSpacing
        let storedThickness: Int = Scanlines.clampThickness(Self.readDouble(defaults, Self.thicknessKey,
                                                                            Double(Scanlines.defaultThickness)))
        thickness = Self.validThickness(storedThickness, spacing: storedSpacing)
        intensity = Scanlines.clampIntensity(Self.readDouble(defaults, Self.intensityKey, Scanlines.defaultIntensity))
        isVertical = Self.readBool(defaults, Self.verticalKey)
    }

    /// The user's value (what the compositors apply).
    var scanlines: Scanlines {
        Scanlines(isEnabled: isEnabled, spacing: spacing, thickness: thickness, intensity: intensity, isVertical: isVertical)
    }

    /// The thickness slider's range (1…spacing − 1; 1…2 and disabled at spacing 2, where only 1 is possible).
    var thicknessRange: ClosedRange<Double> {
        1...Double(max(2, spacing - 1))
    }

    /// At spacing 2 the thickness can only be 1.
    var isThicknessAdjustable: Bool { spacing > 2 }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule; spacing first).
    func apply(_ value: Scanlines) {
        if spacing != value.spacing { spacing = value.spacing }
        if thickness != value.thickness { thickness = value.thickness }
        if intensity != value.intensity { intensity = value.intensity }
        if isVertical != value.isVertical { isVertical = value.isVertical }
        isEnabled = value.isEnabled
    }

    private static func validThickness(_ value: Int, spacing: Int) -> Int {
        min(Scanlines.clampThickness(value), Scanlines.clampSpacing(spacing) - 1)
    }

    /// Only a real Bool counts (a stored number or string reads as off).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → `fallback` (NaN is handled by the clamps).
    private static func readDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return fallback }
        return number.doubleValue
    }

    // MARK: - Readouts (typed steps)

    /// "3 px".
    static func pixelText(_ pixels: Int) -> String {
        String(pixels) + " px"
    }

    /// "50%" (whole percent).
    static func percentText(_ fraction: Double) -> String {
        let percent: Double = (fraction * 100).rounded()
        return String(Int(percent)) + "%"
    }
}
