// TextLayout.swift — where the text lands in a picture (MED-009-R5, R7; research MED-009-D6).
// Plain Swift, every platform.
//
// Picture coordinates are pixels with (0, 0) at the top-left (CMP-001 pictures are top-left). Font
// size = size × picture height; the text area is the picture's width minus 5 % on each side; the
// text frame is at most the picture's height minus 10 %; the canvas (the rendering's rectangle) is
// the text frame grown by `padding` on each side for the outline and the box, clamped to the
// picture. Vertical position: top and bottom keep a 5 % margin, middle centers.

public struct TextCanvas: Equatable, Sendable {
    /// The canvas in picture pixels.
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    /// The text frame inside the canvas (canvas pixels, top-left origin).
    public let frameX: Double
    public let frameY: Double
    public let frameWidth: Double
    public let frameHeight: Double
}

public struct TextLayout: Equatable, Sendable {
    public static let marginFraction = 0.05
    public static let boxPaddingFraction = 0.25

    public let pictureWidth: Int
    public let pictureHeight: Int
    public let fontPixels: Double
    public let outlinePixels: Double
    public let boxPadding: Double
    /// The text area's left edge and width (picture pixels).
    public let areaX: Double
    public let areaWidth: Double
    /// Space around the text frame inside the canvas (whole pixels).
    public let padding: Int
    /// The tallest text frame allowed.
    public let maximumFrameHeight: Double

    public init(spec: TextOverlaySpec, pictureWidth: Int, pictureHeight: Int) {
        self.pictureWidth = max(pictureWidth, 0)
        self.pictureHeight = max(pictureHeight, 0)
        let w = Double(self.pictureWidth), h = Double(self.pictureHeight)
        fontPixels = max(spec.size * h, 1)
        outlinePixels = spec.outlineWidth * fontPixels
        boxPadding = spec.showsBox ? Self.boxPaddingFraction * fontPixels : 0
        let margin = (Self.marginFraction * w).rounded()
        areaX = margin
        areaWidth = max(w - 2 * margin, 1)
        padding = Int(max(outlinePixels, boxPadding).rounded(.up)) + 2
        maximumFrameHeight = max(h * (1 - 2 * Self.marginFraction), 1)
    }

    /// The canvas for a text frame of `frameHeight` pixels (clamped to `maximumFrameHeight`).
    public func canvas(frameHeight: Double, position: TextVerticalPosition) -> TextCanvas {
        let frame = min(max(frameHeight.rounded(.up), 1), maximumFrameHeight)
        let h = Double(pictureHeight)
        let margin = (Self.marginFraction * h).rounded()
        let frameTop: Double
        switch position {
        case .top: frameTop = margin
        case .middle: frameTop = ((h - frame) / 2).rounded()
        case .bottom: frameTop = h - margin - frame
        }
        let p = Double(padding)
        let left = max(Int(areaX - p), 0), top = max(Int(frameTop - p), 0)
        let right = min(Int(areaX + areaWidth + p), pictureWidth), bottom = min(Int(frameTop + frame + p), pictureHeight)
        return TextCanvas(x: left, y: top, width: max(right - left, 0), height: max(bottom - top, 0),
                          frameX: areaX - Double(left), frameY: frameTop - Double(top),
                          frameWidth: areaWidth, frameHeight: frame)
    }
}
