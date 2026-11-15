// SHD-005-T07 (SHD-005-R3, R4; S3; contract G1): a palette's stop detail (positions, alphas, interpolation) — the
// defaults keep UIX-011's bytes, the detail round-trips, malformed detail drops the entry, edits clamp and stay in
// step with the colours. CPU only, runs on Linux.
@testable import SceneFormat
import XCTest

final class PaletteGradientStopsTests: XCTestCase {
    private let idA = "0000D005-0000-4000-8000-000000000001"
    private let idB = "0000D005-0000-4000-8000-000000000002"
    private let teal = PaletteColor(red: 0x00, green: 0x80, blue: 0x80)
    private let pink = PaletteColor(red: 0xFF, green: 0x4F, blue: 0xD8)
    private let gold = PaletteColor(red: 0xE8, green: 0xC0, blue: 0x30)

    private func library() throws -> PaletteLibrary {
        var library = PaletteLibrary()
        try library.create(id: idA, name: "Three", colors: [teal, pink, gold])
        return library
    }

    func testDefaultsKeepTheUIX011Bytes() throws {
        let library = try library()
        let palette = try XCTUnwrap(library.palette(idA))
        XCTAssertFalse(palette.hasStopDetail)
        XCTAssertEqual(palette.stopPositions, [0, 500, 1000])
        XCTAssertEqual(palette.stopAlphas, [255, 255, 255])
        let text = String(decoding: PaletteFile.encode(palette), as: UTF8.self)
        XCTAssertEqual(text, ##"{"colors":["#008080","#FF4FD8","#E8C030"],"id":"\##(idA)","name":"Three","style":"gradient"}"##)
        XCTAssertEqual(ColorPalette.evenPositions(4), [0, 333, 667, 1000])
    }

    func testDetailRoundTripsCanonically() throws {
        var library = try library()
        try library.setStopPosition(idA, at: 1, to: 300)
        try library.setStopAlpha(idA, at: 2, to: 64)
        try library.setInterpolation(idA, .step)
        let palette = try XCTUnwrap(library.palette(idA))
        XCTAssertEqual(palette.positions, [0, 300, 1000])
        XCTAssertEqual(palette.alphas, [255, 255, 64])
        XCTAssertTrue(palette.hasStopDetail)
        let bytes = PaletteFile.encode(library)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains(#""alphas":[255,255,64]"#), text)
        XCTAssertTrue(text.contains(#""interpolation":"step""#), text)
        XCTAssertTrue(text.contains(#""positions":[0,300,1000]"#), text)
        let decoded = try PaletteFile.decode(bytes)
        XCTAssertEqual(decoded.library, library)
        XCTAssertEqual(PaletteFile.encode(decoded.library), bytes)
    }

    func testMalformedDetailDropsTheEntry() throws {
        func entry(_ id: Int, _ extra: String) -> String {
            ##"{"id":"0000D005-0000-4000-8000-00000000000\##(id)","name":"P\##(id)","style":"gradient","colors":["#000000","#FFFFFF"],\##(extra)}"##
        }
        let entries: [String] = [
            entry(1, #""positions":[0,1000],"alphas":[255,128],"interpolation":"srgb""#),   // good
            entry(2, #""positions":[0]"#),                 // wrong count
            entry(3, #""positions":[600,400]"#),           // decreasing
            entry(4, #""positions":[0,1001]"#),            // out of range
            entry(5, #""alphas":[255,256]"#),              // out of range
            entry(6, #""interpolation":"cubic""#),         // unknown mode
            entry(7, #""alphas":"opaque""#),               // not an array
            entry(8, #""interpolation":"smooth""#),        // the default is never written
        ]
        let text = #"{"format":"projectm-ios.palettes","version":1,"palettes":["# + entries.joined(separator: ",") + "]}"
        let decoded = try PaletteFile.decode(Array(text.utf8))
        XCTAssertEqual(decoded.library.user.map(\.name), ["P1"])
        XCTAssertEqual(decoded.dropped, 7)
        XCTAssertEqual(decoded.library.user.first?.interpolation, .srgb)
    }

    func testPositionsClampBetweenNeighbours() throws {
        var library = try library()
        try library.setStopPosition(idA, at: 1, to: 1200)
        XCTAssertEqual(library.palette(idA)?.positions, [0, 1000, 1000], "stops at the next stop")
        try library.setStopPosition(idA, at: 2, to: 10)
        XCTAssertEqual(library.palette(idA)?.positions, [0, 1000, 1000], "the last stop cannot pass its neighbour")
        try library.setStopPosition(idA, at: 0, to: -5)
        try library.setStopAlpha(idA, at: 0, to: 999)
        XCTAssertEqual(library.palette(idA)?.positions?.first, 0)
        XCTAssertEqual(library.palette(idA)?.alphas, [255, 255, 255])
        XCTAssertThrowsError(try library.setStopPosition(idA, at: 3, to: 0))
        XCTAssertThrowsError(try library.setStopAlpha(ColorPalette.spectrumID, at: 0, to: 0)) {
            XCTAssertEqual($0 as? PaletteEditError, .builtIn)
        }
    }

    func testAddRemoveAndDuplicateKeepTheDetailInStep() throws {
        var library = try library()
        try library.setStopPosition(idA, at: 1, to: 200)
        try library.setStopAlpha(idA, at: 2, to: 100)
        try library.addColor(idA)
        XCTAssertEqual(library.palette(idA)?.positions, [0, 200, 1000, 1000])
        XCTAssertEqual(library.palette(idA)?.alphas, [255, 255, 100, 100])
        try library.removeColor(idA, at: 1)
        XCTAssertEqual(library.palette(idA)?.positions, [0, 1000, 1000])
        XCTAssertEqual(library.palette(idA)?.alphas, [255, 100, 100])
        try library.setInterpolation(idA, .srgb)
        try library.duplicate(idA, newID: idB)
        let copy = try XCTUnwrap(library.palette(idB))
        XCTAssertEqual(copy.positions, [0, 1000, 1000])
        XCTAssertEqual(copy.alphas, [255, 100, 100])
        XCTAssertEqual(copy.interpolation, .srgb)
        XCTAssertTrue(copy.isValidUserPalette)
    }
}
