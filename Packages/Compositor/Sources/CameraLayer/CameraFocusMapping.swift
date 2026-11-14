// CameraFocusMapping.swift — a touch on the camera picture to the camera's focus point (CAM-005-R2,
// R3; research CAM-005-D1, D2; contracts/focus-point.md C1). Plain Swift, every platform.
//
// The touch is normalized by the picture's on-screen rect, then mapped by the same
// `CameraPictureGeometry` the camera layer draws with (Fill or Fit, anchor, zoom, mirror, the picture's
// rotation for the interface orientation). Its texture coordinate is the camera picture as delivered:
// unrotated and unmirrored (the providers never rotate or mirror buffers), which is AVFoundation's
// point-of-interest space (0…1, top-left of the landscape sensor picture). So what is drawn under the
// finger is what the camera focuses on. Touches outside the rect or in Fit's bars give nil.

/// A point of the camera picture (0…1 each, AVFoundation's point-of-interest space).
public struct CameraFocusPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    /// Clamped to 0…1; a non-finite value becomes 0.5.
    public init(x: Double, y: Double) {
        self.x = Self.clamped(x)
        self.y = Self.clamped(y)
    }

    /// The middle of the picture: where automatic focus looks by default.
    public static let centre = CameraFocusPoint(x: 0.5, y: 0.5)

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    /// True when both coordinates are within `tolerance` of `other`'s.
    public func isClose(to other: CameraFocusPoint, tolerance: Double = 1e-6) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

/// The camera picture the layer drew last: its texture size and the turn that makes it upright.
public struct CameraDrawnPicture: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rotation: CameraRotation

    public init(width: Int, height: Int, rotation: CameraRotation) {
        self.width = width
        self.height = height
        self.rotation = rotation
    }
}

public enum CameraFocusMapping {
    /// The camera point shown at touch (`touchX`, `touchY`) when the layer picture fills the rect
    /// (`rectX`, `rectY`, `rectWidth`, `rectHeight`), all in the same coordinate space (points). nil
    /// when the rect or picture is empty, the touch is outside the rect, or it is in Fit's bars.
    public static func devicePoint(touchX: Double, touchY: Double, rectX: Double, rectY: Double,
                                   rectWidth: Double, rectHeight: Double, picture: CameraDrawnPicture,
                                   crop: CameraCrop, mirrored: Bool) -> CameraFocusPoint? {
        guard rectWidth.isFinite, rectHeight.isFinite, rectWidth > 0, rectHeight > 0,
              picture.width > 0, picture.height > 0, touchX.isFinite, touchY.isFinite else { return nil }
        let u: Double = (touchX - rectX) / rectWidth
        let v: Double = (touchY - rectY) / rectHeight
        guard u >= 0, u <= 1, v >= 0, v <= 1 else { return nil }
        let geometry = CameraPictureGeometry(pictureWidth: picture.width, pictureHeight: picture.height,
                                             rotation: picture.rotation, outputSize: (rectWidth, rectHeight),
                                             mirrored: mirrored, crop: crop)
        let x: Float = Float(u)
        let y: Float = Float(v)
        guard geometry.contains(x: x, y: y) else { return nil }   // CAM-007-R4: Fit's bars
        let texture: (x: Float, y: Float) = geometry.textureCoordinate(x: x, y: y)
        return CameraFocusPoint(x: Double(texture.x), y: Double(texture.y))
    }
}
