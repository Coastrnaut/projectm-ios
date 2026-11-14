// CameraCrop.swift — the user's crop choice for the camera picture (CAM-007-R1; research CAM-007-D1,
// D5; spec 098). Plain Swift, every platform.
//
// A mode (Fill covers the layer picture, Fit shows the whole picture with transparent bars), an
// anchor (a point on the upright picture's vertical center line that always lands on the same
// relative point of the layer picture) and a zoom (1, 1.5, 2 or 3 times the plain Fill or Fit
// size). `CameraCrop.fill` is CAM-001's centered aspect fill. `CameraPictureGeometry` applies it.

/// Fill covers the layer picture (the overflow is cropped); Fit shows the whole picture.
public enum CameraCropMode: String, Sendable, Equatable, CaseIterable {
    case fill
    case fit

    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        }
    }
}

/// The point of the upright picture kept at the same relative place of the layer picture.
public enum CameraCropAnchor: String, Sendable, Equatable, CaseIterable {
    case center
    case top
    case bottom

    public var title: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }

    /// The anchor's height on the upright picture and on the layer picture (0 top … 1 bottom); its
    /// x is always 0.5, so the mirror never moves it.
    public var y: Float {
        switch self {
        case .center: return 0.5
        case .top: return 0
        case .bottom: return 1
        }
    }
}

public struct CameraCrop: Sendable, Equatable {
    public var mode: CameraCropMode
    public var anchor: CameraCropAnchor
    /// One of `zoomChoices`.
    public private(set) var zoom: Float

    /// The zoom steps offered (CAM-007-D5).
    public static let zoomChoices: [Float] = [1, 1.5, 2, 3]

    /// CAM-001's picture: Fill, centered, 1× (the default).
    public static let fill = CameraCrop(mode: .fill, anchor: .center, zoom: 1)

    /// Any zoom that is not one of `zoomChoices` (or not finite) becomes 1.
    public init(mode: CameraCropMode, anchor: CameraCropAnchor, zoom: Float) {
        self.mode = mode
        self.anchor = anchor
        self.zoom = Self.validZoom(zoom)
    }

    /// `zoom` if it is one of `zoomChoices`, otherwise 1.
    public static func validZoom(_ zoom: Float) -> Float {
        guard zoom.isFinite else { return 1 }
        let match: Float? = zoomChoices.first { (choice: Float) -> Bool in abs(choice - zoom) < 0.001 }
        return match ?? 1
    }

    /// "1×", "1.5×", "2×", "3×".
    public static func zoomTitle(_ zoom: Float) -> String {
        numberText(validZoom(zoom)) + "×"
    }

    /// "1 times", "1.5 times" (VoiceOver reads "×" inconsistently; spec Clarifications).
    public static func zoomSpokenValue(_ zoom: Float) -> String {
        numberText(validZoom(zoom)) + " times"
    }

    /// Whole numbers without a decimal point, halves with one digit.
    private static func numberText(_ value: Float) -> String {
        let tenths: Int = Int((value * 10).rounded())
        let whole: Int = tenths / 10
        let fraction: Int = tenths % 10
        if fraction == 0 { return String(whole) }
        return String(whole) + "." + String(fraction)
    }
}
