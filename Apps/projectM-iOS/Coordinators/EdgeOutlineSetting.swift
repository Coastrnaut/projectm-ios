// EdgeOutlineSetting.swift — FX-014: the edge outline as the user sets it in Settings → Edge outline (FX-014-R9, R10;
// specs/303-fx-014-edge-outline, contracts/edge-outline.md C4; ADR-0114).
//
// One global visual setting: `settings.edgeOutline.enabled` (Bool, absent → off), `.threshold` (0.02…1, absent or not a
// number → 0.2, clamped), `.width` (1…3 pixels, rounded and clamped, absent → 1), `.color` (six-digit sRGB hex,
// unreadable → white) and `.mode` (`overlay` or `outlineOnly`, anything else → overlay). Values are written only when
// changed. Every change calls `onChange`, through which `AppCoordinator` hands the effective value (the ACC-012 colour
// scale applied) to the compositor-backed visuals (Camera, Photo, Video, Text). Scenes and effect-chain presets with an
// `fx.edgeOutline` entry set these values when opened.
import Compositor
import FlashSafety
import Foundation
import Observation

@MainActor
@Observable
final class EdgeOutlineSetting {
    static let enabledKey = "settings.edgeOutline.enabled"
    static let thresholdKey = "settings.edgeOutline.threshold"
    static let widthKey = "settings.edgeOutline.width"
    static let colorKey = "settings.edgeOutline.color"
    static let modeKey = "settings.edgeOutline.mode"
    static let allKeys: [String] = [enabledKey, thresholdKey, widthKey, colorKey, modeKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) user value.
    @ObservationIgnored var onChange: ((EdgeOutline) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(outline)
        }
    }

    /// 0.02…1.
    var threshold: Double {
        didSet {
            let valid: Double = EdgeOutline.clampThreshold(threshold)
            if valid != threshold {
                threshold = valid   // re-enters once with the valid value
                return
            }
            guard threshold != oldValue else { return }
            defaults.set(threshold, forKey: Self.thresholdKey)
            onChange?(outline)
        }
    }

    /// Whole pixels, 1…3.
    var width: Int {
        didSet {
            let valid: Int = EdgeOutline.clampWidth(width)
            if valid != width {
                width = valid
                return
            }
            guard width != oldValue else { return }
            defaults.set(width, forKey: Self.widthKey)
            onChange?(outline)
        }
    }

    var color: EdgeOutlineColor {
        didSet {
            guard color != oldValue else { return }
            defaults.set(color.hex, forKey: Self.colorKey)
            onChange?(outline)
        }
    }

    var mode: EdgeOutlineMode {
        didSet {
            guard mode != oldValue else { return }
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            onChange?(outline)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        threshold = EdgeOutline.clampThreshold(Self.readDouble(defaults, Self.thresholdKey, EdgeOutline.defaultThreshold))
        width = EdgeOutline.clampWidth(Self.readDouble(defaults, Self.widthKey, Double(EdgeOutline.defaultWidth)))
        color = (defaults.object(forKey: Self.colorKey) as? String).flatMap(EdgeOutlineColor.init(hex:)) ?? .white
        mode = (defaults.object(forKey: Self.modeKey) as? String).flatMap(EdgeOutlineMode.init(rawValue:)) ?? .overlay
    }

    /// The user's value (before ACC-012's colour scale).
    var outline: EdgeOutline {
        EdgeOutline(isEnabled: isEnabled, threshold: threshold, width: width, color: color, mode: mode)
    }

    /// What the compositors apply under `clamp` (ACC-012; research FX-014-D6).
    func effective(clamp: SafetyClamp) -> EdgeOutline { outline.limited(by: clamp) }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: EdgeOutline) {
        if threshold != value.threshold { threshold = value.threshold }
        if width != value.width { width = value.width }
        if color != value.color { color = value.color }
        if mode != value.mode { mode = value.mode }
        isEnabled = value.isEnabled
    }

    /// The slider's view of `threshold`, rounded to hundredths on the way in.
    var thresholdValue: Double {
        get { threshold }
        set { threshold = EdgeOutline.clampThreshold((newValue * 100).rounded() / 100) }
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

    /// "0.20".
    static func thresholdText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
