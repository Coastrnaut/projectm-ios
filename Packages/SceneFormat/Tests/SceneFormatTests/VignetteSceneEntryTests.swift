// FX-015-T08: the `fx.vignette` entry of the FX-020 `effects` list (FX-015-R10, S5): round trip, clamping and
// reporting, a disabled vignette is default (nothing saved), and older lists read with the vignette appended last and
// untouched.
import Compositor
import SceneFormat
import XCTest

final class VignetteSceneEntryTests: XCTestCase {
    private let vignetteTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let vignetteGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func vignetteDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testVignetteEntryRoundTripsAndIsClamped() throws {
        let vignette = Vignette(isEnabled: true, intensity: 0.75, softness: 0.3, centerX: 0.25, centerY: 0.6)
        var live = SceneEffectSettings(order: OutputEffectOrder([.vignette, .trails, .grade]))
        live.vignette = vignette
        XCTAssertFalse(live.isDefault)
        let written: [SceneEffectEntry] = live.entries(over: nil)
        XCTAssertEqual(written.map(\.kind), ["fx.vignette"])
        let document = try vignetteDocument(written)
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.vignette, vignette)
        XCTAssertEqual(settings.order.effects.first, .vignette)
        let wild = SceneEffectEntry(kind: "fx.vignette", enabled: true,
                                    parameters: ["intensity": .double(4), "softness": .string("soft"), "centerX": .double(-2)])
        let read = SceneEffectSettings.read([vignetteTrails, wild])
        XCTAssertEqual(read.settings.vignette, Vignette(isEnabled: true, intensity: 1, softness: 0.5, centerX: 0, centerY: 0.5))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.intensity", "$.effects[1].parameters.softness",
                                                 "$.effects[1].parameters.centerX"])
        var disabled = SceneEffectSettings()
        disabled.vignette = Vignette(isEnabled: false, intensity: 1)
        XCTAssertTrue(disabled.isDefault, "a disabled vignette is the default, so nothing is saved")
    }

    func testVignetteOlderListsReadWithItLastAndUntouched() throws {
        let settings = SceneEffectSettings.read([vignetteGrade, vignetteTrails]).settings
        XCTAssertGreaterThan(settings.order.effects.firstIndex(of: .vignette) ?? -1, settings.order.effects.firstIndex(of: .lensDistortion) ?? 99, "appended after Lens distortion (FX-018 Scanlines follows)")
        XCTAssertNil(settings.vignette, "no entry: the current vignette stays")
        XCTAssertEqual(settings.entries(over: [vignetteGrade, vignetteTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
        let old = try vignetteDocument([vignetteGrade, vignetteTrails])
        XCTAssertEqual(try SceneDocument.decode(old.encoded()).document.encoded(), old.encoded(), "older scenes encode byte-identically")
    }
}
