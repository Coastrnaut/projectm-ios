// ExternalOutputSetting.swift — OUT-004-R8, C4 (spec specs/172-out-004-aspect-correction): the external
// display's output correction as the user chose it in Settings › External Display.
//
// Three device-local strings: `settings.externalDisplay.fit` (`fit`, `fill`, `stretch`),
// `settings.externalDisplay.shape` (`display`, `device`) and `settings.externalDisplay.pixelAspect`
// (`auto`, `1.0`, `0.9`, `1.2`). Absent or unknown reads the default (Fit, Display, Automatic) and nothing
// is stored until changed. They describe the user's display hardware, so the library backup leaves them
// out (excluded keys; erased with Settings) and `-uitestResetNotice` removes them. Every change is pushed
// to the coordinator, which applies it to the external slots inside the call (or after a recording hold).
import Foundation
import Observation
import PresentationLifecycle

@MainActor
@Observable
final class ExternalOutputSetting {
    static let fitKey = "settings.externalDisplay.fit"
    static let shapeKey = "settings.externalDisplay.shape"
    static let pixelAspectKey = "settings.externalDisplay.pixelAspect"
    static let keys: [String] = [fitKey, shapeKey, pixelAspectKey]

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
        external.correction = correction
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
        + "Rehearse output previews a display that is not connected."

    // OUT-012
    static let rehearseTitle = "Rehearse output…"
    static let rehearseUnavailable = "A connected display already shows the real output."
    static let rehearsalFooter = "A preview of what a display of this size would show: black bars, crop and "
        + "pixel aspect, with this app's output settings. The visualization keeps running on this device. "
        + "Nothing here is saved; connecting a real display ends the rehearsal."

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
