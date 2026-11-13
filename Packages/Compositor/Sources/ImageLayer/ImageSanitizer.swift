// ImageSanitizer.swift — the pixels-only copy of an imported image (MED-001-R3 to R5; research
// MED-001-D3, D4; contracts/image-layer.md "Sanitizer").
//
// The picked data goes through the decoder (every check of `ImageDecoding`), and the decoded,
// upright, bounded picture is written as a new file from its pixels alone: PNG when it has
// transparency (lossless, alpha kept), JPEG at quality 0.9 otherwise. No property of the source is
// copied, so the copy carries no location, camera, date, maker, IPTC or XMP data and needs no
// orientation tag. Only the sRGB color profile of the new pixels is written.
import Foundation

/// A stored copy ready to be written: the encoded bytes and what they hold.
public struct SanitizedImage: Sendable, Equatable {
    public let data: Data
    /// `png` or `jpg`.
    public let fileExtension: String
    public let width: Int
    public let height: Int
    public let hasAlpha: Bool
}

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageSanitizer {
    /// JPEG quality of opaque copies (spec Clarifications).
    public static let jpegQuality = 0.9

    /// Reads a local file, at most `maxFileBytes + 1` bytes: `.tooLarge` when there is more,
    /// `.unreadable` when it cannot be opened or read. The caller holds any security scope.
    public static func readBounded(_ url: URL, limits: ImageImportLimits) throws(ImageImportError) -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw .unreadable
        }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: Int(limits.maxFileBytes) + 1) ?? Data()
        } catch {
            throw .unreadable
        }
        guard Int64(data.count) <= limits.maxFileBytes else { throw .tooLarge }
        guard !data.isEmpty else { throw .notAnImage }
        return data
    }

    /// Decodes `data` through `decoder` and re-encodes the pixels alone.
    public static func sanitize(_ data: Data, limits: ImageImportLimits,
                                decoder: any ImageDecoding = ImageIODecoder()) throws(ImageImportError) -> SanitizedImage {
        let decoded = try decoder.decode(data, limits: limits)
        guard let image = makeImage(decoded) else { throw .damaged }
        let type: UTType = decoded.hasAlpha ? .png : .jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw .saveFailed
        }
        let properties: [CFString: Any] = decoded.hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .saveFailed }
        return SanitizedImage(data: output as Data, fileExtension: decoded.hasAlpha ? "png" : "jpg",
                              width: decoded.width, height: decoded.height, hasAlpha: decoded.hasAlpha)
    }

    /// A `CGImage` of the straight-alpha sRGB pixels (alpha skipped when opaque).
    static func makeImage(_ decoded: DecodedImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(decoded.pixels) as CFData) else { return nil }
        let alpha: CGImageAlphaInfo = decoded.hasAlpha ? .last : .noneSkipLast
        return CGImage(width: decoded.width, height: decoded.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: decoded.width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
