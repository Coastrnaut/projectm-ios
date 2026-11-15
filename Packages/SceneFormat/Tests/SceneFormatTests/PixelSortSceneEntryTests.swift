// FX-011-T08: the `fx.pixelSort` entry of the FX-020 `effects` list (FX-011-R11, S6): round trip, clamping, span
// snapping and reporting, a disabled sort is default (nothing saved), and older lists read with the sort appended and
// untouched.
import Compositor
import SceneFormat
import XCTest

final class PixelSortSceneEntryTests: XCTestCase {
    private let sortTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let sortGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func sortDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testPixelSortEntryRoundTripsAndIsClamped() throws {
        for sort in [PixelSort(isEnabled: true, threshold: 0.25, span: 8, direction: .vertical),
                     PixelSort(isEnabled: true, threshold: 1, span: 64, direction: .horizontal)] {
            var live = SceneEffectSettings(order: OutputEffectOrder([.pixelSort, .trails, .grade]))
            live.pixelSort = sort
            XCTAssertFalse(live.isDefault)
            let written: [SceneEffectEntry] = live.entries(over: nil)
            XCTAssertEqual(written.map(\.kind), ["fx.pixelSort"])
            let document = try sortDocument(written)
            let again = try SceneDocument.decode(document.encoded()).document
            XCTAssertEqual(again.encoded(), document.encoded())
            let settings = try XCTUnwrap(again.effectSettings)
            XCTAssertEqual(settings.pixelSort, sort)
            XCTAssertEqual(settings.order.effects.first, .pixelSort)
        }
        let wild = SceneEffectEntry(kind: "fx.pixelSort", enabled: true,
                                    parameters: ["threshold": .double(-4), "span": .double(500), "vertical": .string("yes")])
        let read = SceneEffectSettings.read([sortTrails, wild])
        XCTAssertEqual(read.settings.pixelSort, PixelSort(isEnabled: true, threshold: 0, span: 64, direction: .horizontal))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.threshold", "$.effects[1].parameters.span",
                                                 "$.effects[1].parameters.vertical"])
        let odd = SceneEffectEntry(kind: "fx.pixelSort", enabled: true, parameters: ["span": .double(24), "vertical": .double(1)])
        XCTAssertEqual(SceneEffectSettings.read([odd]).settings.pixelSort,
                       PixelSort(isEnabled: true, threshold: 0.5, span: 16, direction: .vertical), "24 rounds down to 16")
        let missing = SceneEffectEntry(kind: "fx.pixelSort", enabled: true)
        XCTAssertEqual(SceneEffectSettings.read([missing]).settings.pixelSort, PixelSort(isEnabled: true),
                       "missing values read as the defaults (0.5, span 32, horizontal)")
        var disabled = SceneEffectSettings()
        disabled.pixelSort = PixelSort(isEnabled: false, threshold: 0.1)
        XCTAssertTrue(disabled.isDefault, "a disabled sort is the default, so nothing is saved")
    }

    func testPixelSortOlderListsReadWithItInTheStandardPlaceAndUntouched() throws {
        let settings = SceneEffectSettings.read([sortGrade, sortTrails]).settings
        XCTAssertEqual(settings.order.effects.firstIndex(of: .pixelSort), 9, "after Lens distortion, before Vignette")
        XCTAssertNil(settings.pixelSort, "no entry: the current sort stays")
        XCTAssertEqual(settings.entries(over: [sortGrade, sortTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
        let old = try sortDocument([sortGrade, sortTrails])
        XCTAssertEqual(try SceneDocument.decode(old.encoded()).document.encoded(), old.encoded(), "older scenes encode byte-identically")
    }
}
