// ImagePictureGeometry.swift — where a still image lands in a layer picture (MED-001-R9; research
// MED-001-D8). Plain Swift, every platform.
//
// Output coordinates are 0…1 with (0, 0) at the top-left of the layer picture; texture coordinates
// likewise for the image. The stored image is already upright (MED-001-R4), so there is no
// rotation. Fill covers the output and crops the overflow equally on both sides (visible ≤ 1); fit
// shows the whole image and letterboxes (visible ≥ 1 on one axis: coordinates outside 0…1 are not
// part of the image and are drawn transparent). CMP-006 adds stretch and pixelAccurate and an anchor;
// the arithmetic is the compositor's `LayerFitPlacement`.

import Compositor

/// The photo layer's fit modes are the compositor's (CMP-006): fill (the default; spec
/// Clarifications), fit, stretch and pixelAccurate.
public typealias ImageScaleMode = LayerFitMode

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

    /// Any size ≤ 0 gives the identity. CMP-006: the placement is `LayerFitPlacement` (fill and fit
    /// as before; stretch; pixelAccurate at one image pixel per output pixel), around `anchor`.
    public init(pictureWidth: Int, pictureHeight: Int, outputWidth: Int, outputHeight: Int, mode: ImageScaleMode = .fill,
                anchor: LayerPoint = LayerPoint(x: 0.5, y: 0.5)) {
        self.init(LayerFitPlacement(contentWidth: pictureWidth, contentHeight: pictureHeight, outputWidth: outputWidth,
                                    outputHeight: outputHeight, fit: LayerFit(mode: mode, anchor: anchor)))
    }

    /// The shader's single-precision copy of a placement.
    public init(_ placement: LayerFitPlacement) {
        visibleWidth = Float(placement.visibleWidth)
        visibleHeight = Float(placement.visibleHeight)
        offsetX = Float(placement.offsetX)
        offsetY = Float(placement.offsetY)
    }

    /// The image coordinate shown at output point (`x`, `y`); outside 0…1 means "no image here".
    /// The shader does the same arithmetic.
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        (offsetX + x * visibleWidth, offsetY + y * visibleHeight)
    }
}
