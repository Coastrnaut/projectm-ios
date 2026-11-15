// ImagePictureGeometry.swift — where a still image lands in a layer picture (MED-001-R9; research
// MED-001-D8). Plain Swift, every platform.
//
// Output coordinates are 0…1 with (0, 0) at the top-left of the layer picture; texture coordinates
// likewise for the image. The stored image is already upright (MED-001-R4), so there is no
// rotation. Fill covers the output and crops the overflow equally on both sides (visible ≤ 1); fit
// shows the whole image and letterboxes (visible ≥ 1 on one axis: coordinates outside 0…1 are not
// part of the image and are drawn transparent). CMP-006 adds stretch and pixelAccurate and an anchor;
// the arithmetic is the compositor's `LayerFitPlacement`. MED-007 (research MED-007-D1, D2): with a Ken Burns crop the
// crop rectangle is the fitted content (`init(_:crop:)`), and image coordinates outside the crop (fit bars) are
// transparent (`minX…maxY`; the whole image without a crop).

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
    /// MED-007: the part of the image that may be drawn (image coordinates; 0…1 without a crop).
    public var minX: Float = 0
    public var minY: Float = 0
    public var maxX: Float = 1
    public var maxY: Float = 1

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

    /// MED-007: a placement computed for the crop's size (content = the crop), mapped back into image coordinates:
    /// visible' = visible · size, offset' = origin + offset · size; only the crop may be drawn.
    public init(_ placement: LayerFitPlacement, crop: KenBurnsRect) {
        let vw: Double = placement.visibleWidth * crop.width
        let vh: Double = placement.visibleHeight * crop.height
        let ox: Double = crop.x + placement.offsetX * crop.width
        let oy: Double = crop.y + placement.offsetY * crop.height
        visibleWidth = Float(vw)
        visibleHeight = Float(vh)
        offsetX = Float(ox)
        offsetY = Float(oy)
        minX = Float(crop.x)
        minY = Float(crop.y)
        maxX = Float(crop.x + crop.width)
        maxY = Float(crop.y + crop.height)
    }

    /// MED-007: the crop's shape as an integer content size for `LayerFitPlacement` (fill, fit and stretch read only
    /// the ratio): the crop's image pixels × 4096, so rounding never changes the shape visibly (pixel-accurate is drawn
    /// as fit, research MED-007-D1).
    public static func cropContentSize(_ crop: KenBurnsRect, imageWidth: Int, imageHeight: Int) -> (width: Int, height: Int) {
        let scale: Double = 4096
        let w: Double = (crop.width * Double(max(imageWidth, 1)) * scale).rounded()
        let h: Double = (crop.height * Double(max(imageHeight, 1)) * scale).rounded()
        return (max(1, Int(w)), max(1, Int(h)))
    }

    /// The image coordinate shown at output point (`x`, `y`); outside 0…1 means "no image here".
    /// The shader does the same arithmetic.
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        (offsetX + x * visibleWidth, offsetY + y * visibleHeight)
    }
}
