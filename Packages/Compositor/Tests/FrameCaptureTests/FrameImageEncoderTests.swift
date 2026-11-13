// FrameImageEncoderTests.swift — REC-001-T07: fixture encoding, the row's acceptance ("Export
// dimensions and alpha policy match selected format"; REC-001-S1, S5). ImageIO only (Mac host and
// simulator); compiled out on Linux.
#if canImport(ImageIO) && canImport(CoreGraphics)
import FrameCapture
import XCTest

final class FrameImageEncoderTests: XCTestCase {
    static let width = 64, height = 48

    /// Half-float bits.
    static let one: UInt16 = 0x3C00, half: UInt16 = 0x3800, zero: UInt16 = 0

    /// The fixture: opaque red (top left), green (top right), blue (bottom left) quadrants and a
    /// half-transparent white region (bottom right, premultiplied (0.5, 0.5, 0.5, 0.5)).
    static func fixture(opaque: Bool = false) -> CapturedPixels {
        var values: [UInt16] = []
        values.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let right = x >= width / 2, bottom = y >= height / 2
                switch (right, bottom) {
                case (false, false): values += [one, zero, zero, one]
                case (true, false): values += [zero, one, zero, one]
                case (false, true): values += [zero, zero, one, one]
                case (true, true): values += opaque ? [one, one, one, one] : [half, half, half, half]
                }
            }
        }
        return CapturedPixels(width: width, height: height, layout: .linearPremultipliedHalfRGBA(values))!
    }

    /// Region centers: red, green, blue, the half-transparent white.
    static let centers = [(16, 12), (48, 12), (16, 36), (48, 36)]

    private func assertClose(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ e: (Int, Int, Int, Int), _ tolerance: Int,
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let got = [Int(p.r), Int(p.g), Int(p.b), Int(p.a)], want = [e.0, e.1, e.2, e.3]
        for c in 0..<4 where abs(got[c] - want[c]) > tolerance {
            XCTFail("\(message): \(got) vs \(want) (± \(tolerance))", file: file, line: line)
            return
        }
    }

    func testPNGKeepsSizeAndStraightAlpha() throws {
        let frame = try FrameImageEncoder.encode(Self.fixture(), as: .png)
        XCTAssertEqual(frame.summary, "png 64x48 alpha")
        let info = try XCTUnwrap(FrameImageEncoder.inspect(frame.data))
        XCTAssertEqual(info.format, .png)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.height, 48)
        XCTAssertTrue(info.hasAlpha)
        let decoded = try XCTUnwrap(FrameImageEncoder.decodeRGBA8(frame.data))
        let expected = [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (255, 255, 255, 128)]
        for (i, (x, y)) in Self.centers.enumerated() { assertClose(decoded.pixel(x: x, y: y), expected[i], 1, "PNG region \(i)") }
        // Every pixel, not just the centers: lossless (the file is the conversion's output ± 1).
        let converted = FrameColorConversion.rgba8(Self.fixture(), policy: .preserveCoverage)
        let worst = zip(decoded.rgba, converted.rgba).map { (a: UInt8, b: UInt8) -> Int in abs(Int(a) - Int(b)) }.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 1)
    }

    func testHEIFIsOpaqueAndFlattenedOntoBlack() throws {
        try XCTSkipUnless(FrameImageEncoder.canEncode(.heif), "This host has no HEIF encoder (recorded; PNG still covered).")
        let frame = try FrameImageEncoder.encode(Self.fixture(), as: .heif)
        XCTAssertEqual(frame.summary, "heif 64x48 opaque")
        let info = try XCTUnwrap(FrameImageEncoder.inspect(frame.data))
        XCTAssertEqual(info.format, .heif)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.height, 48)
        XCTAssertFalse(info.hasAlpha)
        let decoded = try XCTUnwrap(FrameImageEncoder.decodeRGBA8(frame.data))
        // White at 50 % over black is linear 0.5 → sRGB 188 (lossy tolerance ± 12, research REC-001-D4).
        let expected = [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (188, 188, 188, 255)]
        for (i, (x, y)) in Self.centers.enumerated() { assertClose(decoded.pixel(x: x, y: y), expected[i], 12, "HEIF region \(i)") }
    }

    func testOpaqueFramePNGHasNoAlphaChannel() throws {
        let frame = try FrameImageEncoder.encode(Self.fixture(opaque: true), as: .png)
        XCTAssertFalse(frame.hasAlpha)
        XCTAssertEqual(FrameImageEncoder.inspect(frame.data)?.hasAlpha, false)
        // An 8-bit opaque source (native spectrum) is opaque too.
        let bgra = CapturedPixels(width: 2, height: 1, layout: .sRGBBGRA8TopDown([0, 0, 255, 0, 255, 0, 0, 0]))!
        let native = try FrameImageEncoder.encode(bgra, as: .png)
        XCTAssertEqual(native.summary, "png 2x1 opaque")
        let decoded = try XCTUnwrap(FrameImageEncoder.decodeRGBA8(native.data))
        XCTAssertEqual(decoded.rgba, [255, 0, 0, 255, 0, 0, 255, 255])
    }

    /// REC-001-R11, S5: nothing but the image and its color profile.
    func testFilesCarryNoMetadata() throws {
        var formats: [FrameCaptureFormat] = [.png]
        if FrameImageEncoder.canEncode(.heif) { formats.append(.heif) }
        for format in formats {
            let frame = try FrameImageEncoder.encode(Self.fixture(), as: format)
            let properties = try XCTUnwrap(FrameImageEncoder.properties(frame.data))
            for forbidden in ["{GPS}", "{IPTC}", "{MakerApple}", "{ExifAux}"] {
                XCTAssertNil(properties[forbidden], "\(format): \(forbidden)")
            }
            // ImageIO describes the image itself in {Exif} (color space and pixel size); nothing else.
            if let exif = properties["{Exif}"] as? [String: Any] {
                XCTAssertTrue(Set(exif.keys).isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]),
                              "\(format): Exif \(exif.keys.sorted())")
            }
            if let tiff = properties["{TIFF}"] as? [String: Any] {
                for key in ["Make", "Model", "Software", "DateTime", "Artist", "HostComputer"] {
                    XCTAssertNil(tiff[key], "\(format): TIFF \(key)")
                }
            }
            if let png = properties["{PNG}"] as? [String: Any] {
                for key in ["Software", "CreationTime", "Author", "Description", "Comment"] { XCTAssertNil(png[key], "PNG \(key)") }
            }
        }
    }

    func testInvalidDataIsNotAnImage() {
        XCTAssertNil(FrameImageEncoder.inspect(Data([1, 2, 3])))
        XCTAssertTrue(FrameImageEncoder.canEncode(.png))
    }
}
#endif
