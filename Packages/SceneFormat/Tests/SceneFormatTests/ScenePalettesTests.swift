// UIX-011-T02 (UIX-011-R1, R2, R4, R5, R9; contract P1 to P3): the palette model, file codec, links and resolver,
// colour names and contrast. CPU only, runs on Linux.
import Foundation
@testable import SceneFormat
import XCTest

final class ScenePalettesTests: XCTestCase {
    private let idA = "0000C011-0000-4000-8000-000000000001"
    private let idB = "0000C011-0000-4000-8000-000000000002"
    private let teal = PaletteColor(red: 0x00, green: 0x80, blue: 0x80)
    private let pink = PaletteColor(red: 0xFF, green: 0x4F, blue: 0xD8)

    private func library() throws -> PaletteLibrary {
        var library = PaletteLibrary()
        try library.create(id: idA, name: "  Neon ", colors: [teal, pink])
        try library.create(id: idB, name: "Bands", style: .swatches, colors: [pink, teal, pink])
        return library
    }

    func testHexRoundTripsAndRejectsBadText() {
        XCTAssertEqual(PaletteColor(hex: "#00808f")?.hex, "#00808F")
        XCTAssertNil(PaletteColor(hex: "008080"))
        XCTAssertNil(PaletteColor(hex: "#0080GG"))
        XCTAssertEqual(PaletteColor(fractionRed: 1.2, green: 0.5, blue: -1), PaletteColor(red: 255, green: 128, blue: 0))
    }

