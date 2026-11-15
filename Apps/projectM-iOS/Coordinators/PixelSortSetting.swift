// PixelSortSetting.swift — FX-011: the pixel sort as the user sets it in Settings → Pixel sort (FX-011-R9, R10;
// specs/310-fx-011-pixel-sorting, contracts/pixel-sort.md C5; ADR-0121).
//
// One global visual setting: `settings.pixelSort.enabled` (Bool, absent → off), `settings.pixelSort.threshold` (0…1,
// absent/unreadable/NaN → 0.5, out of range → the nearest bound), `settings.pixelSort.span` (absent/unreadable → 32,
// otherwise the largest of 4, 8, 16, 32, 64 not above it, at least 4) and `settings.pixelSort.direction` (`horizontal`
// or `vertical`, anything else → horizontal). Values are written only when changed. Every change calls `onChange`,
// through which `AppCoordinator` hands the value to the compositor-backed visuals (Camera, Photo, Video, Text). Scenes
// and effect-chain presets with an `fx.pixelSort` entry set these values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class PixelSortSetting {
    static let enabledKey = "settings.pixelSort.enabled"
    static let thresholdKey = "settings.pixelSort.threshold"
    static let spanKey = "settings.pixelSort.span"
    static let directionKey = "settings.pixelSort.direction"
    static let allKeys: [String] = [enabledKey, thresholdKey, spanKey, directionKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((PixelSort) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(sort)
        }
    }

    /// Luminance threshold, 0…1.
    var threshold: Double {
        didSet {
            let valid: Double = PixelSort.clampThreshold(threshold)
            if valid != threshold || threshold.isNaN {
                threshold = valid   // re-enters once with the valid value
                return
            }
            guard threshold != oldValue else { return }
            defaults.set(threshold, forKey: Self.thresholdKey)
            onChange?(sort)
        }
    }

    /// Pixels per tile: 4, 8, 16, 32 or 64.
    var span: Int {
        didSet {
            let valid: Int = PixelSort.snapSpan(span)
            if valid != span {
                span = valid
                return
            }
            guard span != oldValue else { return }
            defaults.set(span, forKey: Self.spanKey)
            onChange?(sort)
        }
    }

    var direction: PixelSort.Direction {
        didSet {
            guard direction != oldValue else { return }
            defaults.set(direction.rawValue, forKey: Self.directionKey)
            onChange?(sort)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey) ?? false
        threshold = PixelSort.clampThreshold(Self.readDouble(defaults, Self.thresholdKey, PixelSort.defaultThreshold))
        span = PixelSort.snapSpan(Self.readDouble(defaults, Self.spanKey, Double(PixelSort.defaultSpan)))
        direction = PixelSort.Direction(rawValue: defaults.string(forKey: Self.directionKey) ?? "") ?? PixelSort.defaultDirection
    }

    /// The user's value (what the compositors apply).
    var sort: PixelSort {
        PixelSort(isEnabled: isEnabled, threshold: threshold, span: span, direction: direction)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: PixelSort) {
        if threshold != value.threshold { threshold = value.threshold }
        if span != value.span { span = value.span }
        if direction != value.direction { direction = value.direction }
        isEnabled = value.isEnabled
    }

    /// Only a real Bool counts (a stored number or string reads as absent).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → `fallback` (NaN is handled by the clamp or snap).
    private static func readDouble(_ defaults: UserDefaults, _ key: String, _ fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return fallback }
        return number.doubleValue
    }

    /// "50%" (whole percent).
    static func thresholdText(_ fraction: Double) -> String {
        String(Int((fraction * 100).rounded())) + "%"
    }
}
