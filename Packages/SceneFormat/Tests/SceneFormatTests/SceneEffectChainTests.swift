// FX-020-T15, T16 (US3, US4; FX-020-S4, S5, R4 to R7, R10): the optional `effects` list in the scene document and the
// chain preset list. CPU only, runs on Linux. The renderer side of the acceptance is RenderGoldens'
// `EffectChainSceneTests` and Compositor's `EffectOrderCompositeTests`.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneEffectChainTests: XCTestCase {
    private let grade = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(1.6), "saturation": .double(0.4)])
    private let trails = SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.3)])
    private let future = SceneEffectEntry(kind: "fx.kaleidoscope", enabled: false, parameters: ["segments": .integer(6)],
                                          extra: ["blend": .string("screen")])

    private func minimal(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.effects = effects
        return document
    }

    private func decode(effectsJSON: String) throws -> SceneDecodeResult {
        let text = SceneFixtures.minimalText.dropLast() + ",\"effects\":" + effectsJSON + "}"
        return try SceneDocument.decode(Array(text.utf8))
    }

    // MARK: Format

    func testAbsentListIsByteIdenticalAndMeansStandardOrder() throws {
        let bytes = Array(SceneFixtures.minimalText.utf8)
        let document = try SceneDocument.decode(bytes).document
        XCTAssertNil(document.effects)
        XCTAssertNil(document.effectSettings)
        XCTAssertEqual(document.encoded(), bytes)
        var empty = document
        empty.effects = []
        XCTAssertEqual(empty.effectSettings?.order, .standard, "an empty list: today's order")
        XCTAssertTrue(empty.effectSettings?.isDefault ?? false)
    }

    func testListRoundTripsAndReadsValues() throws {
        let document = try minimal([grade, trails])
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), document.encoded())
        let settings = try XCTUnwrap(again.effectSettings)
        XCTAssertEqual(settings.order.effects, [.grade, .trails])
        XCTAssertEqual(settings.grade, ColorGrade(gamma: 1.6, saturation: 0.4))
        XCTAssertEqual(settings.trails, MotionFeedback(isEnabled: true, halfLifeSeconds: 0.3))
        XCTAssertFalse(settings.isDefault)
    }

    func testWrongTypesAreMalformedAndTooManyIsRefused() throws {
        for bad in ["{}", "[{}]", "[{\"kind\":3}]", "[{\"kind\":\"fx.grade\",\"enabled\":\"yes\"}]",
                    "[{\"kind\":\"fx.grade\",\"parameters\":[]}]"] {
            XCTAssertThrowsError(try decode(effectsJSON: bad), bad) { (error: Error) in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("\(bad): \(error)") }
            }
        }
        let many = "[" + Array(repeating: "{\"kind\":\"fx.x\"}", count: 17).joined(separator: ",") + "]"
        XCTAssertThrowsError(try decode(effectsJSON: many)) { (error: Error) in
            XCTAssertEqual(error as? SceneDecodeError, .tooMany(what: "effects", count: 17, limit: 16))
        }
    }

    func testValuesAreClampedAndReported() throws {
        let entry = SceneEffectEntry(kind: "fx.grade", parameters: ["gamma": .double(9), "hue": .string("red"), "future": .bool(true)])
        let read = SceneEffectSettings.read([entry])
        XCTAssertEqual(read.settings.grade, ColorGrade(gamma: 2))
        XCTAssertEqual(read.issues.map(\.code), [.valueClamped, .valueClamped])
        XCTAssertEqual(read.issues.map(\.path), ["$.effects[0].parameters.gamma", "$.effects[0].parameters.hue"])
        let written = read.settings.entries(over: [entry])
        XCTAssertEqual(written[0].parameters["future"], .bool(true), "unknown parameter names are kept")
    }

    // MARK: Unknown, repeated and fixed entries

    func testUnknownEntryIsKeptAtItsIndexAndReported() throws {
        let registry = try SceneFixtures.registry()
        let document = try minimal([grade, future, trails])
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.unknownEffectKind])
        XCTAssertFalse(issues[0].isError)
        // Load → reorder → capture keeps the unknown entry, verbatim, at index 1.
        var live = try document.liveState(registry: registry).state
        var settings = try XCTUnwrap(SceneEffectSettings.read(try XCTUnwrap(live.effects)).settings as SceneEffectSettings?)
        settings.order = settings.order.moving(from: [1], to: 0)
        live.effects = settings.entries(over: live.effects)
        let saved = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(saved.effects?.map(\.kind), ["fx.trails", "fx.kaleidoscope", "fx.grade"])
        XCTAssertEqual(saved.effects?[1], future)
        let report = SceneRepairReport(document: saved, decodeWarnings: [], registry: registry)
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "unknownEffectKind" })
    }

    func testRepeatedAndFixedKindsNeverChangeTheOrder() {
        let list = [SceneEffectEntry(kind: "fx.toneMap"), trails, SceneEffectEntry(kind: "fx.flashGuard"), grade,
                    SceneEffectEntry(kind: "fx.trails", parameters: ["halfLife": .double(0.05)])]
        let read = SceneEffectSettings.read(list)
        XCTAssertEqual(read.settings.order, .standard)
        XCTAssertEqual(read.settings.trails?.halfLifeSeconds, 0.3, "the first entry of a kind counts")
        XCTAssertEqual(read.issues.map(\.code), [.fixedEffectStage, .fixedEffectStage, .duplicateEffect])
        let rewritten = read.settings.entries(over: list)
        XCTAssertEqual(rewritten.map(\.kind), list.map(\.kind), "every entry stays where it was")
    }

    func testCaptureWithoutStoredListAppendsInLiveOrder() {
        let settings = SceneEffectSettings(order: OutputEffectOrder([.grade, .trails]), grade: .neutral, gradeEnabled: false,
                                           trails: MotionFeedback(isEnabled: true, halfLifeSeconds: 0.2))
        let entries = settings.entries(over: nil)
        XCTAssertEqual(entries.map(\.kind), ["fx.grade", "fx.trails"])
        XCTAssertEqual(entries[0].enabled, false)
        XCTAssertEqual(SceneEffectSettings.read(entries).settings, settings)
    }

    // MARK: Presets

    func testPresetsSaveReplaceApplyAndRoundTrip() throws {
        var list = try XCTUnwrap(EffectChainPresetList().saving(name: "  Soft trails ", effects: [grade, trails]))
        XCTAssertEqual(list.presets.map(\.name), ["Soft trails"])
        list = try XCTUnwrap(list.saving(name: "Hard", effects: [trails]))
        list = try XCTUnwrap(list.saving(name: "soft TRAILS", effects: [trails, grade, future]))
        XCTAssertEqual(list.presets.map(\.name), ["soft TRAILS", "Hard"], "a repeated name replaces in place")
        let decoded = try XCTUnwrap(EffectChainPresetList.decode(list.encoded()))
        XCTAssertEqual(decoded, list)
        XCTAssertEqual(decoded.preset(named: "Soft Trails")?.effects, [trails, grade, future])
        XCTAssertEqual(SceneEffectSettings.read(try XCTUnwrap(decoded.preset(named: "hard")).effects).settings.trails?.halfLifeSeconds, 0.3)
        XCTAssertEqual(decoded.removing(name: "HARD").presets.count, 1)
    }

    func testPresetLimits() throws {
        XCTAssertNil(EffectChainPresetList().saving(name: "   ", effects: []))
        XCTAssertNil(EffectChainPresetList().saving(name: String(repeating: "x", count: 61), effects: []))
        var list = EffectChainPresetList()
        for i in 0..<32 { list = try XCTUnwrap(list.saving(name: "P\(i)", effects: [])) }
        XCTAssertNil(list.saving(name: "one more", effects: []))
        XCTAssertNotNil(list.saving(name: "p0", effects: [grade]), "replacing works when full")
        XCTAssertNil(EffectChainPresetList.decode(Array("{\"version\":2,\"presets\":[]}".utf8)))
        XCTAssertNil(EffectChainPresetList.decode(Array("not json".utf8)))
    }
}