    func testTheFileRoundTripsCanonically() throws {
        let library = try library()
        XCTAssertEqual(library.user.map(\.name), ["Neon", "Bands"], "names are trimmed")
        let bytes = PaletteFile.encode(library)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix(##"{"format":"projectm-ios.palettes","palettes":[{"colors":["#008080","#FF4FD8"],"id":"##), text)
        XCTAssertFalse(text.contains("builtin."), "built-ins are never written")
        let decoded = try PaletteFile.decode(bytes)
        XCTAssertEqual(decoded.library, library)
        XCTAssertEqual(decoded.dropped, 0)
        XCTAssertEqual(PaletteFile.encode(decoded.library), bytes, "byte-identical")
    }

    func testDamagedEntriesAreDroppedAndNewerFilesRefused() throws {
        let text = """
        {"format":"projectm-ios.palettes","version":1,"palettes":[
          {"id":"\(idA)","name":"Good","style":"gradient","colors":["#000000","#FFFFFF"]},
          {"id":"\(idA)","name":"Duplicate","style":"gradient","colors":["#000000","#FFFFFF"]},
          {"id":"\(idB)","name":"One colour","style":"gradient","colors":["#000000"]},
          {"id":"not-a-uuid","name":"Bad ID","style":"gradient","colors":["#000000","#FFFFFF"]},
          {"id":"0000C011-0000-4000-8000-000000000003","name":"","style":"gradient","colors":["#000000","#FFFFFF"]},
          {"id":"0000C011-0000-4000-8000-000000000004","name":"Style","style":"plaid","colors":["#000000","#FFFFFF"]},
          {"id":"0000C011-0000-4000-8000-000000000005","name":"Hex","style":"gradient","colors":["#000000","white"]}
        ]}
        """
        let decoded = try PaletteFile.decode(Array(text.utf8))
        XCTAssertEqual(decoded.library.user.map(\.name), ["Good"])
        XCTAssertEqual(decoded.dropped, 6)
        XCTAssertThrowsError(try PaletteFile.decode(Array(#"{"format":"projectm-ios.palettes","version":2,"palettes":[]}"#.utf8))) {
            XCTAssertEqual($0 as? PaletteFileError, .newerVersion(2))
        }
        XCTAssertThrowsError(try PaletteFile.decode(Array(#"{"format":"other","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? PaletteFileError, .notAPaletteFile)
        }
        XCTAssertThrowsError(try PaletteFile.decode(Array("not json".utf8)))
    }

    func testLimitsAndBuiltInsAreEnforced() throws {
        var library = try library()
        XCTAssertThrowsError(try library.setColor(ColorPalette.spectrumID, at: 0, to: teal)) { XCTAssertEqual($0 as? PaletteEditError, .builtIn) }
        XCTAssertThrowsError(try library.delete(ColorPalette.iceID)) { XCTAssertEqual($0 as? PaletteEditError, .builtIn) }
        XCTAssertThrowsError(try library.removeColor(idA, at: 0)) { XCTAssertEqual($0 as? PaletteEditError, .colorLimit) }
        for _ in 0..<6 { try library.addColor(idA) }
        XCTAssertEqual(library.palette(idA)?.colors.count, 8)
        XCTAssertThrowsError(try library.addColor(idA)) { XCTAssertEqual($0 as? PaletteEditError, .colorLimit) }
        XCTAssertThrowsError(try library.rename(idA, to: String(repeating: "x", count: 41))) { XCTAssertEqual($0 as? PaletteEditError, .invalidName) }
        try library.duplicate(ColorPalette.iceID, newID: "0000C011-0000-4000-8000-0000000000FF")
        XCTAssertEqual(library.user.last?.name, "Ice copy")
        XCTAssertEqual(library.user.last?.colors, ColorPalette.builtIns[1].colors)
        var full = PaletteLibrary()
        for n in 0..<PaletteLibrary.maximumUserPalettes {
            try full.create(id: String(format: "0000C011-0000-4000-8000-%012X", n), name: "P\(n)", colors: [teal, pink])
        }
        XCTAssertThrowsError(try full.create(id: idA, name: "One more", colors: [teal, pink])) {
            XCTAssertEqual($0 as? PaletteEditError, .tooManyPalettes(limit: 64))
        }
    }

    /// Links live in `extra` (no version change) and survive a decode; the resolver takes layer → scene → Spectrum.
    func testLinksRoundTripAndResolve() throws {
        var library = try library()
        var document = try SceneFixtures.allKinds()
        XCTAssertGreaterThanOrEqual(document.layers.count, 3)
        document.paletteID = idA
        document.layers[0].paletteID = idB
        let decoded = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(decoded.paletteID, idA)
        XCTAssertEqual(decoded.layers[0].paletteID, idB)
        XCTAssertNil(decoded.layers[1].paletteID)
        XCTAssertTrue(String(decoding: document.encoded(), as: UTF8.self).contains(#""version":1"#))
        XCTAssertEqual(library.resolve(layer: 0, in: decoded).palette.id, idB, "the layer's own link")
        XCTAssertEqual(library.resolve(layer: 1, in: decoded).palette.id, idA, "the scene's link")
        XCTAssertEqual(library.resolve(nil).palette.id, ColorPalette.defaultID)
        try library.delete(idB)
        let missing = library.resolve(layer: 0, in: decoded)
        XCTAssertEqual(missing.palette.id, ColorPalette.defaultID)
        XCTAssertTrue(missing.isMissing)
        XCTAssertEqual(missing.requestedID, idB, "the link is kept")
        XCTAssertNil(try SceneFixtures.allKinds().paletteID, "scenes without a link have none")
    }

    func testNamesAndContrast() {
        XCTAssertEqual(teal.name, "teal")
        XCTAssertEqual(PaletteColor(red: 0x10, green: 0x20, blue: 0x80).name, "dark blue")
        XCTAssertEqual(PaletteColor(red: 0xD0, green: 0xD0, blue: 0xD0).name, "light grey")
        XCTAssertEqual(PaletteColor(red: 0xFF, green: 0xA0, blue: 0xD0).name, "pink")
        XCTAssertEqual(teal.spokenDescription(index: 1, count: 4), "Colour 2 of 4, teal, #008080")
        XCTAssertEqual(PaletteColor(red: 255, green: 255, blue: 255).contrastOnBlack, 21, accuracy: 0.01)
        XCTAssertTrue(PaletteColor(red: 0x30, green: 0x30, blue: 0x30).hasLowContrastOnBlack)
        XCTAssertFalse(PaletteColor(red: 0x4D, green: 0x5C, blue: 0x7B).hasLowContrastOnBlack, "ACC-003's first stop has 3:1")
    }
}
