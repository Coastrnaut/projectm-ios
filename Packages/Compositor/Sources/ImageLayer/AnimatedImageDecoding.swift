// AnimatedImageDecoding.swift — recognising, decoding and re-encoding animated images with ImageIO (MED-008-R1 to R3;
// specs/257-med-008-animated-images, contracts/animated-image.md A1; research MED-008-D1, D2).
//
// * `AnimatedImageProbe`: a source is animated when it holds more than one picture and its first picture states a
//   frame delay in the GIF, PNG (APNG), HEICS or WebP dictionary. The unclamped delay is preferred. Any other
//   multi-picture file (a HEIC with several images, a multi-page TIFF) stays a still.
// * `AnimatedImageFrames`: one frame as an upright sRGB picture at most `maxSide` long (ImageIO's thumbnail, which
//   composes partial GIF/APNG frames onto the canvas), through MED-001's `ImageIODecoder.pixels(of:)`.
// * `AnimatedImageSanitizer`: the stored copy of an animation, an APNG of pixels and delays only (loop count 0; no
//   comment, XMP, location or camera data), at most 600 frames and 32 M stored pixels; re-encoded at half the pixels
//   (at most twice) while it is over the file size limit, then `.tooLarge`. CGImageDestination keeps every frame until
//   `Finalize`, which the total-pixel cap bounds (research MED-008-D2).
import Foundation

/// What ImageIO says about an animated picture.
public struct AnimatedImageFacts: Sendable, Equatable {
    public let frameCount: Int
    public let width: Int
    public let height: Int
    /// The delay each frame states (seconds; nil: none stated).
    public let rawDelays: [Double?]
}

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum AnimatedImageProbe {
    /// The format dictionaries and their (unclamped, clamped) delay keys.
    private static var delayKeys: [(dictionary: CFString, unclamped: CFString, clamped: CFString)] { [
        (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
        (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
    ] }

    /// The facts of an animated source; nil for a still (one picture, or no frame delay on the first).
    public static func facts(_ source: CGImageSource) -> AnimatedImageFacts? {
        let count: Int = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let first = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              case .some = delay(first),
              let width = (first[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (first[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        var delays: [Double?] = []
        delays.reserveCapacity(count)
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any]
            delays.append(properties.flatMap { (p: [CFString: Any]) -> Double? in delay(p) ?? nil })
        }
        return AnimatedImageFacts(frameCount: count, width: width, height: height, rawDelays: delays)
    }

    /// The facts of animated data; nil for a still or data ImageIO cannot read.
    public static func facts(_ data: Data) -> AnimatedImageFacts? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return facts(source)
    }

    /// `.some(delay)` when a format dictionary is present (the delay itself may be absent); nil without one.
    static func delay(_ properties: [CFString: Any]) -> Double?? {
        for keys in delayKeys {
            guard let dictionary = properties[keys.dictionary] as? [CFString: Any] else { continue }
            let unclamped: Double? = (dictionary[keys.unclamped] as? NSNumber)?.doubleValue
            let clamped: Double? = (dictionary[keys.clamped] as? NSNumber)?.doubleValue
            guard unclamped != nil || clamped != nil else { continue }
            if let unclamped, unclamped > 0 { return .some(unclamped) }
            return .some(clamped ?? unclamped)
        }
        return nil
    }
}

public enum AnimatedImageFrames {
    /// Frame `index` of `source`, upright, at most `maxSide` px long, as ImageIO composes it (nil when it cannot be
    /// decoded).
    public static func image(_ source: CGImageSource, index: Int, maxSide: Int) -> CGImage? {
        guard index >= 0, index < CGImageSourceGetCount(source) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceShouldCacheImmediately: true,
                       kCGImageSourceShouldCache: false,
                       kCGImageSourceThumbnailMaxPixelSize: max(maxSide, 1)] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options), image.width > 0, image.height > 0
        else { return nil }
        return image
    }

    /// Frame `index` as RGBA8 sRGB straight-alpha pixels (the photo layer's `DecodedImage`).
    public static func decode(_ source: CGImageSource, index: Int, maxSide: Int) -> DecodedImage? {
        guard let image = image(source, index: index, maxSide: maxSide) else { return nil }
        return ImageIODecoder.pixels(of: image)
    }
}

public enum AnimatedImageSanitizer {
    /// The APNG copy of an animation whose first frame passed `ImageIODecoder`'s checks.
    public static func sanitize(_ source: CGImageSource, facts: AnimatedImageFacts, limits: ImageImportLimits,
                                animation: AnimatedImportLimits = .standard) throws(ImageImportError) -> SanitizedImage {
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw .damaged }
        let frames: Int = min(facts.frameCount, animation.maxFrames)
        var factor: Double = 1
        for _ in 0..<3 {
            let size: (width: Int, height: Int) = animation.storedSize(width: facts.width, height: facts.height, frames: frames,
                                                                       base: limits, pixelFactor: factor)
            let data: Data = try encode(source, facts: facts, frames: frames, width: size.width, height: size.height)
            if Int64(data.count) <= limits.maxFileBytes {
                return SanitizedImage(data: data, fileExtension: "png", width: size.width, height: size.height, hasAlpha: true)
            }
            factor /= 2
        }
        throw .tooLarge
    }

    /// Frames 0..<frames drawn into `width` × `height` sRGB canvases, written as an APNG with the stated delays.
    static func encode(_ source: CGImageSource, facts: AnimatedImageFacts, frames: Int, width: Int,
                       height: Int) throws(ImageImportError) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw .saveFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString,
                                                                 frames, nil) else { throw .saveFailed }
        let container: [CFString: Any] = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]]
        CGImageDestinationSetProperties(destination, container as CFDictionary)
        for index in 0..<frames {
            guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
                  let frame = AnimatedImageFrames.image(source, index: index, maxSide: max(width, height)),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw .damaged
            }
            context.interpolationQuality = .high
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let pixels = context.makeImage() else { throw .damaged }
            let delay: Double = index < facts.rawDelays.count ? (facts.rawDelays[index] ?? 0) : 0
            let properties: [CFString: Any] = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
            CGImageDestinationAddImage(destination, pixels, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw .saveFailed }
        return output as Data
    }
}
#endif
