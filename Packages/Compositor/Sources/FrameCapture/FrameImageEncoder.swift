// FrameImageEncoder.swift — REC-001 PNG/HEIF encoding with ImageIO and read-back (spec REC-001-R5,
// R6, R9, R11; research REC-001-D4, D5). Compiles out where ImageIO is missing (Linux).
//
// The image is an sRGB `CGImage` (8 bits per component; straight alpha `last`, or `noneSkipLast`).
// The only destination property is HEIF's lossy quality: no EXIF, TIFF, GPS, IPTC or date is
// written, so the file carries the pixels and the sRGB profile only.
#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import Foundation
import ImageIO

/// What a file says about itself, read back with ImageIO (tests, the DEBUG probe).
public struct FrameImageInfo: Sendable, Equatable {
    public let typeIdentifier: String
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool
    /// Top-level property dictionary keys (for example "{PNG}", "{TIFF}", "{Exif}", "{GPS}").
    public let propertyKeys: [String]

    /// The format, when it is one Save Frame writes.
    public var format: FrameCaptureFormat? { FrameCaptureFormat.allCases.first { $0.typeIdentifier == typeIdentifier } }

    /// "png 64x48 alpha" — compare with `CapturedFrame.summary`.
    public var summary: String {
        "\(format?.rawValue ?? typeIdentifier) \(width)x\(height) \(hasAlpha ? "alpha" : "opaque")"
    }
}

public enum FrameImageEncoder {
    /// Whether ImageIO on this device can write `format` (HEIF needs an encoder; REC-001 edge cases).
    public static func canEncode(_ format: FrameCaptureFormat) -> Bool {
        guard let types = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return false }
        return types.contains(format.typeIdentifier)
    }

    /// Converts `pixels` per the format's alpha policy and encodes them (REC-001-R5 to R7, R9).
    public static func encode(_ pixels: CapturedPixels, as format: FrameCaptureFormat) throws(FrameCaptureFailure) -> CapturedFrame {
        try encode(FrameColorConversion.rgba8(pixels, policy: format.alphaPolicy), as: format)
    }

    /// Encodes converted pixels. HEIF never carries alpha (flattened by the conversion).
    public static func encode(_ image: RGBA8Image, as format: FrameCaptureFormat) throws(FrameCaptureFailure) -> CapturedFrame {
        guard canEncode(format) else { throw .formatUnavailable(format) }
        let hasAlpha = image.hasAlpha && format.alphaPolicy == .preserveCoverage
        guard let cgImage = makeCGImage(image, alpha: hasAlpha) else { throw .encodingFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, format.typeIdentifier as CFString, 1, nil) else {
            throw .encodingFailed
        }
        var properties: [CFString: Any] = [:]
        if let quality = format.lossyQuality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return CapturedFrame(format: format, width: image.width, height: image.height, hasAlpha: hasAlpha, data: output as Data)
    }

    static func makeCGImage(_ image: RGBA8Image, alpha: Bool) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(image.rgba) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: (alpha ? CGImageAlphaInfo.last : CGImageAlphaInfo.noneSkipLast).rawValue)
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The file's type, size, alpha flag and top-level property keys; nil if ImageIO cannot read it.
    public static func inspect(_ data: Data) -> FrameImageInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        let hasAlpha = (properties[kCGImagePropertyHasAlpha as String] as? Bool) ?? false
        return FrameImageInfo(typeIdentifier: type, width: width, height: height, hasAlpha: hasAlpha,
                              propertyKeys: properties.keys.sorted())
    }

    /// The full property dictionary of the first image (metadata tests).
    public static func properties(_ data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }

    /// Decodes a file into 8-bit sRGB straight RGBA, top-down (tests and verification). Pixels with
    /// alpha are read from a premultiplied context and unpremultiplied (±1 rounding).
    public static func decodeRGBA8(_ data: Data) -> RGBA8Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = image.width, h = image.height
        // Exact path: an 8-bit straight RGBA image (how ImageIO decodes a PNG with alpha) is copied as is.
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32, image.alphaInfo == .last,
           image.bitmapInfo.intersection(.byteOrderMask).rawValue == 0 || image.bitmapInfo.contains(.byteOrder32Big),
           image.colorSpace?.name == CGColorSpace.sRGB,
           let raw = image.dataProvider?.data as Data? {
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let row = image.bytesPerRow
            raw.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                for y in 0..<h { for x in 0..<(w * 4) { bytes[y * w * 4 + x] = src[y * row + x] } }
            }
            return RGBA8Image(width: w, height: h, rgba: bytes, hasAlpha: true)
        }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let hasAlpha = (inspect(data)?.hasAlpha) ?? false
        if hasAlpha {
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let a = Int(bytes[i + 3])
                guard a > 0, a < 255 else { continue }
                for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + a / 2) / a)) }
            }
        }
        return RGBA8Image(width: w, height: h, rgba: bytes, hasAlpha: hasAlpha)
    }
}
#endif
