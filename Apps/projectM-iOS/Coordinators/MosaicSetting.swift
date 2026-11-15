// MosaicSetting.swift — FX-012: the mosaic as the user sets it in Settings → Mosaic (FX-012-R8, R9;
// specs/299-fx-012-mosaic-pixelation, contracts/mosaic.md C4, research FX-012-D6; ADR-0110).
//
// One global visual setting: `settings.mosaic.enabled` (Bool, absent → off), `settings.mosaic.size` (whole pixels,
// absent/not a number → 8, rounded, out of range → the nearest bound of 1…64) and `settings.mosaic.shape` (`square` or
// `hexagon`, anything else → square). Values are written only when changed. Every change calls `onChange`, through
// which `AppCoordinator` hands the value to the compositor-backed visuals (Camera, Photo, Video, Text). No safety cap
// (copying colours adds no brightness; ADR-0110). Scenes and effect-chain presets with an `fx.mosaic` entry set these
// values when opened.
import Compositor
import Foundation
import Observation

@MainActor
@Observable
final class MosaicSetting {
    static let enabledKey = "settings.mosaic.enabled"
    static let sizeKey = "settings.mosaic.size"
    static let shapeKey = "settings.mosaic.shape"
    static let allKeys: [String] = [enabledKey, sizeKey, shapeKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// Called after every change with the new (valid) value.
    @ObservationIgnored var onChange: ((Mosaic) -> Void)?

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            onChange?(mosaic)
        }
    }

    /// Whole pixels, 1…64.
    var blockSize: Int {
        didSet {
            let valid: Int = Mosaic.clampSize(blockSize)
            if valid != blockSize {
                blockSize = valid   // re-enters once with the valid value
                return
            }
            guard blockSize != oldValue else { return }
            defaults.set(blockSize, forKey: Self.sizeKey)
            onChange?(mosaic)
        }
    }

    var shape: MosaicShape {
        didSet {
            guard shape != oldValue else { return }
            defaults.set(shape.rawValue, forKey: Self.shapeKey)
            onChange?(mosaic)
        }
    }

    /// The slider's view of `blockSize` (rounded to whole pixels on the way in).
    var blockSizeValue: Double {
        get { Double(blockSize) }
        set { blockSize = Mosaic.clampSize(newValue) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = Self.readBool(defaults, Self.enabledKey)
        blockSize = Self.readSize(defaults)
        shape = (defaults.object(forKey: Self.shapeKey) as? String).flatMap(MosaicShape.init(rawValue:)) ?? .square
    }

    /// The user's value (what the compositors apply).
    var mosaic: Mosaic {
        Mosaic(isEnabled: isEnabled, blockSize: blockSize, shape: shape)
    }

    /// Sets every value from a scene or preset entry (each setter keeps its range rule).
    func apply(_ value: Mosaic) {
        if blockSize != value.blockSize { blockSize = value.blockSize }
        if shape != value.shape { shape = value.shape }
        isEnabled = value.isEnabled
    }

    /// Only a real Bool counts (a stored number or string reads as off).
    private static func readBool(_ defaults: UserDefaults, _ key: String) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }

    /// Absent, not a number or a Bool → 8; otherwise rounded and clamped.
    private static func readSize(_ defaults: UserDefaults) -> Int {
        guard let number = defaults.object(forKey: sizeKey) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return Mosaic.defaultSize }
        return Mosaic.clampSize(number.doubleValue)
    }

    // MARK: - Readouts (typed steps)

    /// "8 px".
    static func sizeText(_ size: Int) -> String {
        String(size) + " px"
    }
}
