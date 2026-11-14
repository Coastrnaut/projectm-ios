// SceneMaterialVariantTests.swift — SHD-004-T12, T15 (US2, US3; SHD-004-R6, S3; contracts/material-variants.md V4):
// a material layer's optional `materialVariant`. Switching changes only that field (the bytes are otherwise
// identical), the default writes nothing, decode → live state → capture is byte-equal, and an unlisted variant
// is kept with an `unknownMaterialVariant` warning. CPU only, runs on Linux.
import Compositor
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneMaterialVariantTests: XCTestCase {
    private func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    func testSwitchingChangesOnlyTheVariantField() throws {
        let original = try SceneFixtures.allKinds()
        let bytes: [UInt8] = original.encoded()
        let index = try XCTUnwrap(original.layers.firstIndex { (l: SceneLayer) -> Bool in l.kind == "material" })
        XCTAssertNil(original.layers[index].materialVariant)
        XCTAssertFalse(text(bytes).contains("materialVariant"), "untouched scenes keep their bytes")

        var switched = original
        switched.layers[index].materialVariant = "plasmaDetailed"
        let switchedBytes: [UInt8] = switched.encoded()
        XCTAssertNotEqual(switchedBytes, bytes)
        let field = "\"materialVariant\":\"plasmaDetailed\","
        XCTAssertEqual(text(switchedBytes).components(separatedBy: field).count, 2, "written once")
        XCTAssertEqual(text(switchedBytes).replacingOccurrences(of: field, with: ""), text(bytes),
                       "byte-equal apart from the variant field")
        XCTAssertEqual(switched.layers[index].values, original.layers[index].values)
        XCTAssertEqual(switched.layers[index].composite, original.layers[index].composite)
        XCTAssertEqual(switched.parameters, original.parameters, "parameter values are untouched")

        // Back to the default (nil) gives the original bytes.
        var back = switched
        back.layers[index].materialVariant = nil
        XCTAssertEqual(back.encoded(), bytes)
    }

    func testRoundTripThroughLiveStateAndCapture() throws {
        let registry = try SceneFixtures.registry()
        var document = try SceneFixtures.allKinds()
        let index = try XCTUnwrap(document.layers.firstIndex { (l: SceneLayer) -> Bool in l.kind == "material" })
        document.layers[index].materialVariant = "plasmaDetailed"
        let bytes: [UInt8] = document.encoded()
        let decoded = try SceneDocument.decode(bytes).document
        XCTAssertEqual(decoded.layers[index].materialVariant, "plasmaDetailed")
        XCTAssertEqual(decoded.encoded(), bytes, "decode → encode is byte-identical")
        XCTAssertFalse(decoded.validate(registry: registry).contains { (i: SceneIssue) -> Bool in i.code == .unknownMaterialVariant })
        let live = try decoded.liveState(registry: registry).state
        let instance = LayerInstanceID(rawValue: decoded.layers[index].instance)
        XCTAssertEqual(live.materialVariants, [instance: "plasmaDetailed"])
        let captured = try SceneDocument(capturing: live, id: decoded.id, name: decoded.name)
        XCTAssertEqual(captured.layers.first { (l: SceneLayer) -> Bool in l.instance == instance.rawValue }?.materialVariant, "plasmaDetailed")
        let plain = try SceneFixtures.allKinds()
        let plainCapture = try SceneDocument(capturing: try plain.liveState(registry: registry).state, id: plain.id, name: plain.name)
        XCTAssertFalse(text(plainCapture.encoded()).contains("materialVariant"), "no variant, no field")
    }

    func testUnknownVariantIsKeptWithAWarningAndBadTypeIsDropped() throws {
        let registry = try SceneFixtures.registry()
        var document = try SceneFixtures.allKinds()
        let index = try XCTUnwrap(document.layers.firstIndex { (l: SceneLayer) -> Bool in l.kind == "material" })
        document.layers[index].materialVariant = "plasmaUltra"
        let decoded = try SceneDocument.decode(document.encoded()).document
        let issues = decoded.validate(registry: registry).filter { (i: SceneIssue) -> Bool in i.code == .unknownMaterialVariant }
        XCTAssertEqual(issues.map(\.path), ["$.layers[\(index)].materialVariant"])
        XCTAssertFalse(issues.first?.isError ?? true, "a warning: the scene still opens")
        XCTAssertEqual(SceneRepairReport.classify(.unknownMaterialVariant).group, .unknownContent)
        let live = try decoded.liveState(registry: registry).state
        XCTAssertEqual(Array(live.materialVariants.values), ["plasmaUltra"], "kept for re-save")

        // A non-text value is dropped with a warning; on another kind the field stays an unknown field.
        let encoded = text(document.encoded()).replacingOccurrences(of: "\"materialVariant\":\"plasmaUltra\"", with: "\"materialVariant\":7")
        let result = try SceneDocument.decode(Array(encoded.utf8))
        XCTAssertNil(result.document.layers[index].materialVariant)
        XCTAssertTrue(result.warnings.contains { (i: SceneIssue) -> Bool in
            i.code == .droppedField && i.path == "$.layers[\(index)].materialVariant"
        })
        var camera = SceneLayer(instance: 99, content: .camera)
        camera.extra["materialVariant"] = .string("x")
        XCTAssertNil(camera.materialVariant)
    }
}
