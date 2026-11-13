// MED-001-T08, T17: import of still images through ImageIO — the pixels-only stored copy (no GPS,
// EXIF, TIFF, IPTC or XMP), upright, scaled to the stored limit, PNG with alpha / JPEG without, and
// every refusal with its typed error (MED-001-R4, R5, R12, S3, S5). Fixtures are generated here with
// ImageIO (no binary files in the repository). ImageIO only: skipped in the Linux shape.
#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import ImageLayer
import UniformTypeIdentifiers
import XCTest

/// Fixture images built in memory.
enum ImageFixtures {
    struct RGBA { var r, g, b, a: UInt8 }

    /// A `width` × `height` image whose pixel (x, y) is `color(x, y)` (straight alpha, sRGB).
    static func image(width: Int, height: Int, color: (Int, Int) -> RGBA) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var alpha = false
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y), i = (y * width + x) * 4
                bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b; bytes[i + 3] = c.a
                if c.a != 255 { alpha = true }
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: (alpha ? CGImageAlphaInfo.last : .noneSkipLast).rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func solid(_ c: RGBA, width: Int = 64, height: Int = 48) -> CGImage {
        image(width: width, height: height) { _, _ in c }
    }

    /// Encodes `image` as `type` with the given properties (metadata dictionaries included).
    static func encode(_ image: CGImage, _ type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A JPEG with location, camera, date and maker metadata and orientation 6 (stored sideways).
    static func jpegWithMetadata(width: Int = 40, height: Int = 20) -> Data {
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.8584, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 2.2945, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:13 10:00:00",
                                             kCGImagePropertyExifLensModel: "Fixture Lens 26mm"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FixtureMaker", kCGImagePropertyTIFFModel: "Fixture 1"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Fixture City"],
        ]
        return encode(solid(RGBA(r: 200, g: 100, b: 50, a: 255), width: width, height: height), .jpeg, properties: properties)
    }

    /// A PNG whose IHDR claims a 0 × 0 picture (the signature and chunk layout stay valid).
    static func zeroSizePNG() -> Data {
        var png = encode(solid(RGBA(r: 1, g: 2, b: 3, a: 255), width: 8, height: 8), .png)
        for i in 16..<24 { png[i] = 0 }   // IHDR width and height
        return png
    }

    /// The top-level property dictionaries of encoded data.
    static func properties(_ data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}

final class ImageImportTests: XCTestCase {
    private typealias RGBA = ImageFixtures.RGBA
    private let limits = ImageImportLimits.standard
    static let technicalExifKeys: Set<String> = [kCGImagePropertyExifPixelXDimension as String,
                                                 kCGImagePropertyExifPixelYDimension as String, kCGImagePropertyExifColorSpace as String]

    // MARK: - US1: the stored copy holds pixels only (S3, R4)

    func testFixtureReallyCarriesMetadata() {
        let p = ImageFixtures.properties(ImageFixtures.jpegWithMetadata())
        XCTAssertNotNil(p[kCGImagePropertyGPSDictionary], "the fixture has GPS")
        XCTAssertNotNil(p[kCGImagePropertyExifDictionary], "and EXIF")
        XCTAssertEqual((p[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
    }

    func testMetadataIsStrippedAndThePictureStoredUpright() throws {
        let copy = try ImageSanitizer.sanitize(ImageFixtures.jpegWithMetadata(), limits: limits)
        XCTAssertEqual(copy.fileExtension, "jpg", "opaque → JPEG")
        XCTAssertFalse(copy.hasAlpha)
        XCTAssertEqual(copy.width, 20, "orientation 6 applied: the 40 × 20 picture is upright 20 × 40")
        XCTAssertEqual(copy.height, 40)
        let p = ImageFixtures.properties(copy.data)
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyExifAuxDictionary, kCGImagePropertyMakerAppleDictionary] {
            XCTAssertNil(p[key], "no \(key) in the stored copy: \(p)")
        }
        XCTAssertNil(p[kCGImagePropertyOrientation], "no orientation tag")
        // ImageIO's JPEG writer always adds three technical EXIF fields describing the new pixels
        // (pixel dimensions and color space); nothing of the original (date, lens, location) remains.
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertTrue(Set(exif.keys.map { $0 as String }).isSubset(of: Self.technicalExifKeys), "only technical EXIF: \(exif)")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(copy.data as CFData, nil))
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []
            let names = tags.map { "\((CGImageMetadataTagCopyPrefix($0) as String?) ?? ""):\((CGImageMetadataTagCopyName($0) as String?) ?? "")" }
            XCTAssertTrue(names.allSatisfy { ["exif:PixelXDimension", "exif:PixelYDimension", "exif:ColorSpace"].contains($0) },
                          "no XMP camera, date or location tags: \(names)")
        }
        let text = String(decoding: copy.data, as: UTF8.self)
        for secret in ["Fixture Lens", "FixtureMaker", "Fixture City", "2026:11:13"] {
            XCTAssertFalse(text.contains(secret), "\(secret) is not anywhere in the stored bytes")
        }
        let decoded = try ImageIODecoder().decode(copy.data, limits: limits)
        let center = (20 * 20 + 10) * 4
        XCTAssertEqual(Int(decoded.pixels[center]), 200, accuracy: 3, "the pixels survive (red)")
        XCTAssertEqual(Int(decoded.pixels[center + 2]), 50, accuracy: 3, "(blue)")
    }

