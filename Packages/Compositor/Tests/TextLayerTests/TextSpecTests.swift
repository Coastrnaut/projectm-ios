// MED-009-T06: the plain-Swift parts of the text layer (MED-009-R3 to R6, R10, S3, S4, S6). Every
// host, Linux shape included.
import Foundation
import TextLayer
import XCTest

final class TextSpecTests: XCTestCase {
    // MARK: Cleaning (S4)

    func testControlCharactersAreRemovedOrConverted() {
        XCTAssertEqual(TextSanitizer.clean("a\tb").message, "a b", "tab → space")
        XCTAssertEqual(TextSanitizer.clean("a\u{7}b\u{1B}c\u{0}d\u{7F}e\u{85}f").message, "abcdef", "BEL, ESC, NUL, DEL, NEL removed")
        XCTAssertEqual(TextSanitizer.clean("a\r\nb\rc\u{2028}d\u{2029}e").message, "a\nb\nc\nd\ne", "every line break kind → LF")
        XCTAssertEqual(TextSanitizer.clean("one\ntwo").message, "one\ntwo", "LF kept")
    }

    func testFormatCharactersNeededByScriptsAndEmojiAreKept() {
        let family = "👨\u{200D}👩\u{200D}👧"
        XCTAssertEqual(TextSanitizer.clean(family).message, family, "ZWJ kept")
        XCTAssertEqual(TextSanitizer.clean("\u{200F}abc").message, "\u{200F}abc", "RLM kept")
        XCTAssertEqual(TextSanitizer.clean("❤\u{FE0F}").message, "❤\u{FE0F}", "VS16 kept")
        XCTAssertEqual(TextSanitizer.clean("e\u{301}").message.unicodeScalars.count, 2, "combining mark kept")
    }

    // MARK: Limits (S3)

    func testLimitCountsGraphemeClustersAndNeverSplitsOne() {
        let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦\u{1F3FD}"   // several scalars, one character
        let long = String(repeating: family, count: 281)
        let cleaned = TextSanitizer.clean(long)
        XCTAssertTrue(cleaned.wasCut)
        XCTAssertEqual(cleaned.message.count, 280, "280 characters kept")
        XCTAssertEqual(cleaned.message, String(repeating: family, count: 280), "each one whole")
        XCTAssertFalse(TextSanitizer.clean(String(repeating: family, count: 280)).wasCut, "280 fit")

        let accented = String(repeating: "e\u{301}\u{323}", count: 300)
        let cut = TextSanitizer.clean(accented).message
        XCTAssertEqual(cut.count, 280)
        XCTAssertEqual(cut.unicodeScalars.count, 840, "marks stay with their letter")
    }

    func testLinesAfterTheEighthBecomeSpaces() {
        let ten = (1...10).map(String.init).joined(separator: "\n")
        let cleaned = TextSanitizer.clean(ten).message
        XCTAssertEqual(cleaned.split(separator: "\n", omittingEmptySubsequences: false).count, 8)
        XCTAssertTrue(cleaned.hasSuffix("8 9 10"))
        XCTAssertTrue(TextSanitizer.isBlank(" \n \n"))
        XCTAssertFalse(TextSanitizer.isBlank(" a "))
    }

    // MARK: Direction (R6)

    func testDirectionComesFromTheFirstStrongLetter() {
        XCTAssertEqual(TextDirection.of("Hello"), .leftToRight)
        XCTAssertEqual(TextDirection.of("مرحبا"), .rightToLeft, "Arabic")
        XCTAssertEqual(TextDirection.of("שלום"), .rightToLeft, "Hebrew")
        XCTAssertEqual(TextDirection.of("123 !?"), .leftToRight, "no strong letter")
        XCTAssertEqual(TextDirection.of("👋🏽 ٣ مرحبا Hello"), .rightToLeft, "emoji and Arabic digits are not strong")
        XCTAssertEqual(TextDirection.of("Hello 👋🏽 مرحبا"), .leftToRight, "mixed, Latin first")
        XCTAssertEqual(TextDirection.of("\u{200F}Hello"), .rightToLeft, "RLM first")
        XCTAssertEqual(TextDirection.of("你好"), .leftToRight, "CJK")
        XCTAssertEqual(TextAlignmentChoice.leading.side(for: .rightToLeft), .right)
        XCTAssertEqual(TextAlignmentChoice.trailing.side(for: .rightToLeft), .left)
        XCTAssertEqual(TextAlignmentChoice.leading.side(for: .leftToRight), .left)
        XCTAssertEqual(TextAlignmentChoice.trailing.side(for: .leftToRight), .right)
        XCTAssertEqual(TextAlignmentChoice.center.side(for: .rightToLeft), .center)
    }

