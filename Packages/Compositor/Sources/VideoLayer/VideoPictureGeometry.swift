// VideoPictureGeometry.swift — where a video picture lands in a layer picture (CMP-006-R7; research
// CMP-006-D6). Plain Swift, every platform.
//
// The track's quarter turn makes the decoded picture upright; the fit (CMP-006 `LayerFitPlacement`)
// is computed on the upright size, so a portrait clip recorded sideways keeps its crop on a landscape
// output. `textureCoordinate` maps an output point (0…1, top-left) to the upright coordinate and then
// to the decoded texture; an upright coordinate outside 0…1 is not part of the video and is drawn
// transparent (fit and pixelAccurate bars). With no fit set (fill at the centre) the numbers equal
// the camera geometry's aspect fill that MED-002 used before, so today's video output is unchanged.
import CameraLayer
import Compositor

public struct VideoPictureGeometry: Sendable, Equatable {
    /// Width and height of the output, in units of the upright picture's width and height.
    public var visibleWidth: Float
    public var visibleHeight: Float
    /// Upright coordinate of the output's top-left corner.
    public var offsetX: Float
    public var offsetY: Float
    public var rotation: CameraRotation

    /// `pictureWidth` × `pictureHeight` is the decoded texture (before rotation). Any size ≤ 0 gives
    /// the whole picture with the rotation.
    public init(pictureWidth: Int, pictureHeight: Int, rotation: CameraRotation, outputWidth: Int, outputHeight: Int,
                fit: LayerFit = .default) {
        let uprightW: Int = rotation.swapsAxes ? pictureHeight : pictureWidth
        let uprightH: Int = rotation.swapsAxes ? pictureWidth : pictureHeight
        let placement = LayerFitPlacement(contentWidth: uprightW, contentHeight: uprightH, outputWidth: outputWidth,
                                          outputHeight: outputHeight, fit: fit)
        visibleWidth = Float(placement.visibleWidth)
        visibleHeight = Float(placement.visibleHeight)
        offsetX = Float(placement.offsetX)
        offsetY = Float(placement.offsetY)
        self.rotation = rotation
    }

    /// The upright coordinate shown at output point (`x`, `y`); outside 0…1 means "no video here".
    public func uprightCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        let a: Float = offsetX + x * visibleWidth
        let b: Float = offsetY + y * visibleHeight
        return (a, b)
    }

    /// The decoded texture coordinate (0…1, top-left) of upright coordinate (`a`, `b`). The shader
    /// does the same arithmetic.
    public func textureCoordinate(x: Float, y: Float) -> (x: Float, y: Float) {
        let (a, b) = uprightCoordinate(x: x, y: y)
        switch rotation {
        case .none: return (a, b)
        case .clockwise90: return (b, 1 - a)
        case .clockwise180: return (1 - a, 1 - b)
        case .clockwise270: return (1 - b, a)
        }
    }
}