    func testTransparencyIsKeptAsPNG() throws {
        let half = ImageFixtures.image(width: 16, height: 16) { x, _ in x < 8 ? RGBA(r: 0, g: 0, b: 255, a: 128) : RGBA(r: 255, g: 0, b: 0, a: 255) }
        let copy = try ImageSanitizer.sanitize(ImageFixtures.encode(half, .png), limits: limits)
        XCTAssertEqual(copy.fileExtension, "png")
        XCTAssertTrue(copy.hasAlpha)
        let decoded = try ImageIODecoder().decode(copy.data, limits: limits)
        XCTAssertEqual(decoded.pixels[3], 128, "alpha kept")
        XCTAssertEqual(decoded.pixels[2], 255, "straight (not premultiplied) color")
        XCTAssertEqual(decoded.pixels[(8) * 4 + 3], 255)
    }

    func testLargePictureIsScaledToTheStoredLimit() throws {
        let small = ImageImportLimits(maxFileBytes: limits.maxFileBytes, maxPixelCount: limits.maxPixelCount, maxStoredLongestSide: 64)
        let wide = ImageFixtures.solid(RGBA(r: 10, g: 20, b: 30, a: 255), width: 500, height: 10)
        let copy = try ImageSanitizer.sanitize(ImageFixtures.encode(wide, .png), limits: small)
        XCTAssertEqual(copy.width, 64)
        XCTAssertLessThanOrEqual(abs(copy.height - 1), 1, "aspect kept: 500 × 10 → 64 × ~1")
    }

    func testSolidColorDecodesToItsCode() throws {
        let decoded = try ImageIODecoder().decode(ImageFixtures.encode(ImageFixtures.solid(RGBA(r: 188, g: 188, b: 188, a: 255)), .png),
                                                  limits: limits)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        XCTAssertFalse(decoded.hasAlpha)
        XCTAssertTrue(decoded.pixels.enumerated().allSatisfy { $0.offset % 4 == 3 ? $0.element == 255 : $0.element == 188 })
    }

    // MARK: - US4: refusals (S5, R5, R12)

    private func assertRefused(_ data: Data, limits: ImageImportLimits? = nil, _ expected: ImageImportError,
                               file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try ImageSanitizer.sanitize(data, limits: limits ?? self.limits)
            XCTFail("accepted; expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testOversizedDataIsRefusedBeforeDecoding() {
        assertRefused(Data(count: 41 * 1024 * 1024), .tooLarge)
    }

    func testTextIsNotAnImage() {
        assertRefused(Data("not an image, just text".utf8), .notAnImage)
        assertRefused(Data(), .notAnImage)
    }

    /// What ImageIO itself can tell is broken: half a JPEG, and a PNG whose header claims a zero
    /// size. ImageIO decodes a PNG cut short without complaint (the missing rows come out empty and
    /// its status reads "complete"), so that case is MED-014's (safe media decoder) to harden.
    func testDamagedImagesAreRefused() {
        let jpeg = ImageFixtures.jpegWithMetadata(width: 64, height: 64)
        assertRefused(jpeg.prefix(jpeg.count / 2), .damaged)
        assertRefused(ImageFixtures.zeroSizePNG(), .damaged)
    }

    func testTooManyPixelsIsRefused() {
        let tight = ImageImportLimits(maxFileBytes: limits.maxFileBytes, maxPixelCount: 64 * 48 - 1, maxStoredLongestSide: 4096)
        assertRefused(ImageFixtures.encode(ImageFixtures.solid(RGBA(r: 1, g: 2, b: 3, a: 255)), .png), limits: tight, .tooManyPixels)
    }

    func testBoundedReadOfFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try ImageSanitizer.readBounded(directory.appendingPathComponent("missing.png"), limits: limits)) {
            XCTAssertEqual($0 as? ImageImportError, .unreadable)
        }
        let big = directory.appendingPathComponent("big.bin")
        try Data(count: 2048).write(to: big)
        let tiny = ImageImportLimits(maxFileBytes: 1024, maxPixelCount: 1, maxStoredLongestSide: 1)
        XCTAssertThrowsError(try ImageSanitizer.readBounded(big, limits: tiny)) { XCTAssertEqual($0 as? ImageImportError, .tooLarge) }
        XCTAssertEqual(try ImageSanitizer.readBounded(big, limits: limits).count, 2048)
    }
}
#endif
