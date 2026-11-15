// FX-016-T09: the `fx.lensDistortion` entry of the FX-020 `effects` list (FX-016-R10, S6): round trip, clamping and
// reporting, a disabled warp is default (nothing saved), and older lists read with the warp appended after Edge outline
// and untouched.
import Compositor
import SceneFormat
import XCTest

final class LensDistortionSceneEntryTests: XCTestCase {
    private let lensTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let lensGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func lensDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testLensDistortionEntryRoundTripsAndIsClamped() throws {
        for lens in [LensDistortion(isEnabled: true, strength: -0.75, zoomToFill: false),
                     LensDistortion(isEnabled: true, strength: 1, zoomToFill: true)] {
            var live = SceneEffectSettings(order: OutputEffectOrder([.lensDistortion, .trails, .grade]))
            live.lensDistortion = lens
            XCTAssertFalse(live.isDefault)
            let written: [SceneEffectEntry] = live.entries(over: nil)
            XCTAssertEqual(written.map(\.kind), ["fx.lensDistortion"])
            let document = try lensDocument(written)
            let again = try SceneDocument.decode(document.encoded()).document
            XCTAssertEqual(again.encoded(), document.encoded())
            let settings = try XCTUnwrap(again.effectSettings)
            XCTAssertEqual(settings.lensDistortion, lens)
            XCTAssertEqual(settings.order.effects.first, .lensDistortion)
        }
        let wild = SceneEffectEntry(kind: "fx.lensDistortion", enabled: true,
                                    parameters: ["strength": .double(-4), "zoomToFill": .string("yes")])
        let read = SceneEffectSettings.read([lensTrails, wild])
        XCTAssertEqual(read.settings.lensDistortion, LensDistortion(isEnabled: true, strength: -1, zoomToFill: true))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.strength", "$.effects[1].parameters.zoomToFill"])
        let missing = SceneEffectEntry(kind: "fx.lensDistortion", enabled: true)
        XCTAssertEqual(SceneEffectSettings.read([missing]).settings.lensDistortion, LensDistortion(isEnabled: true),
                       "missing values read as the defaults (+0.3, zoom on)")
        var disabled = SceneEffectSettings()
        disabled.lensDistortion = LensDistortion(isEnabled: false, strength: 1)
        XCTAssertTrue(disabled.isDefault, "a disabled warp is the default, so nothing is saved")
    }

    func testLensDistortionOlderListsReadWithItAfterEdgeOutlineAndUntouched() throws {
        let settings = SceneEffectSettings.read([lensGrade, lensTrails]).settings
        XCTAssertEqual(settings.order.effects.firstIndex(of: .lensDistortion), 8, "appended after Edge outline (FX-014)")
        XCTAssertNil(settings.lensDistortion, "no entry: the current warp stays")
        XCTAssertEqual(settings.entries(over: [lensGrade, lensTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
        let old = try lensDocument([lensGrade, lensTrails])
        XCTAssertEqual(try SceneDocument.decode(old.encoded()).document.encoded(), old.encoded(), "older scenes encode byte-identically")
    }
}
