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

public struct CameraPictureGeometry: Sendable, Equatable {
    /// Fraction of the upright picture's width and height that is shown (each 0…1).
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

    /// Aspect fill of a `pictureWidth` × `pictureHeight` texture (before rotation) into the output.
    /// Any size ≤ 0 gives the identity with the rotation.
    public init(pictureWidth: Int, pictureHeight: Int, rotation: CameraRotation, outputWidth: Int, outputHeight: Int,
                mirrored: Bool = false) {
        self.mirrored = mirrored
        guard pictureWidth > 0, pictureHeight > 0, outputWidth > 0, outputHeight > 0 else {
            self = .identity
            self.rotation = rotation
            self.mirrored = mirrored
            return
        }
        let uprightW = Double(rotation.swapsAxes ? pictureHeight : pictureWidth)
        let uprightH = Double(rotation.swapsAxes ? pictureWidth : pictureHeight)
        let scale = max(Double(outputWidth) / uprightW, Double(outputHeight) / uprightH)
        let fx = min(Double(outputWidth) / (uprightW * scale), 1)
        let fy = min(Double(outputHeight) / (uprightH * scale), 1)
        visibleWidth = Float(fx)
        visibleHeight = Float(fy)
        offsetX = Float((1 - fx) / 2)
        offsetY = Float((1 - fy) / 2)
        self.rotation = rotation
    }

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
