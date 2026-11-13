// MED-009-T09, T11, T18, T19: the CoreText rasterizer (MED-009-R2, R5 to R8; S1, S2). Pictures are
// small (320 × 160 or 200 × 100) so each test stays well under a second.
#if canImport(CoreText) && canImport(CoreGraphics)
import TextLayer
import XCTest

final class TextRasterizerTests: XCTestCase {
    private func render(_ spec: TextOverlaySpec, _ width: Int = 320, _ height: Int = 160,
                        file: StaticString = #filePath, line: UInt = #line) throws -> TextRendering {
        try XCTUnwrap(TextRasterizer.render(spec, pictureWidth: width, pictureHeight: height), "rendered", file: file, line: line)
    }

    /// The ink's horizontal center in picture pixels, as a share of the picture width.
    private func inkCenter(_ r: TextRendering) throws -> Double {
        let ink = try XCTUnwrap(r.inkBounds, "ink")
        return (Double(r.x) + Double(ink.minX + ink.maxX) / 2) / Double(r.pictureWidth)
    }

    private func pixel(_ r: TextRendering, _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * r.width + x) * 4
        return Array(r.pixels[i..<(i + 4)])
    }

    // MARK: US2 — determinism (S1)

    func testSameSpecGivesIdenticalBytesAndAStoredSpecRendersIdentically() throws {
        let spec = TextOverlaySpec(message: "Hello 👋🏽 مرحبا", font: .avenirNext, weight: .heavy, size: 0.12, showsBox: true)
        let first = try render(spec), second = try render(spec)
        XCTAssertEqual(first.pixels, second.pixels, "byte-identical")
        XCTAssertEqual(first.checksum, second.checksum)
        guard case .spec(let restored) = TextOverlaySpec.decodeStored(spec.encodedForStorage()) else { return XCTFail("decodes") }
        let third = try render(restored)
        XCTAssertEqual(third, first, "save → JSON → load → identical rendering")
        var changed = spec
        changed.color = TextColor(red: 1, green: 0.9, blue: 1)
        XCTAssertNotEqual(try render(changed).checksum, first.checksum, "one field changes the checksum")
    }

    // MARK: US1 — style

    func testInkIsTheTextColorAndOnlyInsideTheCanvas() throws {
        let spec = TextOverlaySpec(message: "IIII", size: 0.25, color: TextColor(red: 1, green: 0, blue: 0), outlineWidth: 0)
        let r = try render(spec)
        let ink = try XCTUnwrap(r.inkBounds)
        XCTAssertGreaterThan(ink.maxX - ink.minX, 10)
        XCTAssertGreaterThanOrEqual(r.x, 0)
        XCTAssertLessThanOrEqual(r.x + r.width, 320)
        XCTAssertLessThanOrEqual(r.y + r.height, 160)
        let opaque = stride(from: 0, to: r.pixels.count, by: 4).filter { r.pixels[$0 + 3] == 255 }
        XCTAssertFalse(opaque.isEmpty, "fully covered pixels exist")
        for i in opaque { XCTAssertEqual(Array(r.pixels[i..<(i + 3)]), [255, 0, 0], "pure red where covered") }
    }

    func testOutlineAddsABorderInTheOutlineColor() throws {
        let plain = TextOverlaySpec(message: "O", size: 0.25, color: .white, outlineWidth: 0)
        var outlined = plain
        outlined.outlineWidth = 0.15
        outlined.outlineColor = TextColor(red: 0, green: 0, blue: 1)
        let a = try render(plain), b = try render(outlined)
        let inkA = try XCTUnwrap(a.inkBounds), inkB = try XCTUnwrap(b.inkBounds)
        XCTAssertGreaterThan((inkB.maxX - inkB.minX) + b.x, (inkA.maxX - inkA.minX) + a.x - 1)
        XCTAssertGreaterThan(inkB.maxX - inkB.minX, inkA.maxX - inkA.minX + 4, "wider by the border")
        let blue = stride(from: 0, to: b.pixels.count, by: 4).filter { b.pixels[$0 + 3] == 255 && b.pixels[$0 + 2] == 255 && b.pixels[$0] == 0 }
        XCTAssertGreaterThan(blue.count, 20, "outline-colored pixels")
        let blueInPlain = stride(from: 0, to: a.pixels.count, by: 4).filter { a.pixels[$0 + 2] > 0 && a.pixels[$0] == 0 }
        XCTAssertTrue(blueInPlain.isEmpty, "no border without an outline")
    }

    func testBoxFillsAroundTheText() throws {
        let spec = TextOverlaySpec(message: "Hi", size: 0.2, outlineWidth: 0, showsBox: true,
                                   boxColor: TextColor(red: 0, green: 1, blue: 0, alpha: 1))
        let r = try render(spec)
        let green = stride(from: 0, to: r.pixels.count, by: 4).filter { Array(r.pixels[$0..<($0 + 4)]) == [0, 255, 0, 255] }
        XCTAssertGreaterThan(green.count, 200, "the box is drawn")
        let ink = try XCTUnwrap(r.inkBounds)
        XCTAssertEqual(pixel(r, ink.minX, ink.minY), [0, 255, 0, 255], "the box's corner is the ink's corner")
        var off = spec
        off.showsBox = false
        let plain = try render(off)
        XCTAssertFalse(stride(from: 0, to: plain.pixels.count, by: 4).contains { plain.pixels[$0 + 1] == 255 && plain.pixels[$0] == 0 })
    }

    func testAlignmentPutsLatinInkOnTheExpectedSide() throws {
        let left = try inkCenter(try render(TextOverlaySpec(message: "Hi", alignment: .leading)))
        let middle = try inkCenter(try render(TextOverlaySpec(message: "Hi", alignment: .center)))
        let right = try inkCenter(try render(TextOverlaySpec(message: "Hi", alignment: .trailing)))
        XCTAssertLessThan(left, 0.25)
        XCTAssertEqual(middle, 0.5, accuracy: 0.05)
        XCTAssertGreaterThan(right, 0.75)
    }

    func testVerticalPosition() throws {
        func center(_ p: TextVerticalPosition) throws -> Double {
            let r = try render(TextOverlaySpec(message: "Hi", verticalPosition: p))
            let ink = try XCTUnwrap(r.inkBounds)
            return (Double(r.y) + Double(ink.minY + ink.maxY) / 2) / 160
        }
        XCTAssertLessThan(try center(.top), 0.25)
        XCTAssertEqual(try center(.middle), 0.5, accuracy: 0.08)
        XCTAssertGreaterThan(try center(.bottom), 0.75)
    }

    func testEveryFontAndWeightRendersAndWeightsDiffer() throws {
        for font in TextFontFamily.allCases {
            var sums: [TextFontWeight: Int] = [:]
            for weight in TextFontWeight.allCases {
                let r = try render(TextOverlaySpec(message: "Wg", font: font, weight: weight, size: 0.2, outlineWidth: 0))
                XCTAssertNotNil(r.inkBounds, "\(font) \(weight)")
                sums[weight] = stride(from: 3, to: r.pixels.count, by: 4).reduce(0) { $0 + Int(r.pixels[$1]) }
            }
            XCTAssertGreaterThan(sums[.heavy]!, sums[.regular]!, "\(font): heavy has more ink than regular")
        }
    }

    func testLongWordWrapsAndHugeTextStaysInsideThePicture() throws {
        let word = try render(TextOverlaySpec(message: String(repeating: "W", count: 60), size: 0.1))
        XCTAssertGreaterThan(word.height, 40, "a 60-letter word wraps onto several lines")
        XCTAssertLessThanOrEqual(word.x + word.width, 320)
        let huge = try render(TextOverlaySpec(message: (1...8).map { "Line \($0)" }.joined(separator: "\n"), size: 0.25))
        XCTAssertGreaterThanOrEqual(huge.y, 0)
        XCTAssertLessThanOrEqual(huge.y + huge.height, 160, "clamped to the picture")
    }

    // MARK: US3 — Unicode (S2)

    func testUnicodeFixturesRenderOnTheExpectedSide() throws {
        let fixtures: [(String, String, TextAlignmentChoice, ClosedRange<Double>)] = [
            ("combining marks", "Cafe\u{301} nai\u{308}ve", .leading, 0...0.5),
            ("emoji family and skin tone", "👨\u{200D}👩\u{200D}👧\u{200D}👦 👋🏽", .leading, 0...0.5),
            ("Arabic leading", "مرحبا بالعالم", .leading, 0.5...1),
            ("Arabic trailing", "مرحبا بالعالم", .trailing, 0...0.5),
            ("Hebrew leading", "שלום עולם", .leading, 0.5...1),
            ("CJK", "你好，世界 こんにちは 안녕하세요", .leading, 0...0.5),
            ("mixed, Latin first", "Hello 👋🏽 مرحبا", .leading, 0...0.5),
            ("mixed, Latin first, trailing", "Hello 👋🏽 مرحبا", .trailing, 0.5...1),
        ]
        for (name, message, alignment, side) in fixtures {
            let r = try render(TextOverlaySpec(message: message, size: 0.08, alignment: alignment), 640, 160)
            let ink = try XCTUnwrap(r.inkBounds, name)
            XCTAssertGreaterThan(ink.maxX - ink.minX, 20, "\(name): visible")
            let center = try inkCenter(r)
            XCTAssertTrue(side.contains(center), "\(name): ink center \(center) in \(side)")
        }
    }

    func testEmojiKeepTheirOwnColors() throws {
        let r = try render(TextOverlaySpec(message: "😀", size: 0.25, color: .white, outlineWidth: 0))
        let colored = stride(from: 0, to: r.pixels.count, by: 4).contains { i in
            let p = r.pixels
            return p[i + 3] > 200 && (abs(Int(p[i]) - Int(p[i + 2])) > 60)   // not white/gray: the emoji's yellow
        }
        XCTAssertTrue(colored, "the color emoji font is used, not the text color")
    }

    // MARK: US4 — empty

    func testBlankMessagesDrawNothing() {
        XCTAssertNil(TextRasterizer.render(TextOverlaySpec(message: ""), pictureWidth: 100, pictureHeight: 100))
        XCTAssertNil(TextRasterizer.render(TextOverlaySpec(message: "  \n "), pictureWidth: 100, pictureHeight: 100))
        XCTAssertNil(TextRasterizer.render(TextOverlaySpec(message: "x"), pictureWidth: 0, pictureHeight: 100))
    }
}
#endif
