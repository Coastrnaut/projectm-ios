// FX-017-T09: the `fx.filmGrain` entry of the FX-020 `effects` list (FX-017-R11, S5): round trip, clamping, rounding and
// reporting, a disabled grain is default (nothing saved), and older lists read with the grain appended last and
// untouched.
import Compositor
import SceneFormat
import XCTest

final class FilmGrainSceneEntryTests: XCTestCase {
    private let grainTrails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let grainGrade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6)])

    private func grainDocument(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    func testFilmGrainEntryRoundTripsAndIsClamped() throws {
        let grain = FilmGrain(isEnabled: true, opacity: 0.65, size: 2, isColor: true, seed: 4_321, isAnimated: true)
        var live = SceneEffectSettings(order: OutputEffectOrder([.filmGrain, .trails, .grade]))
        live.filmGrain = grain
        XCTAssertFalse(live.isDefault)
        let written: [SceneEffectEntry] = live.entries(over: nil)
        XCTAssertEqual(written.map(\.kind), ["fx.filmGrain"])
        let document = try grainDocument(written)
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.filmGrain, grain)
        XCTAssertEqual(settings.order.effects.first, .filmGrain)
        let wild = SceneEffectEntry(kind: "fx.filmGrain", enabled: true,
                                    parameters: ["opacity": .double(4), "size": .double(2.6), "color": .string("yes"),
                                                 "seed": .double(-3), "animated": .double(0.9)])
        let read = SceneEffectSettings.read([grainTrails, wild])
        XCTAssertEqual(read.settings.filmGrain, FilmGrain(isEnabled: true, opacity: 1, size: 3, isColor: false, seed: 0, isAnimated: true))
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[1].parameters.opacity", "$.effects[1].parameters.color",
                                                 "$.effects[1].parameters.seed"])
        var disabled = SceneEffectSettings()
        disabled.filmGrain = FilmGrain(isEnabled: false, opacity: 1)
        XCTAssertTrue(disabled.isDefault, "a disabled grain is the default, so nothing is saved")
    }

    func testFilmGrainOlderListsReadWithItLastAndUntouched() throws {
        let settings = SceneEffectSettings.read([grainGrade, grainTrails]).settings
        XCTAssertEqual(settings.order.effects.last, .filmGrain, "appended last")
        XCTAssertNil(settings.filmGrain, "no entry: the current grain stays")
        XCTAssertEqual(settings.entries(over: [grainGrade, grainTrails]).map(\.kind), ["fx.grade", "fx.trails"], "nothing added")
        let old = try grainDocument([grainGrade, grainTrails])
        XCTAssertEqual(try SceneDocument.decode(old.encoded()).document.encoded(), old.encoded(), "older scenes encode byte-identically")
    }
}
