// ImageDecoding.swift — the decoder boundary for still images (MED-001-R5, R12; research MED-001-D4,
// D5, D6; contracts/image-layer.md "Decoder boundary").
//
// `ImageDecoding` is the seam MED-014 (safe media decoder) hardens: the importer and the layer only
// ever decode through it, so a stricter decoder (memory budget, format allow-list) replaces this one
// without touching them. `DecodedImage` is plain Swift (Linux shape); `ImageIODecoder` needs ImageIO.
//
// ImageIODecoder, in order of cost (each failure is typed):
//   1. size: data longer than `maxFileBytes` → `.tooLarge`, before ImageIO sees it;
//   1a. structure (MED-014-R1 to R5): `ImageHeaderSniffer` checks PNG, JPEG and HEIF before ImageIO
//      (no bytes → `.notAnImage`; cut short, bad checksum, illegal field → `.damaged`), and a size
//      stated in the header over `maxPixelCount` → `.tooManyPixels` before any decoding. Other
//      formats (GIF, TIFF/DNG, WebP…) go on to ImageIO's checks below;
//   2. type: ImageIO must recognise an image type with at least one picture → `.notAnImage`;
//   3. integrity: ImageIO's status must be complete → `.damaged` (it misses a PNG cut short, which
//      step 1a catches);
//   4. pixel count: width × height from the picture's properties (only those two numbers are read;
//      no other metadata) > `maxPixelCount` → `.tooManyPixels`;
//   5. decode: an upright (orientation applied) picture at most `maxStoredLongestSide` long, drawn
//      into 8-bit RGBA sRGB (wide-gamut colors are converted, out-of-gamut clipped) and returned
//      with straight (non-premultiplied) alpha → `.damaged` when ImageIO cannot decode it.
// Only the first picture of a multi-picture file is used (animation is MED-008).
import Foundation
import MediaSniffing

/// An upright picture: RGBA8, sRGB-encoded, straight alpha, row 0 at the top, `width × 4` bytes per row.
public struct DecodedImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    /// False when every pixel is opaque.
    public let hasAlpha: Bool

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
        var opaque = true
        var i = 3
        while i < pixels.count {
            if pixels[i] != 255 { opaque = false; break }
            i += 4
        }
        hasAlpha = !opaque
    }
}

/// Decodes untrusted image data into a bounded, upright picture (the MED-014 seam).
public protocol ImageDecoding: Sendable {
    func decode(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) -> DecodedImage
}

/// The structure and header-size checks of `ImageIODecoder` (MED-014-R1 to R5), plain Swift.
public enum ImageStructureCheck {
    /// Throws the typed error for malformed bytes or a header size over the pixel limit.
    public static func check(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) {
        let facts: ImageHeaderFacts
        do throws(MediaSniffError) {
            facts = try ImageHeaderSniffer.sniff(data)
        } catch {
            switch error {
            case .empty, .unrecognized: throw .notAnImage
            case .truncated, .corrupt, .unreadable: throw .damaged
            }
        }
        if let pixels = facts.pixelCount, pixels > limits.maxPixelCount { throw .tooManyPixels }
    }
}

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The system decoder (ImageIO): every still format iOS reads (JPEG, PNG, HEIC, TIFF, GIF, WebP…).
public struct ImageIODecoder: ImageDecoding {
    public init() {}

    public func decode(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) -> DecodedImage {
        let image = try Self.uprightImage(data, limits: limits)
        guard let decoded = Self.pixels(of: image) else { throw .damaged }
        return decoded
    }

    /// Steps 1-5 up to the upright, bounded `CGImage`.
    static func uprightImage(_ data: Data, limits: ImageImportLimits) throws(ImageImportError) -> CGImage {
        guard Int64(data.count) <= limits.maxFileBytes else { throw .tooLarge }
        try ImageStructureCheck.check(data, limits: limits)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier), type.conforms(to: .image),
              CGImageSourceGetCount(source) >= 1 else { throw .notAnImage }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw .damaged }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw .damaged }
        guard width.multipliedReportingOverflow(by: height).partialValue <= limits.maxPixelCount,
              !width.multipliedReportingOverflow(by: height).overflow else { throw .tooManyPixels }
        let longest = min(max(width, height), limits.maxStoredLongestSide)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceThumbnailMaxPixelSize: longest] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.width > 0, image.height > 0,
              max(image.width, image.height) <= limits.maxStoredLongestSide else { throw .damaged }
        return image
    }

    /// Draws `image` into RGBA8 sRGB (premultiplied, the only 8-bit RGBA bitmap CoreGraphics draws
    /// into) and un-premultiplies, so the GPU can linearise the color before multiplying by alpha.
    static func pixels(of image: CGImage) -> DecodedImage? {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var i = 0
        while i < pixels.count {
            let a = Int(pixels[i + 3])
            if a != 255 {
                if a == 0 {
                    pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0
                } else {
                    for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Int(pixels[i + c]) * 255 + a / 2) / a)) }
                }
            }
            i += 4
        }
        return DecodedImage(width: width, height: height, pixels: pixels)
    }
}
#endif
