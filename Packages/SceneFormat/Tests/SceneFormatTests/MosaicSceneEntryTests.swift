// FX-012-T09: the `fx.mosaic` entry of the FX-020 `effects` list (FX-012-R10, S5): round trip, clamping and reporting,
// a disabled mosaic is default (nothing saved), and older lists read with the mosaic appended and untouched.
import Compositor
import SceneFormat
import XCTest

final class MosaicSceneEntryTests: XCTestCase {
    private let mosaicTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let mosaicGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func mosaicDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testMosaicEntryRoundTripsAndIsClamped() throws {
        let mosaic = Mosaic(isEnabled: true, blockSize: 12, shape: .hexagon)
        let order = OutputEffectOrder([.mosaic, .trails, .grade])
        let live = SceneEffectSettings(order: order, mosaic: mosaic)
        XCTAssertFalse(live.isDefault)
        let written: [SceneEffectEntry] = live.entries(over: nil)
        XCTAssertEqual(written.map(\.kind), ["fx.mosaic"])
        let document = try mosaicDocument(written)
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.mosaic, mosaic)
        XCTAssertEqual(settings.order.effects.first, .mosaic)
        let wild = SceneEffectEntry(kind: "fx.mosaic", enabled: true, parameters: ["size": .double(500), "shape": .string("hex")])
        let read = SceneEffectSettings.read([mosaicTrails, wild])
        XCTAssertEqual(read.settings.mosaic, Mosaic(isEnabled: true, blockSize: 64, shape: .square))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.size", "$.effects[1].parameters.shape"])
        let fractional = SceneEffectEntry(kind: "fx.mosaic", parameters: ["size": .double(5.6), "shape": .double(0.7)])
        XCTAssertEqual(SceneEffectSettings.read([fractional]).settings.mosaic, Mosaic(isEnabled: true, blockSize: 6, shape: .hexagon))
        XCTAssertTrue(SceneEffectSettings(mosaic: Mosaic(isEnabled: false, blockSize: 30)).isDefault,
                      "a disabled mosaic is the default, so nothing is saved")
    }

    func testMosaicOlderListsReadWithItLastAndUntouched() throws {
        let settings = SceneEffectSettings.read([mosaicGrade, mosaicTrails]).settings
        XCTAssertEqual(settings.order.effects.firstIndex(of: .mosaic), 6, "appended after Echo (FX-010)")
        XCTAssertNil(settings.mosaic, "no entry: the current mosaic stays")
        XCTAssertEqual(settings.entries(over: [mosaicGrade, mosaicTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
    }
}
