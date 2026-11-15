// ExternalOutputSetting.swift — OUT-004-R8, C4 (spec specs/172-out-004-aspect-correction): the external
// display's output correction as the user chose it in Settings › External Display.
//
// Three device-local strings: `settings.externalDisplay.fit` (`fit`, `fill`, `stretch`),
// `settings.externalDisplay.shape` (`display`, `device`) and `settings.externalDisplay.pixelAspect`
// (`auto`, `1.0`, `0.9`, `1.2`). Absent or unknown reads the default (Fit, Display, Automatic) and nothing
// is stored until changed. They describe the user's display hardware, so the library backup leaves them
// out (excluded keys; erased with Settings) and `-uitestResetNotice` removes them. Every change is pushed
// to the coordinator, which applies it to the external slots inside the call (or after a recording hold).
// OUT-003 (spec specs/255-out-003-output-resolution, contract C4): the output resolution, two more
// device-local values with the same rules: `settings.externalDisplay.resolution` (`native`, `1080p`,
// `720p`, `custom`) and `settings.externalDisplay.resolutionPercent` (integer 50…100, default 75).
// The device's pixel budget is REC-014's `RecordingOutputCap.device`.
// OUT-006 (spec specs/261-out-006-output-mirroring, contract C4): the output mode, one more device-local
// value with the same rules: `settings.externalDisplay.outputMode` (`sameScene`, `clean`), applied live.
// OUT-007 (spec specs/264-out-007-corner-pin, contract C4): the corner pin, one more device-local value with the
// same rules: `settings.externalDisplay.cornerPin` ("x,y;x,y;x,y;x,y", TL;TR;BR;BL); the identity removes it, and
// a missing, malformed or invalid value reads as the identity. Applied live.
import FrameRecording
import Foundation
import Observation
import PresentationLifecycle

@MainActor
@Observable
final class ExternalOutputSetting {
    static let fitKey = "settings.externalDisplay.fit"
    static let shapeKey = "settings.externalDisplay.shape"
    static let pixelAspectKey = "settings.externalDisplay.pixelAspect"
    static let resolutionKey = "settings.externalDisplay.resolution"
    static let resolutionPercentKey = "settings.externalDisplay.resolutionPercent"
    static let outputModeKey = "settings.externalDisplay.outputMode"   // OUT-006
    static let cornerPinKey = "settings.externalDisplay.cornerPin"   // OUT-007
    static let keys: [String] = [fitKey, shapeKey, pixelAspectKey, resolutionKey, resolutionPercentKey, outputModeKey,
                                 cornerPinKey]

    @ObservationIgnored private let defaults: UserDefaults
    /// OUT-012: the rehearsal row reads and drives the coordinator's rehearsal flag.
    @ObservationIgnored private(set) weak var external: ExternalDisplayCoordinator?

    var fit: ExternalOutputFit {
        didSet { store(fit.rawValue, Self.fitKey) }
    }
    var shape: ExternalOutputShape {
        didSet { store(shape.rawValue, Self.shapeKey) }
    }
    var pixelAspect: ExternalPixelAspect {
        didSet { store(pixelAspect.rawValue, Self.pixelAspectKey) }
    }

    // OUT-003
    var resolutionMode: ExternalResolutionMode {
        didSet {
            guard resolutionMode != oldValue else { return }
            defaults.set(resolutionMode.rawValue, forKey: Self.resolutionKey)
            external?.resolution = resolution
        }
    }
    /// Custom's percentage (50…100, 5 % steps in the slider).
    var resolutionPercent: Int {
        didSet {
            let clamped: Int = ExternalOutputResolution.clampPercent(resolutionPercent)
            if clamped != resolutionPercent { resolutionPercent = clamped }   // no second didSet
            guard resolutionPercent != oldValue else { return }
            defaults.set(resolutionPercent, forKey: Self.resolutionPercentKey)
            external?.resolution = resolution
        }
    }

    // OUT-006
    var outputMode: ExternalOutputMode {
        didSet {
            guard outputMode != oldValue else { return }
            defaults.set(outputMode.rawValue, forKey: Self.outputModeKey)
            external?.outputMode = outputMode
        }
    }

    // OUT-007
    /// Only valid pins are ever set (the editor's edits are clamped or refused by `CornerPin`).
    var cornerPin: CornerPin {
        didSet {
            guard cornerPin != oldValue else { return }
            if cornerPin.isIdentity { defaults.removeObject(forKey: Self.cornerPinKey) } else {
                defaults.set(cornerPin.stored, forKey: Self.cornerPinKey)
            }
            external?.cornerPin = cornerPin
        }
    }

    var resolution: ExternalOutputResolution {
        ExternalOutputResolution(mode: resolutionMode, percent: resolutionPercent)
    }

    /// REC-014-R5's cap for this device class, as the external output's pixel budget (OUT-003-R3).
    static var devicePixelBudget: ExternalPixelBudget {
        let cap: RecordingOutputCap = RecordingOutputCap.device(physicalMemory: ProcessInfo.processInfo.physicalMemory,
                                                                maxTextureSide: 16_384)
        return ExternalPixelBudget(maxSide: cap.maxSide, maxPixels: cap.maxPixels)
    }

