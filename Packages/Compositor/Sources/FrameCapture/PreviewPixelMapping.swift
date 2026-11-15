// PreviewPixelMapping.swift — UIX-012-R4 (specs/300-uix-012-touch-color-sampler, contract C1; research
// UIX-012-D2, D3). Plain Swift: builds on Linux.
//
// A tap on the live preview, in window points, to the output pixel under it:
//
//   1. UIX-007 split editor: the visual is drawn at its full size scaled by `splitScale` from the top left and
//      moved by `splitOrigin`, so the full-size view point is (p − origin) / scale. Outside the view: rejected.
//   2. The picture in the view: `stretch` covers the view (the device: a drawable stretched over its view);
//      `fit` and `fill` keep the picture's physical shape W·pixelAspect : H (OUT-004's rule), centred.
//      A point outside the picture's rect (fit's bars) is rejected.
//   3. The point's fraction (u, v) of the picture rect → pixel (floor(u·W), floor(v·H)), the far edge clamped
//      to the last pixel. The screen's Retina factor needs no input: the picture's pixel size carries it.
import Foundation

/// How the picture meets the view.
public enum PreviewFit: String, Sendable, Equatable, CaseIterable {
    case stretch, fit, fill
}

/// An output pixel, top-left origin.
public struct PreviewPixel: Sendable, Equatable, CustomStringConvertible {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public var description: String { "(\(x), \(y))" }
}

public struct PreviewPixelMapping: Sendable, Equatable {
    /// The visual's full view size in points.
    public var viewWidth: Double
    public var viewHeight: Double
    /// UIX-007: the uniform scale and the offset (window points) the visual is drawn with; 1 and 0 when not split.
    public var splitScale: Double
    public var splitOriginX: Double
    public var splitOriginY: Double
    public var fit: PreviewFit
    /// The picture's size in pixels.
    public var pictureWidth: Int
    public var pictureHeight: Int
    /// Pixel width ÷ pixel height of the picture's pixels (1: square).
    public var pixelAspect: Double

    public init(viewWidth: Double, viewHeight: Double, splitScale: Double = 1, splitOriginX: Double = 0,
                splitOriginY: Double = 0, fit: PreviewFit = .stretch, pictureWidth: Int, pictureHeight: Int,
                pixelAspect: Double = 1) {
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        self.splitScale = splitScale
        self.splitOriginX = splitOriginX
        self.splitOriginY = splitOriginY
        self.fit = fit
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
        self.pixelAspect = pixelAspect
    }

    private var isUsable: Bool {
        let values: [Double] = [viewWidth, viewHeight, splitScale, splitOriginX, splitOriginY, pixelAspect]
        return values.allSatisfy(\.isFinite) && viewWidth > 0 && viewHeight > 0 && splitScale > 0 && pixelAspect > 0
            && pictureWidth > 0 && pictureHeight > 0
    }

    /// The picture's rect in the full-size view (points): x, y, width, height.
    public var pictureRect: (x: Double, y: Double, width: Double, height: Double) {
        let w: Double = viewWidth, h: Double = viewHeight
        guard fit != .stretch else { return (0, 0, w, h) }
        let aspect: Double = Double(pictureWidth) * pixelAspect / Double(pictureHeight)
        let wider: Bool = aspect >= w / h
        let widthLimited: Bool = fit == .fit ? wider : !wider
        let size: (Double, Double) = widthLimited ? (w, w / aspect) : (h * aspect, h)
        return ((w - size.0) / 2, (h - size.1) / 2, size.0, size.1)
    }

    /// The output pixel under window point (x, y), or nil (outside the view or the picture, or unusable input).
    public func pixel(atX x: Double, y: Double) -> PreviewPixel? {
        guard isUsable, x.isFinite, y.isFinite else { return nil }
        let viewX: Double = (x - splitOriginX) / splitScale
        let viewY: Double = (y - splitOriginY) / splitScale
        guard viewX >= 0, viewY >= 0, viewX <= viewWidth, viewY <= viewHeight else { return nil }
        let rect = pictureRect
        let u: Double = (viewX - rect.x) / rect.width
        let v: Double = (viewY - rect.y) / rect.height
        guard u >= 0, v >= 0, u <= 1, v <= 1 else { return nil }
        let px: Int = min(Int((u * Double(pictureWidth)).rounded(.down)), pictureWidth - 1)
        let py: Int = min(Int((v * Double(pictureHeight)).rounded(.down)), pictureHeight - 1)
        return PreviewPixel(x: px, y: py)
    }
}
