// TextRasterizer.swift — draws a TextOverlaySpec with CoreText into a CPU bitmap (MED-009-R2, R5 to
// R8; research MED-009-D1, D2, D6 to D8; contracts/text-layer.md "Rasterizer").
//
// * Layout: one `CTFramesetter` over the cleaned message with the chosen font (CoreText's own font
//   fallback covers emoji, CJK and every script the system has a font for; bidirectional ordering
//   and shaping are CoreText's), a paragraph style with the message's direction (TextDirection) as
//   its explicit base direction and the alignment side, word wrapping, in a frame as wide as the
//   text area. The frame's height is CoreText's suggestion, clamped by `TextLayout`, so lines that do
//   not fit are not drawn.
// * Drawing: a zero-filled RGBA buffer (8 bits, premultiplied last, sRGB) as large as the canvas;
//   the box (if on: the union of the line bounds grown by the box padding), the outline (stroke
//   only, width 2 × outline so the visible border outside each glyph is the outline width), then the
//   fill on top. Antialiasing on, font smoothing off (iOS has none; macOS hosts match).
// * Pure function of its inputs, no shared state: the same spec at the same picture size gives
//   byte-identical pixels (MED-009-R8, S1). Any thread; the layer calls it on one serial queue.
#if canImport(CoreText) && canImport(CoreGraphics)
import CoreGraphics
import CoreText
import Foundation

public enum TextRasterizer {
    /// Nil when the message is blank, a size is below 1 pixel or a context cannot be made.
    public static func render(_ spec: TextOverlaySpec, pictureWidth: Int, pictureHeight: Int) -> TextRendering? {
        guard !spec.isEmpty, pictureWidth >= 1, pictureHeight >= 1 else { return nil }
        let layout = TextLayout(spec: spec, pictureWidth: pictureWidth, pictureHeight: pictureHeight)
        let direction = TextDirection.of(spec.message)
        let side = spec.alignment.side(for: direction)
        let font = makeFont(spec.font, weight: spec.weight, size: layout.fontPixels)
        let fill = attributedString(spec.message, font: font, color: spec.color, direction: direction, side: side, stroke: nil)
        let fillSetter = CTFramesetterCreateWithAttributedString(fill)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            fillSetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: layout.areaWidth, height: CGFloat.greatestFiniteMagnitude), nil)
        let canvas = layout.canvas(frameHeight: Double(suggested.height), position: spec.verticalPosition)
        guard canvas.width >= 1, canvas.height >= 1, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // CoreGraphics' y axis points up: the frame's top-left (frameX, frameY) maps to y = height − frameY − frameHeight.
        let frameRect = CGRect(x: canvas.frameX, y: Double(canvas.height) - canvas.frameY - canvas.frameHeight,
                               width: canvas.frameWidth, height: canvas.frameHeight)
        let path = CGPath(rect: frameRect, transform: nil)
        let fillFrame = CTFramesetterCreateFrame(fillSetter, CFRange(location: 0, length: 0), path, nil)

        var pixels = [UInt8](repeating: 0, count: canvas.width * canvas.height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: canvas.width, height: canvas.height,
                                          bitsPerComponent: 8, bytesPerRow: canvas.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            context.textMatrix = .identity
            if spec.showsBox, let box = boxRect(fillFrame, in: frameRect, padding: layout.boxPadding) {
                context.setFillColor(cgColor(spec.boxColor, space))
                context.fill(box.intersection(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)))
            }
            if layout.outlinePixels > 0 {
                let percent = 2 * layout.outlinePixels / layout.fontPixels * 100
                let outline = attributedString(spec.message, font: font, color: spec.outlineColor, direction: direction, side: side,
                                               stroke: (percent, spec.outlineColor))
                let outlineFrame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(outline),
                                                            CFRange(location: 0, length: 0), path, nil)
                context.setLineJoin(.round)
                CTFrameDraw(outlineFrame, context)
            }
            CTFrameDraw(fillFrame, context)
            return true
        }
        guard drawn else { return nil }
        return TextRendering(pictureWidth: pictureWidth, pictureHeight: pictureHeight, x: canvas.x, y: canvas.y,
                             width: canvas.width, height: canvas.height, pixels: pixels)
    }

    /// The family at the weight (descriptor matching picks the nearest face); the system font when
    /// the family does not resolve.
    static func makeFont(_ family: TextFontFamily, weight: TextFontWeight, size: Double) -> CTFont {
        let traits = [kCTFontWeightTrait as String: weight.weightTrait] as CFDictionary
        let system = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let systemWeighted = CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system),
                                                     [kCTFontTraitsAttribute as String: traits] as CFDictionary), size, nil)
        let name: String
        switch family {
        case .system: return systemWeighted
        case .avenirNext: name = "Avenir Next"
        case .georgia: name = "Georgia"
        case .menlo: name = "Menlo"
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: name,
                                                               kCTFontTraitsAttribute as String: traits] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return (CTFontCopyFamilyName(font) as String) == name ? font : systemWeighted
    }

    static func cgColor(_ color: TextColor, _ space: CGColorSpace) -> CGColor {
        let components: [CGFloat] = [color.red, color.green, color.blue, color.alpha]
        return CGColor(colorSpace: space, components: components) ?? CGColor(gray: 0, alpha: 0)
    }

    static func attributedString(_ message: String, font: CTFont, color: TextColor, direction: TextDirection,
                                 side: TextHorizontalSide, stroke: (percent: Double, color: TextColor)?) -> CFAttributedString {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var alignment: CTTextAlignment = side == .left ? .left : side == .right ? .right : .center
        var writing: CTWritingDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
        var lineBreak: CTLineBreakMode = .byWordWrapping
        let style: CTParagraphStyle = withUnsafeBytes(of: &alignment) { (a: UnsafeRawBufferPointer) -> CTParagraphStyle in
            withUnsafeBytes(of: &writing) { (w: UnsafeRawBufferPointer) -> CTParagraphStyle in
                withUnsafeBytes(of: &lineBreak) { (l: UnsafeRawBufferPointer) -> CTParagraphStyle in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                        CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: w.count, value: w.baseAddress!),
                        CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: l.count, value: l.baseAddress!),
                    ]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
        var attributes: [String: Any] = [
            kCTFontAttributeName as String: font,
            kCTParagraphStyleAttributeName as String: style,
            kCTForegroundColorAttributeName as String: cgColor(color, space),
        ]
        if let stroke {
            attributes[kCTStrokeWidthAttributeName as String] = stroke.percent as NSNumber
            attributes[kCTStrokeColorAttributeName as String] = cgColor(stroke.color, space)
        }
        return CFAttributedStringCreate(nil, message as CFString, attributes as CFDictionary)
    }

    /// The union of the lines' typographic bounds (CoreGraphics coordinates), grown by `padding`.
    static func boxRect(_ frame: CTFrame, in frameRect: CGRect, padding: Double) -> CGRect? {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], !lines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)
        var union: CGRect?
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let ink = CTLineGetImageBounds(line, nil)
            let left = frameRect.minX + origin.x + min(ink.minX, 0)
            let rect = CGRect(x: left, y: frameRect.minY + origin.y - descent,
                              width: max(width - CTLineGetTrailingWhitespaceWidth(line), ink.width), height: ascent + descent)
            union = union.map { $0.union(rect) } ?? rect
        }
        return union?.insetBy(dx: -padding, dy: -padding).integral
    }
}
#endif
