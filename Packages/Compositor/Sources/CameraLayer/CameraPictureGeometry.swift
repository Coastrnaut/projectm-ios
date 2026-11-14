// CameraPictureGeometry.swift — aspect fill and orientation of a camera picture in a layer picture
// (CAM-001-R2; research CAM-001-D3). Plain Swift, every platform.
//
// Output coordinates are 0…1 with (0, 0) at the top-left of the layer picture. The camera picture is
// first made upright by its rotation, then scaled to cover the output while keeping its aspect
// ratio; the overflow is cropped equally on both sides. `visible`/`offset` describe the part of the
// upright picture that is shown; `textureCoordinate` maps an output point to the camera texture.
// CAM-002-R3 (research CAM-002-D1): `mirrored` flips the upright picture left to right about its
// vertical center, after the rotation makes it upright and with the crop still centered. This is
// the only place the mirror exists; the shader repeats the same arithmetic, so the screen, saved
// frames, recordings and the external display (one composite) all carry it.
// CAM-007-R2, R3 (research CAM-007-D1): the scale may instead fit (Fit) and be zoomed, and the
// shown part is placed by the crop's anchor instead of always centered; `visible` may exceed 1
// (Fit) and `offset` may be negative. `contains` marks the bars, drawn transparent.

public struct CameraPictureGeometry: Sendable, Equatable {
    /// Fraction of the upright picture's width and height that is shown (0…1 in Fill; above 1 in Fit).
    public var visibleWidth: Float
    public var visibleHeight: Float
    /// Upright coordinate of the output's top-left corner.
    public var offsetX: Float
    public var offsetY: Float
    public var rotation: CameraRotation
    /// CAM-002: the upright picture is flipped left to right.
    public var mirrored: Bool

    /// The whole picture, upright already.
    public static let identity = CameraPictureGeometry(visibleWidth: 1, visibleHeight: 1, offsetX: 0, offsetY: 0, rotation: .none)

    public init(visibleWidth: Float, visibleHeight: Float, offsetX: Float, offsetY: Float, rotation: CameraRotation,
                mirrored: Bool = false) {
        self.visibleWidth = visibleWidth
        self.visibleHeight = visibleHeight
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotation = rotation
        self.mirrored = mirrored
    }

    /// The picture of a `pictureWidth` × `pictureHeight` texture (before rotation) in the output, with
    /// the user's crop (CAM-007-R2, R3; research CAM-007-D1). One scale for both axes (no stretch):
    /// Fill covers the output, Fit lies wholly inside it, and the zoom multiplies that scale. The
    /// shown part is placed so the crop's anchor point of the upright picture lands on the same
    /// relative output point: offset = (1 − visible) × anchor. `crop == .fill` is CAM-001's centered
    /// aspect fill. Any size ≤ 0 gives the identity with the rotation and mirror.
    public init(pictureWidth: Int, pictureHeight: Int, rotation: CameraRotation, outputWidth: Int, outputHeight: Int,
                mirrored: Bool = false, crop: CameraCrop = .fill) {
        self.mirrored = mirrored
        guard pictureWidth > 0, pictureHeight > 0, outputWidth > 0, outputHeight > 0 else {
            self = .identity
            self.rotation = rotation
            self.mirrored = mirrored
            return
        }
        let uprightW: Double = Double(rotation.swapsAxes ? pictureHeight : pictureWidth)
        let uprightH: Double = Double(rotation.swapsAxes ? pictureWidth : pictureHeight)
        let outW: Double = Double(outputWidth)
        let outH: Double = Double(outputHeight)
        let scaleX: Double = outW / uprightW
        let scaleY: Double = outH / uprightH
        let base: Double = crop.mode == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let scale: Double = base * Double(crop.zoom)
        let rawX: Double = outW / (uprightW * scale)
        let rawY: Double = outH / (uprightH * scale)
        // Fill never shows more than the picture (≤ 1 already; the clamp only removes rounding).
        let fx: Double = crop.mode == .fill ? min(rawX, 1) : rawX
        let fy: Double = crop.mode == .fill ? min(rawY, 1) : rawY
        let anchorX: Double = 0.5
        let anchorY: Double = Double(crop.anchor.y)
        visibleWidth = Float(fx)
        visibleHeight = Float(fy)
        offsetX = Float((1 - fx) * anchorX)
        offsetY = Float((1 - fy) * anchorY)
        self.rotation = rotation
    }

    /// CAM-007-R4: true when output point (`x`, `y`) (0…1, top-left) shows the picture; false in Fit's
    /// bars. The shader uses the same test and tolerance.
    public func contains(x: Float, y: Float) -> Bool {
        let a: Float = offsetX + x * visibleWidth
        let b: Float = offsetY + y * visibleHeight
        let low: Float = -Self.edgeTolerance
        let high: Float = 1 + Self.edgeTolerance
        return a >= low && a <= high && b >= low && b <= high
    }

    /// Upright coordinates this far outside 0…1 still count as the picture (Fill's edge pixels).
    public static let edgeTolerance: Float = 1e-4

    /// The camera texture coordinate (0…1, top-left) shown at output point (`x`, `y`) (0…1, top-left).
    /// The shader does the same arithmetic.
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        let croppedA: Float = offsetX + x * visibleWidth
        let b: Float = offsetY + y * visibleHeight
        let a: Float = mirrored ? 1 - croppedA : croppedA   // CAM-002-R3: flip the upright picture
        switch rotation {
        case .none: return (a, b)
        case .clockwise90: return (b, 1 - a)
        case .clockwise180: return (1 - a, 1 - b)
        case .clockwise270: return (1 - b, a)
        }
    }
}
