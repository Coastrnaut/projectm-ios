// GoldenPNG.swift — golden PNG coding through REC-001's `FrameImageEncoder` (8-bit sRGB, no metadata;
// QA-002-R6). Alpha is written only when some pixel is not opaque, as REC-001's PNG policy does.
#if canImport(ImageIO) && canImport(CoreGraphics)
import FrameCapture
import Foundation
import GoldenImages

public enum GoldenPNG {
    public static func encode(_ image: GoldenImage) throws(FrameCaptureFailure) -> Data {
        var hasAlpha = false
        for i in stride(from: 3, to: image.rgba.count, by: 4) where image.rgba[i] != 255 {
            hasAlpha = true
            break
        }
        let rgba8 = RGBA8Image(width: image.width, height: image.height, rgba: image.rgba, hasAlpha: hasAlpha)
        return try FrameImageEncoder.encode(rgba8, as: .png).data
    }

    public static func decode(_ data: Data) -> GoldenImage? {
        guard let decoded = FrameImageEncoder.decodeRGBA8(data) else { return nil }
        return GoldenImage(width: decoded.width, height: decoded.height, rgba: decoded.rgba)
    }
}
#endif
