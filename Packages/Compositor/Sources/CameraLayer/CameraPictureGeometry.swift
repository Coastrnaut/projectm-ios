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
        self.init(pictureWidth: pictureWidth, pictureHeight: pictureHeight, rotation: rotation,
                  outputSize: (Double(outputWidth), Double(outputHeight)), mirrored: mirrored, crop: crop)
    }

    /// The same geometry for an output of any real size (CAM-005-T02): a picture rect on screen in
    /// points keeps its exact aspect. Any size ≤ 0 or not finite gives the identity with the rotation
    /// and mirror.
    public init(pictureWidth: Int, pictureHeight: Int, rotation: CameraRotation, outputSize: (width: Double, height: Double),
                mirrored: Bool = false, crop: CameraCrop = .fill) {
        self.mirrored = mirrored
        let outW: Double = outputSize.width
        let outH: Double = outputSize.height
        guard pictureWidth > 0, pictureHeight > 0, outW.isFinite, outH.isFinite, outW > 0, outH > 0 else {
            self = .identity
            self.rotation = rotation
            self.mirrored = mirrored
            return
        }
        let uprightW: Double = Double(rotation.swapsAxes ? pictureHeight : pictureWidth)
        let uprightH: Double = Double(rotation.swapsAxes ? pictureWidth : pictureHeight)
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

    /// QA-011 CAM-007-T15/T16 (spec 098 Clarifications 2026-11-23): where the whole upright picture lands in the
    /// output, in output fractions (0…1, top-left), read from the same `visible`/`offset` the shader samples with:
    /// output x shows upright a = offsetX + x × visibleWidth, so a = 0…1 spans x = −offsetX / visibleWidth over a
    /// width of 1 / visibleWidth (y likewise). Fill covers 0…1 (and may extend past it); Fit lies inside it, with
    /// bars where it does not reach. The mirror flips the picture within this rectangle and does not move it.
    public var pictureRect: CameraPictureRect {
        guard visibleWidth > 0, visibleHeight > 0, visibleWidth.isFinite, visibleHeight.isFinite else {
            return CameraPictureRect(x: 0, y: 0, width: 1, height: 1)
        }
        let width: Float = 1 / visibleWidth
        let height: Float = 1 / visibleHeight
        return CameraPictureRect(x: -offsetX * width, y: -offsetY * height, width: width, height: height)
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

/// A rectangle in output fractions (0…1, top-left; QA-011 CAM-007-T15/T16).
public struct CameraPictureRect: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// What the camera layer drew last frame (QA-011 CAM-007-T15/T16): the picture, the crop, the layer picture's size
/// and the geometry the shader sampled with. Plain values, stored once per frame without allocating.
public struct CameraDrawnLayout: Sendable, Equatable {
    public let picture: CameraDrawnPicture
    public let crop: CameraCrop
    public let outputWidth: Int
    public let outputHeight: Int
    public let geometry: CameraPictureGeometry

    public init(picture: CameraDrawnPicture, crop: CameraCrop, outputWidth: Int, outputHeight: Int,
                geometry: CameraPictureGeometry) {
        self.picture = picture
        self.crop = crop
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.geometry = geometry
    }

    /// The upright picture's width over its height (the source's aspect after its rotation).
    public var sourceAspect: Double {
        let swaps: Bool = picture.rotation.swapsAxes
        let w: Double = Double(swaps ? picture.height : picture.width)
        let h: Double = Double(swaps ? picture.width : picture.height)
        return h > 0 ? w / h : 0
    }
}
