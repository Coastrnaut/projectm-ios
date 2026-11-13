// ImagePictureGeometry.swift — where a still image lands in a layer picture (MED-001-R9; research
// MED-001-D8). Plain Swift, every platform.
//
// Output coordinates are 0…1 with (0, 0) at the top-left of the layer picture; texture coordinates
// likewise for the image. The stored image is already upright (MED-001-R4), so there is no
// rotation. Fill covers the output and crops the overflow equally on both sides (visible ≤ 1); fit
// shows the whole image and letterboxes (visible ≥ 1 on one axis: coordinates outside 0…1 are not
// part of the image and are drawn transparent).

public enum ImageScaleMode: Sendable, Equatable {
    /// Cover the output, crop the overflow (the default; spec Clarifications).
    case fill
    /// Show the whole image, transparent bars on the other axis.
    case fit
}

public struct ImagePictureGeometry: Sendable, Equatable {
    /// Width and height of the output, in units of the image's width and height.
    public var visibleWidth: Float
    public var visibleHeight: Float
    /// Image coordinate of the output's top-left corner.
    public var offsetX: Float
    public var offsetY: Float

    public static let identity = ImagePictureGeometry(visibleWidth: 1, visibleHeight: 1, offsetX: 0, offsetY: 0)

    public init(visibleWidth: Float, visibleHeight: Float, offsetX: Float, offsetY: Float) {
        self.visibleWidth = visibleWidth
        self.visibleHeight = visibleHeight
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// Any size ≤ 0 gives the identity.
    public init(pictureWidth: Int, pictureHeight: Int, outputWidth: Int, outputHeight: Int, mode: ImageScaleMode = .fill) {
        guard pictureWidth > 0, pictureHeight > 0, outputWidth > 0, outputHeight > 0 else {
            self = .identity
            return
        }
        let w = Double(pictureWidth), h = Double(pictureHeight)
        let sx = Double(outputWidth) / w, sy = Double(outputHeight) / h
        let scale = mode == .fill ? max(sx, sy) : min(sx, sy)
        let fx = Double(outputWidth) / (w * scale)
        let fy = Double(outputHeight) / (h * scale)
        visibleWidth = Float(fx)
        visibleHeight = Float(fy)
        offsetX = Float((1 - fx) / 2)
        offsetY = Float((1 - fy) / 2)
    }

    /// The image coordinate shown at output point (`x`, `y`); outside 0…1 means "no image here".
    /// The shader does the same arithmetic.
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        (offsetX + x * visibleWidth, offsetY + y * visibleHeight)
    }
}
