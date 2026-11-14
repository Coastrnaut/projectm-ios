// PresetColorPNG.swift — roadmap PRE-004: decodes a thumbnail PNG to RGBA8 for the palette
// (research PRE-004-D8). Apple platforms only (ImageIO, CoreGraphics); the Linux build keeps the
// palette from raw RGBA (spec PRE-004-R12).
#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import Foundation
import ImageIO

public enum PresetColorPNG {
    /// RGBA8 rows (top first) of the first image in `data`; nil when it cannot be decoded.
    public static func rgba(_ data: Data) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width: Int = image.width, height: Int = image.height
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        var pixels: [UInt8] = Array(repeating: 0, count: width * height * 4)
        let space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }

    /// The dominant families of a thumbnail PNG; `[]` when it cannot be decoded.
    public static func dominantFamilies(_ data: Data) -> [PresetColorFamily] {
        guard let decoded = rgba(data) else { return [] }
        return PresetColorPalette.dominantFamilies(rgba: decoded.pixels, width: decoded.width, height: decoded.height)
    }
}
#endif