    // MARK: Spec and storage (R5, R10, S6)

    func testSpecClampsEveryValue() {
        var spec = TextOverlaySpec(message: "a\u{7}", size: 9, outlineWidth: -1)
        XCTAssertEqual(spec.message, "a")
        XCTAssertEqual(spec.size, 0.25)
        XCTAssertEqual(spec.outlineWidth, 0)
        spec.size = .nan
        XCTAssertEqual(spec.size, TextOverlaySpec.defaultSize)
        spec.outlineWidth = 0.5
        XCTAssertEqual(spec.outlineWidth, 0.15)
        XCTAssertEqual(TextColor(red: 2, green: -1, blue: .nan, alpha: 0.5), TextColor(red: 1, green: 0, blue: 1, alpha: 0.5))
        XCTAssertTrue(spec.setMessage(String(repeating: "x", count: 300)))
        XCTAssertEqual(spec.message.count, 280)
        let d = TextOverlaySpec.default
        XCTAssertEqual([d.message, d.font.rawValue, d.weight.rawValue, d.alignment.rawValue, d.verticalPosition.rawValue],
                       ["", "system", "bold", "center", "middle"])
        XCTAssertEqual(d.size, 0.08)
        XCTAssertEqual(d.outlineWidth, 0.06)
        XCTAssertEqual(d.color, .white)
        XCTAssertEqual(d.outlineColor, .black)
        XCTAssertFalse(d.showsBox)
        XCTAssertTrue(d.isEmpty)
    }

