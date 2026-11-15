// FX-018-T08: the `fx.scanlines` entry of the FX-020 `effects` list (FX-018-R10, S4): round trip, clamping and
// reporting, disabled scanlines are default (nothing saved), and older lists read with Scanlines appended after
// Vignette and untouched.
import Compositor
import SceneFormat
import XCTest

final class ScanlinesSceneEntryTests: XCTestCase {
    private let scanlinesTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let scanlinesGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func scanlinesDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testScanlinesEntryRoundTripsAndIsClamped() throws {
        let lines = Scanlines(isEnabled: true, spacing: 7, thickness: 3, intensity: 0.65, isVertical: true)
        var live = SceneEffectSettings(order: OutputEffectOrder([.scanlines, .trails, .grade]))
        live.scanlines = lines
        XCTAssertFalse(live.isDefault)
        let written: [SceneEffectEntry] = live.entries(over: nil)
        XCTAssertEqual(written.map(\.kind), ["fx.scanlines"])
        let document = try scanlinesDocument(written)
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.scanlines, lines)
        XCTAssertEqual(settings.order.effects.first, .scanlines)
        let wild = SceneEffectEntry(kind: "fx.scanlines", enabled: true,
                                    parameters: ["spacing": .double(40), "thickness": .double(2.6), "intensity": .string("dark"),
                                                 "vertical": .double(0.2)])
        let read = SceneEffectSettings.read([scanlinesTrails, wild])
        XCTAssertEqual(read.settings.scanlines, Scanlines(isEnabled: true, spacing: 16, thickness: 3, intensity: 0.5, isVertical: false))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.spacing", "$.effects[1].parameters.intensity"])
        var disabled = SceneEffectSettings()
        disabled.scanlines = Scanlines(isEnabled: false, intensity: 1)
        XCTAssertTrue(disabled.isDefault, "disabled scanlines are the default, so nothing is saved")
    }

    func testScanlinesOlderListsReadWithItAfterVignetteAndUntouched() throws {
        let settings = SceneEffectSettings.read([scanlinesGrade, scanlinesTrails]).settings
        let order: [OutputEffectKind] = settings.order.effects
        XCTAssertGreaterThan(order.firstIndex(of: .scanlines) ?? -1, order.firstIndex(of: .vignette) ?? 99, "appended after Vignette")
        XCTAssertNil(settings.scanlines, "no entry: the current scanlines stay")
        XCTAssertEqual(settings.entries(over: [scanlinesGrade, scanlinesTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
        let old = try scanlinesDocument([scanlinesGrade, scanlinesTrails])
        XCTAssertEqual(try SceneDocument.decode(old.encoded()).document.encoded(), old.encoded(), "older scenes encode byte-identically")
    }
}