    var correction: ExternalOutputCorrection {
        ExternalOutputCorrection(fit: fit, shape: shape, pixelAspect: pixelAspect)
    }

    init(defaults: UserDefaults, external: ExternalDisplayCoordinator) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            for key in Self.keys { defaults.removeObject(forKey: key) }   // the UI-test reset
        }
        self.defaults = defaults
        self.external = external
        fit = defaults.string(forKey: Self.fitKey).flatMap(ExternalOutputFit.init(rawValue:)) ?? .fit
        shape = defaults.string(forKey: Self.shapeKey).flatMap(ExternalOutputShape.init(rawValue:)) ?? .display
        pixelAspect = defaults.string(forKey: Self.pixelAspectKey).flatMap(ExternalPixelAspect.init(rawValue:)) ?? .automatic
        resolutionMode = defaults.string(forKey: Self.resolutionKey).flatMap(ExternalResolutionMode.init(rawValue:)) ?? .native
        let storedPercent: Int? = defaults.object(forKey: Self.resolutionPercentKey) as? Int
        resolutionPercent = ExternalOutputResolution.clampPercent(storedPercent ?? ExternalOutputResolution.defaultPercent)
        outputMode = ExternalOutputMode(stored: defaults.string(forKey: Self.outputModeKey))
        cornerPin = defaults.string(forKey: Self.cornerPinKey).flatMap { (s: String) -> CornerPin? in CornerPin(stored: s) } ?? .identity
        external.correction = correction
        external.pixelBudget = Self.devicePixelBudget
        external.resolution = resolution
        external.outputMode = outputMode
        external.cornerPin = cornerPin
    }

    private func store(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
        external?.correction = correction
    }

    // MARK: - Strings (Settings › External Display)

    static let sectionTitle = "External Display"
    static let footer = "Changes only the picture on a connected external display. Fit shows the whole picture "
        + "with black bars, Fill covers the screen and crops, Stretch fills the screen without correction. "
        + "Device keeps this device's shape; Pixel aspect keeps circles round on screens with non-square pixels. "
        + "Resolution sets how many pixels are drawn for the display (never more than it has, and within "
        + "this device's safe limit); the picture's layout stays the same. "
        + "Output: Same scene shows the scene as composed, logo included; Clean output shows the visual only "
        + "(no logo) on the display, and recordings made meanwhile match it. The device always shows the whole scene. "
        + "Rehearse output previews a display that is not connected. "
        + "Corner pin moves the picture's four corners to fit a projector that is not square to the screen "
        + "(the display only; this device and recordings are unchanged)."

    // OUT-007
    static let cornerPinTitle = "Corner pin…"
    static let cornerPinEditorTitle = "Corner Pin"
    static let cornerPinFooter = "Drag each corner, or pick a corner and nudge it, until the test card's edges "
        + "match the screen. A connected display shows the test card while this is open. Shapes that would fold "
        + "or flip the picture are not accepted."

    static func title(_ corner: CornerPin.Corner) -> String {
        switch corner {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .bottomLeft: "Bottom left"
        }
    }

    /// "Top left, 3 % across, 0 % down" (VoiceOver value, output-relative percentages).
    static func spokenValue(_ corner: CornerPin.Corner, _ point: CornerPinPoint) -> String {
        let x = Int((point.x * 1000).rounded()), y = Int((point.y * 1000).rounded())
        let across: String = percent(x) + " across", down: String = percent(y) + " down"
        return across + ", " + down
    }

    private static func percent(_ tenths: Int) -> String {
        let sign: String = tenths < 0 ? "minus " : ""
        let magnitude: Int = abs(tenths)
        let whole: Int = magnitude / 10, fraction: Int = magnitude % 10
        return sign + (fraction == 0 ? "\(whole) %" : "\(whole).\(fraction) %")
    }

    // OUT-012
    static let rehearseTitle = "Rehearse output…"
    static let rehearseUnavailable = "A connected display already shows the real output."
    static let rehearsalFooter = "A preview of what a display of this size would show: black bars, crop and "
        + "pixel aspect, with this app's output settings. The visualization keeps running on this device. "
        + "Nothing here is saved; connecting a real display ends the rehearsal."

    // OUT-006
    static let outputModeTitle = "Output"

    static func title(_ mode: ExternalOutputMode) -> String {
        switch mode {
        case .sameScene: "Same scene"
        case .clean: "Clean output"
        }
    }

    // OUT-003
    static let resolutionTitle = "Resolution"
    static let resolutionPercentTitle = "Scale"

    static func title(_ mode: ExternalResolutionMode) -> String {
        switch mode {
        case .native: "Native"
        case .hd1080: "1080p"
        case .hd720: "720p"
        case .custom: "Custom"
        }
    }

    static func title(_ fit: ExternalOutputFit) -> String {
        switch fit {
        case .fit: "Fit"
        case .fill: "Fill"
        case .stretch: "Stretch"
        }
    }

    static func title(_ shape: ExternalOutputShape) -> String {
        switch shape {
        case .display: "Display"
        case .device: "Device"
        }
    }

    static func title(_ aspect: ExternalPixelAspect) -> String {
        switch aspect {
        case .automatic: "Automatic"
        case .square: "1.0 (square)"
        case .narrow: "0.9"
        case .wide: "1.2"
        }
    }
}
