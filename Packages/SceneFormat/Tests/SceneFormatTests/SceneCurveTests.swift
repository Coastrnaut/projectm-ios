// SceneCurveTests.swift — MOD-004-T10: a binding's curve is stored in the optional `curve` field
// (omitted for linear, no version change), round-trips through save and reopen, and an unreadable or
// invalid curve rejects its binding, which is kept verbatim and reported (MOD-004-R9, S4; contract K8;
// research MOD-004-D5).
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneCurveTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    static let curves: [MappingCurve] = [
        .easeIn(exponent: 2), .easeOut(exponent: 3.5), .easeInOut(exponent: 8), .logarithmic(strength: 9),
        .exponential(strength: 0.25), .piecewise([CurvePoint(x: 0.25, y: 0.5), CurvePoint(x: 0.75, y: 0.5)]),
        .piecewise([]),
    ]

    private func document(_ binding: SceneBinding) -> SceneDocument {
        SceneDocument(id: SceneFixtures.sceneID, name: "Curves", bindings: [binding])
    }

    private func binding(curve: MappingCurve = .linear, extra: [String: SceneJSON] = [:]) -> SceneBinding {
        SceneBinding(sourceID: "audio.band.0", target: IDs.bloomIntensity, mapping: LinearMapping(outputStart: 0, outputEnd: 1),
                     curve: curve, extra: extra)
    }

    private func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    // MARK: Round trip (MOD-004-S4)

    func testEveryCurveKindSurvivesSaveAndReopen() throws {
        let registry = try SceneFixtures.registry()
        for curve in Self.curves {
            let bytes: [UInt8] = document(binding(curve: curve)).encoded()
            let reopened = try SceneDocument.decode(bytes)
            XCTAssertEqual(reopened.warnings, [], "\(curve)")
            XCTAssertEqual(reopened.document.bindings.first?.curve, curve)
            let loaded = try reopened.document.liveState(registry: registry)
            XCTAssertEqual(loaded.warnings, [], "\(curve)")
            XCTAssertEqual(loaded.state.bindings.map(\.curve), [curve], "applied with the same curve")
            let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Curves")
            XCTAssertEqual(saved.encoded(), bytes, "\(curve): capture → encode is byte-identical")
            XCTAssertTrue(text(bytes).contains("\"curve\""), "\(curve): only the linear curve is omitted")
        }
    }

    func testLinearBindingsWriteNoCurveAndReadAnExplicitLinear() throws {
        let bytes: [UInt8] = document(binding()).encoded()
        XCTAssertFalse(text(bytes).contains("curve"), "a linear binding is stored exactly as before this row")
        let explicit = binding(extra: ["curve": .object(["kind": .string("linear")])])
        let reopened = try SceneDocument.decode(document(explicit).encoded())
        XCTAssertEqual(reopened.warnings, [])
        XCTAssertEqual(reopened.document.bindings.first?.curve, .linear)
        XCTAssertNil(reopened.document.bindings.first?.extra["curve"])
        XCTAssertEqual(reopened.document.encoded(), bytes, "an explicit linear curve is re-saved without the field")
    }

    func testStoredShape() throws {
        let stored = SceneEncoder.binding(binding(curve: .piecewise([CurvePoint(x: 0.25, y: 0.5)])))
        XCTAssertEqual(stored.objectValue?["curve"], .object([
            "kind": .string("piecewise"),
            "points": .array([.object(["x": .double(0.25), "y": .double(0.5)])]),
        ]))
        XCTAssertEqual(SceneEncoder.binding(binding(curve: .logarithmic(strength: 9))).objectValue?["curve"],
                       .object(["kind": .string("logarithmic"), "strength": .double(9)]))
        XCTAssertEqual(SceneEncoder.binding(binding(curve: .easeIn(exponent: 2))).objectValue?["curve"],
                       .object(["kind": .string("easeIn"), "exponent": .double(2)]))
    }

    // MARK: Unreadable curves (contract K8)

    func testUnreadableCurvesRejectTheBindingAndAreKeptVerbatim() throws {
        let registry = try SceneFixtures.registry()
        let unreadable: [SceneJSON] = [
            .object(["kind": .string("bezier"), "handles": .array([.double(0.1)])]),
            .integer(5),
            .object(["kind": .string("easeIn")]),
            .object(["kind": .string("logarithmic"), "strength": .string("strong")]),
            .object(["kind": .string("piecewise"), "points": .array([.object(["x": .double(0.5)])])]),
            .object(["exponent": .double(2)]),
        ]
        for stored in unreadable {
            let bytes: [UInt8] = document(binding(extra: ["curve": stored])).encoded()
            let reopened = try SceneDocument.decode(bytes)
            XCTAssertEqual(reopened.warnings, [], "decoding never fails or drops an unreadable curve")
            XCTAssertEqual(reopened.document.bindings.first?.extra["curve"], stored, "kept verbatim")
            let loaded = try reopened.document.liveState(registry: registry)   // the scene still opens
            XCTAssertEqual(loaded.warnings.map { (i: SceneIssue) -> String in "\(i.code.rawValue) \(i.path)" },
                           ["unsupportedCurve $.bindings[0].curve"], "\(stored)")
            XCTAssertEqual(loaded.warnings.first?.message, "Binding 0 uses a curve this version cannot read; it is kept but not applied.")
            XCTAssertEqual(loaded.warnings.first?.severity, .warning)
            XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.rejected])
            XCTAssertEqual(loaded.state.bindings, [], "not applied")
            let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Curves")
            XCTAssertEqual(saved.encoded(), bytes, "re-saving writes the unreadable curve back unchanged")
        }
    }

    func testInvalidCurveRejectsTheBinding() throws {
        let registry = try SceneFixtures.registry()
        let decreasing = MappingCurve.piecewise([CurvePoint(x: 0.3, y: 0.7), CurvePoint(x: 0.6, y: 0.4)])
        let bytes: [UInt8] = document(binding(curve: decreasing)).encoded()
        let reopened = try SceneDocument.decode(bytes)
        XCTAssertEqual(reopened.document.bindings.first?.curve, decreasing, "read as written, not repaired")
        let loaded = try reopened.document.liveState(registry: registry)
        let error = AudioFeatureBindingError.invalidCurve(IDs.bloomIntensity, reason: decreasing.validationProblem ?? "")
        XCTAssertEqual(loaded.warnings, [SceneIssue(.invalidBinding, path: "$.bindings[0]", "Binding 0: \(error.description).")])
        XCTAssertEqual(loaded.modulationReport.entries.map(\.outcome), [.rejected])
        let saved = try SceneDocument(capturing: loaded.state, id: SceneFixtures.sceneID, name: "Curves")
        XCTAssertEqual(saved.encoded(), bytes, "kept verbatim")
    }

    func testUnknownFieldsInsideAReadableCurveAreDropped() throws {
        let stored: SceneJSON = .object(["kind": .string("easeIn"), "exponent": .double(2), "tension": .double(1)])
        let reopened = try SceneDocument.decode(document(binding(extra: ["curve": stored])).encoded())
        XCTAssertEqual(reopened.document.bindings.first?.curve, .easeIn(exponent: 2))
        XCTAssertNil(reopened.document.bindings.first?.extra["curve"])
        XCTAssertEqual(reopened.warnings.map { (i: SceneIssue) -> String in "\(i.code.rawValue) \(i.path)" },
                       ["droppedField $.bindings[0].curve"])
    }

    func testUnsupportedCurveIsAMappingProblemInTheRepairReport() {
        XCTAssertEqual(SceneIssue.Code.unsupportedCurve.severity, .warning)
        XCTAssertTrue(SceneRepairReport.mappingCodes.contains(.unsupportedCurve))
        XCTAssertEqual(SceneRepairReport.classify(.unsupportedCurve).action, .dropInvalidMappings)
        XCTAssertEqual(SceneRepairReport.ifOpened(.unsupportedCurve, .problem), "It is kept in the scene but has no effect.")
    }
}