    func testStoredRoundTripIsExactAndVersioned() throws {
        let spec = TextOverlaySpec(message: "Hello 👋🏽 مرحبا\nline two", font: .georgia, weight: .heavy, size: 0.1234567,
                                   color: TextColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4), alignment: .trailing,
                                   verticalPosition: .bottom, outlineWidth: 0.1, outlineColor: TextColor(red: 1, green: 0, blue: 0),
                                   showsBox: true, boxColor: TextColor(red: 0, green: 0, blue: 1, alpha: 0.25))
        let data = spec.encodedForStorage()
        XCTAssertEqual(TextOverlaySpec.decodeStored(data), .spec(spec))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"version\":1"), json)
        XCTAssertEqual(data, spec.encodedForStorage(), "sorted keys: the same bytes each time")
    }

    func testUnknownVersionDamagedValuesAndUnknownChoices() {
        XCTAssertEqual(TextOverlaySpec.decodeStored(Data(#"{"version":2,"message":"x"}"#.utf8)), .unsupportedVersion(2))
        XCTAssertEqual(TextOverlaySpec.decodeStored(Data("not json".utf8)), .damaged)
        XCTAssertEqual(TextOverlaySpec.decodeStored(Data(#"{"message":"no version"}"#.utf8)), .damaged)
        XCTAssertEqual(TextOverlaySpec.decodeStored(Data(#"{"version":1,"size":"big"}"#.utf8)), .damaged)
        XCTAssertEqual(TextOverlaySpec.decodeStored(Data()), .damaged)
        let lenient = TextOverlaySpec.decodeStored(Data(#"{"version":1,"message":"hi\u0007","font":"comicSans","size":7}"#.utf8))
        XCTAssertEqual(lenient, .spec(TextOverlaySpec(message: "hi", font: .system, size: 0.25)), "unknown font → default, clamped, cleaned")
    }

    // MARK: Layout

    func testLayoutKeepsTheCanvasInsideThePicture() {
        let spec = TextOverlaySpec(message: "x", size: 0.25, outlineWidth: 0.15, showsBox: true)
        let layout = TextLayout(spec: spec, pictureWidth: 400, pictureHeight: 200)
        XCTAssertEqual(layout.fontPixels, 50)
        XCTAssertEqual(layout.areaX, 20)
        XCTAssertEqual(layout.areaWidth, 360)
        XCTAssertEqual(layout.padding, 15, "max(7.5 outline, 12.5 box) rounded up + 2")
        for position in TextVerticalPosition.allCases {
            let c = layout.canvas(frameHeight: 10_000, position: position)
            XCTAssertGreaterThanOrEqual(c.x, 0)
            XCTAssertGreaterThanOrEqual(c.y, 0)
            XCTAssertLessThanOrEqual(c.x + c.width, 400)
            XCTAssertLessThanOrEqual(c.y + c.height, 200)
            XCTAssertEqual(c.frameHeight, 180, "frame clamped to 90 % of the height")
        }
        let top = layout.canvas(frameHeight: 50, position: .top), bottom = layout.canvas(frameHeight: 50, position: .bottom)
        XCTAssertEqual(Double(top.y) + top.frameY, 10, "5 % from the top")
        XCTAssertEqual(Double(bottom.y) + bottom.frameY + 50, 190, "5 % from the bottom")
    }

    // MARK: Rendering helpers

    func testChecksumAndInkBounds() {
        var pixels = [UInt8](repeating: 0, count: 4 * 3 * 4)
        let a = TextRendering(pictureWidth: 10, pictureHeight: 10, x: 1, y: 2, width: 4, height: 3, pixels: pixels)
        XCTAssertNil(a.inkBounds)
        pixels[(1 * 4 + 2) * 4 + 3] = 1
        let b = TextRendering(pictureWidth: 10, pictureHeight: 10, x: 1, y: 2, width: 4, height: 3, pixels: pixels)
        XCTAssertEqual(b.inkBounds, TextPixelBounds(minX: 2, minY: 1, maxX: 2, maxY: 1))
        XCTAssertNotEqual(a.checksum, b.checksum, "one byte changes it")
        XCTAssertEqual(b.checksum, TextRendering(pictureWidth: 10, pictureHeight: 10, x: 1, y: 2, width: 4, height: 3, pixels: pixels).checksum)
        let moved = TextRendering(pictureWidth: 10, pictureHeight: 10, x: 2, y: 2, width: 4, height: 3, pixels: pixels)
        XCTAssertNotEqual(b.checksum, moved.checksum, "the place counts")
        XCTAssertEqual(b.checksumText.count, 16)
    }

    func testHalfFloatConversion() {
        XCTAssertEqual(HalfFloat.bits(0), 0)
        XCTAssertEqual(HalfFloat.bits(1), 0x3C00)
        XCTAssertEqual(HalfFloat.bits(0.5), 0x3800)
        XCTAssertEqual(HalfFloat.bits(-2), 0xC000)
        XCTAssertEqual(HalfFloat.bits(65504), 0x7BFF)
        XCTAssertEqual(HalfFloat.bits(1e6), 0x7C00, "overflow → infinity")
        XCTAssertEqual(HalfFloat.bits(0x1p-24), 0x0001, "smallest subnormal")
        XCTAssertEqual(HalfFloat.bits(0x1p-26), 0, "underflow")
        for value: Float in [0, 0.001, 0.0396, 0.2140, 0.5, 0.75, 1] {
            XCTAssertEqual(HalfFloat.float(HalfFloat.bits(value)), value, accuracy: value / 1024 + 1e-7)
        }
        // An opaque white pixel and a half-covered sRGB 188 gray.
        let r = TextRendering(pictureWidth: 2, pictureHeight: 1, x: 0, y: 0, width: 2, height: 1,
                              pixels: [255, 255, 255, 255, 94, 94, 94, 128])
        let h = r.linearHalfPixels().map(HalfFloat.float)
        XCTAssertEqual(Array(h[0..<4]), [1, 1, 1, 1])
        XCTAssertEqual(h[7], 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(h[4], 0.4969 * 128.0 / 255, accuracy: 0.001, "linear(sRGB 187) × alpha")
    }
}
