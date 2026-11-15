// FilmGrainSetting.swift — FX-017: the film grain as the user sets it in Settings → Film grain (FX-017-R9, R10;
// specs/311-fx-017-film-grain, contracts/film-grain.md C4, research FX-017-D6; ADR-0122).
//
// One global visual setting: `settings.filmGrain.enabled` (Bool, absent → off), `.opacity` (0…1, absent/NaN → 0.3),
// `.size` (1…3 pixels, absent → 1), `.color` (Bool, absent → monochrome), `.seed` (0…9999, absent → 1) and `.animated`
// (Bool, absent → static); out of range → the nearest bound, fractional numbers rounded, non-Bool flags read as off.
// Values are written only when changed. Every change calls `onChange`, through which `AppCoordinator` hands the effective
// value (static under Reduce Motion) to the compositor-backed visuals (Camera, Photo, Video, Text). No safety cap (the
// grain is zero-mean and bounded; ADR-0122). Scenes and effect-chain presets with an `fx.filmGrain` entry set these
// values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class FilmGrainSetting {
    static let enabledKey = "settings.filmGrain.enabled"
    static let opacityKey = "settings.filmGrain.opacity"
    static let sizeKey = "settings.filmGrain.size"
    static let colorKey = "settings.filmGrain.color"
    static let seedKey = "settings.filmGrain.seed"
    static let animatedKey = "settings.filmGrain.animated"
    static let allKeys: [String] = [enabledKey, opacityKey, sizeKey, colorKey, seedKey, animatedKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((FilmGrain) -> Void)?

    var isEnabled: Bool {
        didSet { flag(isEnabled, oldValue, Self.enabledKey) }
    }

    /// Fraction, 0…1.
    var opacity: Double {
        didSet {
            let valid: Double = FilmGrain.clampOpacity(opacity)
            if valid != opacity || opacity.isNaN {
                opacity = valid   // re-enters once with the valid value
                return
            }
            guard opacity != oldValue else { return }
            defaults.set(opacity, forKey: Self.opacityKey)
            onChange?(grain)
        }
    }

    /// Grain cell edge, 1…3 pixels.
    var size: Int {
        didSet {
            let valid: Int = FilmGrain.clampSize(size)
            if valid != size {
                size = valid
                return
            }
            guard size != oldValue else { return }
            defaults.set(size, forKey: Self.sizeKey)
            onChange?(grain)
        }
    }

    var isColor: Bool {
        didSet { flag(isColor, oldValue, Self.colorKey) }
    }

    /// Pattern seed, 0…9999.
    var seed: Int {
        didSet {
            let valid: Int = FilmGrain.clampSeed(seed)
            if valid != seed {
                seed = valid
                return
            }
            guard seed != oldValue else { return }
            defaults.set(seed, forKey: Self.seedKey)
            onChange?(grain)
        }
    }

    /// "Vary over time".
    var isAnimated: Bool {
        didSet { flag(isAnimated, oldValue, Self.animatedKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        opacity = FilmGrain.clampOpacity(Self.readNumber(defaults, Self.opacityKey) ?? FilmGrain.defaultOpacity)
        size = FilmGrain.size(fromNumber: Self.readNumber(defaults, Self.sizeKey) ?? Double(FilmGrain.defaultSize))
        isColor = Self.readBool(defaults, Self.colorKey)
        seed = FilmGrain.seed(fromNumber: Self.readNumber(defaults, Self.seedKey) ?? Double(FilmGrain.defaultSeed))
        isAnimated = Self.readBool(defaults, Self.animatedKey)
    }

    /// The user's value (the compositors get `effective(reduceMotion:)` of it).
    var grain: FilmGrain {
        FilmGrain(isEnabled: isEnabled, opacity: opacity, size: size, isColor: isColor, seed: seed, isAnimated: isAnimated)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: FilmGrain) {
        if opacity != value.opacity { opacity = value.opacity }
        if size != value.size { size = value.size }
        if isColor != value.isColor { isColor = value.isColor }
        if seed != value.seed { seed = value.seed }
        if isAnimated != value.isAnimated { isAnimated = value.isAnimated }
        isEnabled = value.isEnabled
    }

    /// A Bool changed: stored and sent.
    private func flag(_ value: Bool, _ oldValue: Bool, _ key: String) {
        guard value != oldValue else { return }
        defaults.set(value, forKey: key)
        onChange?(grain)
    }

    /// Only a real Bool counts (a stored number or string reads as off).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → nil (NaN is handled by the clamps).
    private static func readNumber(_ defaults: UserDefaults, _ key: String) -> Double? {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.doubleValue
    }

    // MARK: - Readouts (typed steps)

    /// "30%" (whole percent).
    static func percentText(_ fraction: Double) -> String {
        let percent: Double = (fraction * 100).rounded()
        return String(Int(percent)) + "%"
    }

    /// "2 px".
    static func sizeText(_ size: Int) -> String { String(size) + " px" }
}
