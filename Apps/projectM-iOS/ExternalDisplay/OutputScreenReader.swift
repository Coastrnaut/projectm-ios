// OutputScreenReader.swift — OUT-011 (spec specs/275-out-011-output-diagnostics, contract C2; research OUT-011-D1): the
// only place that reads a display's own values, from documented, non-deprecated `UIScreen` properties of the external
// scene's screen. Nothing is estimated: a value the screen does not report stays nil ("Not available").
import PresentationLifecycle
import UIKit

@MainActor
enum OutputScreenReader {
    /// The screen's readings (OUT-011-R2); the output's own fields (drawable, pixel aspect, mode) are added by the
    /// coordinator.
    static func readings(screen: UIScreen) -> OutputReadings {
        var r = OutputReadings()
        let native: CGRect = screen.nativeBounds
        r.nativeWidth = Int(native.width.rounded())
        r.nativeHeight = Int(native.height.rounded())
        r.nativeScale = Double(screen.nativeScale)
        r.pointWidth = Double(screen.bounds.width)
        r.pointHeight = Double(screen.bounds.height)
        r.scale = Double(screen.scale)
        r.maximumFramesPerSecond = screen.maximumFramesPerSecond
        r.gamut = gamut(screen.traitCollection.displayGamut)
        r.potentialEDRHeadroom = Double(screen.potentialEDRHeadroom)
        r.currentEDRHeadroom = Double(screen.currentEDRHeadroom)
        r.mirrored = screen.mirrored != nil
        r.overscan = overscan(screen.overscanCompensation)
        return r
    }

    static func gamut(_ gamut: UIDisplayGamut) -> OutputReadings.Gamut? {
        switch gamut {
        case .SRGB: return .sRGB
        case .P3: return .displayP3
        case .unspecified: return nil
        @unknown default: return nil
        }
    }

    static func overscan(_ compensation: UIScreen.OverscanCompensation) -> OutputReadings.Overscan? {
        switch compensation {
        case .scale: return .scale
        case .insetBounds: return .insetBounds
        case .none: return .off
        @unknown default: return nil
        }
    }
}
