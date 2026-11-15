// FX-014-T09: the `fx.edgeOutline` entry of the FX-020 `effects` list (FX-014-R11, S5): round trip, clamping and
// reporting, a disabled outline is default (nothing saved), and older lists read with the outline appended and untouched.
import Compositor
import SceneFormat
import XCTest

final class EdgeOutlineSceneEntryTests: XCTestCase {
    private let outlineTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let outlineGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    func testEdgeOutlineEntryRoundTripsAndIsClamped() throws {
        let outline = EdgeOutline(isEnabled: true, threshold: 0.35, width: 2,
                                  color: EdgeOutlineColor(hex: "FF8000") ?? .white, mode: .outlineOnly)
        let live = SceneEffectSettings(order: OutputEffectOrder([.edgeOutline, .trails, .grade]), edgeOutline: outline)
        XCTAssertFalse(live.isDefault)
        let written: [SceneEffectEntry] = live.entries(over: nil)
        XCTAssertEqual(written.map(\.kind), ["fx.edgeOutline"])
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = written
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.edgeOutline, outline)
        XCTAssertEqual(settings.order.effects.first, .edgeOutline)
        let wild = SceneEffectEntry(kind: "fx.edgeOutline", enabled: true,
                                    parameters: ["threshold": .double(5), "width": .double(2.6), "red": .double(-1), "mode": .string("x")])
        let read = SceneEffectSettings.read([outlineTrails, wild])
        XCTAssertEqual(read.settings.edgeOutline,
                       EdgeOutline(isEnabled: true, threshold: 1, width: 3, color: EdgeOutlineColor(red: 0, green: 1, blue: 1)))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.threshold", "$.effects[1].parameters.red",
                                                 "$.effects[1].parameters.mode"])
        XCTAssertTrue(SceneEffectSettings(edgeOutline: EdgeOutline(isEnabled: false, threshold: 0.9)).isDefault,
                      "a disabled outline is the default, so nothing is saved")
    }

    func testEdgeOutlineOlderListsReadWithItLastAndUntouched() throws {
        let settings = SceneEffectSettings.read([outlineGrade, outlineTrails]).settings
        XCTAssertEqual(settings.order.effects.firstIndex(of: .edgeOutline), 7, "appended after Mosaic (FX-012)")
        XCTAssertNil(settings.edgeOutline, "no entry: the current outline stays")
        XCTAssertEqual(settings.entries(over: [outlineGrade, outlineTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
    }
}
