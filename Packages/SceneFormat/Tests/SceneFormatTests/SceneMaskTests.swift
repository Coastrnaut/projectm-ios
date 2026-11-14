// CMP-007-T13 (US3; CMP-007-S4, R8-R11): the scene format stores a layer's shape mask and its own
// transform as the optional `composite.mask`, written only when set; known shapes reach the live
// stack, an unknown shape is kept verbatim (decode → encode and load → capture), reported and drawn
// unmasked; out-of-range values are clamped; unusable polygons drop the mask with a warning.
// CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneMaskTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let videoIndex = 3   // instance 10
    private let photoID = LayerInstanceID(rawValue: 9)

    private static func masks() throws -> [LayerMask] {
        let star: [LayerPoint] = [LayerPoint(x: 0, y: -0.5), LayerPoint(x: 0.125, y: -0.1), LayerPoint(x: 0.5, y: -0.1),
                                  LayerPoint(x: 0.2, y: 0.15), LayerPoint(x: 0.3, y: 0.5), LayerPoint(x: 0, y: 0.275),
                                  LayerPoint(x: -0.3, y: 0.5), LayerPoint(x: -0.2, y: 0.15), LayerPoint(x: -0.5, y: -0.1),
                                  LayerPoint(x: -0.125, y: -0.1)]
        return [
            try LayerMask(shape: .ellipse, transform: LayerMaskTransform(center: LayerPoint(x: 0.3, y: 0.7),
                                                                         scale: LayerPoint(x: 0.45, y: 0.45))),
            try LayerMask(shape: .rectangle(cornerRadius: 0.125),
                          transform: LayerMaskTransform(center: LayerPoint(x: 0.6, y: 0.4), scale: LayerPoint(x: 1.5, y: 0.75),
                                                        rotation: 0.3), feather: 0.03),
            try LayerMask(shape: .polygon(star),
                          transform: LayerMaskTransform(center: LayerPoint(x: 0.123456789, y: 0.55), scale: LayerPoint(x: 0.8, y: 1.1),
                                                        rotation: -2.5), feather: 0.0625, inverted: true),
        ]
    }

    private func scene(photo: SceneMask?, video: SceneMask? = nil) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.mask = photo
        document.layers[videoIndex].composite.mask = video
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    private func maskText(_ mask: SceneMask) -> String { String(decoding: SceneJSONWriter.write(SceneEncoder.mask(mask)), as: UTF8.self) }

    func testEveryShapeAndItsTransformSurviveDecodeLoadCaptureAndEncodeByteForByte() throws {
        let registry = try SceneFixtures.registry()
        for mask in try Self.masks() {
            let name = mask.shape.kindName
            let document = try scene(photo: .known(mask), video: .known(try Self.masks()[0]))
            let bytes = document.encoded()
            let decoded = try SceneDocument.decode(bytes)
            XCTAssertEqual(decoded.warnings, [], "\(name): no warnings")
            XCTAssertEqual(decoded.document.layers[photoIndex].composite.mask?.layerMask, mask, "\(name) decodes")
            XCTAssertEqual(decoded.document.encoded(), bytes, "\(name): decode → encode byte for byte")
            XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .unsupportedMaskShape }, "\(name) is drawn")
            let loaded = try document.liveState(registry: registry)
            let photo = try XCTUnwrap(loaded.state.stack.entry(photoID))
            XCTAssertEqual(photo.settings.mask, mask, "\(name) reaches the live stack")
            XCTAssertEqual(photo.settings.mask?.transform, mask.transform, "\(name): the mask transform persists")
            XCTAssertEqual(loaded.state.preservedMasks, [:])
            let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
            XCTAssertEqual(captured.layers[photoIndex].composite.mask, .known(mask), "capture writes \(name)")
            let recaptured = try SceneDocument.decode(captured.encoded())
            XCTAssertEqual(recaptured.document.layers[photoIndex].composite.mask, .known(mask))
            XCTAssertTrue(text(captured).contains("\"mask\":" + maskText(.known(mask))), "\(name): the same mask bytes after capture")
        }
        let circle = try LayerMask(shape: .ellipse)
        XCTAssertEqual(maskText(.known(circle)),
                       "{\"feather\":0.0,\"inverted\":false,\"shape\":\"ellipse\",\"transform\":{\"center\":{\"x\":0.5,\"y\":0.5},"
                           + "\"rotation\":0.0,\"scale\":{\"x\":1.0,\"y\":1.0}}}",
                       "the saved form")
    }

    func testASceneWithoutAMaskIsUnchangedAndHasNoMaskField() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"mask\""), "no mask set, no field written")
        let registry = try SceneFixtures.registry()
        let loaded = try document.liveState(registry: registry)
        XCTAssertTrue(loaded.state.stack.entries.allSatisfy { $0.settings.mask == nil })
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertFalse(text(captured).contains("\"mask\""))
        XCTAssertEqual(try SceneDocument.decode(document.encoded()).document.encoded(), document.encoded())
        XCTAssertEqual(SceneDocument.currentVersion, 1, "no format version change")
    }

    func testUnknownShapesAreKeptReportedAndDrawnUnmasked() throws {
        let registry = try SceneFixtures.registry()
        let object: [String: SceneJSON] = ["shape": .string("heart"), "lobes": .integer(2), "feather": .double(0.5),
                                           "transform": .object(["twist": .bool(true)])]
        let unknown = SceneMask.unknown(shape: "heart", object: object)
        let document = try scene(photo: unknown)
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.warnings, [], "kept, not dropped")
        XCTAssertEqual(decoded.document.layers[photoIndex].composite.mask, unknown)
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "decode → encode keeps it verbatim")

        let issues = document.validate(registry: registry).filter { $0.code == .unsupportedMaskShape }
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.path, "$.layers[\(photoIndex)].composite.mask.shape")
        XCTAssertFalse(issues.first?.isError ?? true, "a warning")
        let report = SceneRepairReport(document: document, registry: registry)
        let entry = try XCTUnwrap(report.entries.first { $0.code == "unsupportedMaskShape" })
        XCTAssertEqual(entry.group, .valuesAdjusted)
        XCTAssertEqual(entry.severity, .note)

        let loaded = try document.liveState(registry: registry)
        XCTAssertNil(loaded.state.stack.entry(photoID)?.settings.mask, "drawn unmasked")
        XCTAssertEqual(loaded.state.preservedMasks, [photoID: unknown])
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertEqual(captured.layers[photoIndex].composite.mask, unknown, "load → capture writes it back")
        XCTAssertEqual(try SceneDocument.decode(captured.encoded()).document.layers[photoIndex].composite.mask, unknown)

        // A mask set live wins over the preserved one.
        var live = loaded.state
        var settings = try XCTUnwrap(live.stack.entry(photoID)).settings
        let circle = try LayerMask(shape: .ellipse)
        settings.mask = circle
        try live.stack.setSettings(settings, of: photoID)
        let edited = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(edited.layers[photoIndex].composite.mask, .known(circle))
    }

    /// Decodes the fixture scene with the photo's mask replaced by `maskJSON`.
    private func decode(_ maskJSON: String) throws(SceneDecodeError) -> SceneDecodeResult {
        let marker = SceneMask.known(try! LayerMask(shape: .ellipse))
        let base = text(try! scene(photo: marker))
        let edited = base.replacingOccurrences(of: "\"mask\":" + maskText(marker), with: "\"mask\":" + maskJSON)
        precondition(edited != base, "the fixture text changed")
        return try SceneDocument.decode(Array(edited.utf8))
    }

    func testOutOfRangeValuesAreClampedAndUnknownKeysDropped() throws {
        let result = try decode("{\"shape\":\"rectangle\",\"cornerRadius\":0.9,\"feather\":2,\"extra\":1,"
                                + "\"transform\":{\"center\":{\"x\":12,\"y\":0.5},\"scale\":{\"x\":0,\"y\":30},\"rotation\":1,\"skew\":0}}")
        let mask = try XCTUnwrap(result.document.layers[photoIndex].composite.mask?.layerMask)
        XCTAssertEqual(mask.shape, .rectangle(cornerRadius: 0.5))
        XCTAssertEqual(mask.feather, 1)
        XCTAssertEqual(mask.transform, LayerMaskTransform(center: LayerPoint(x: 10, y: 0.5), scale: LayerPoint(x: 0.01, y: 20), rotation: 1))
        let p = "$.layers[\(photoIndex)].composite.mask"
        XCTAssertEqual(Set(result.warnings.filter { $0.code == .valueClamped }.map(\.path)),
                       [p + ".cornerRadius", p + ".feather", p + ".transform.center.x", p + ".transform.scale.x", p + ".transform.scale.y"])
        XCTAssertEqual(result.warnings.filter { $0.code == .droppedField }.count, 2, "extra and skew dropped")
        // Defaults: a bare polygon with points; a polygon point beyond the range is clamped.
        let polygon = try decode("{\"shape\":\"polygon\",\"points\":[{\"x\":-20,\"y\":0},{\"x\":0,\"y\":1},{\"x\":1,\"y\":0}]}")
        let live = try XCTUnwrap(polygon.document.layers[photoIndex].composite.mask?.layerMask)
        XCTAssertEqual(live.shape, .polygon([LayerPoint(x: -10, y: 0), LayerPoint(x: 0, y: 1), LayerPoint(x: 1, y: 0)]))
        XCTAssertEqual(live.transform, .identity)
        XCTAssertFalse(live.inverted)
        XCTAssertEqual(polygon.warnings.map(\.path), [p + ".points[0].x"])
        for bad in ["{\"feather\":0}", "{\"shape\":3}", "\"ellipse\"", "{\"shape\":\"ellipse\",\"inverted\":1}",
                    "{\"shape\":\"polygon\"}", "{\"shape\":\"polygon\",\"points\":{}}"] {
            XCTAssertThrowsError(try decode(bad), "refused: \(bad)") { error in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("malformed expected, got \(error)") }
            }
        }
    }

    func testUnusablePolygonsDropTheMaskWithAWarning() throws {
        let many = (0..<33).map { (k: Int) -> String in
            let a: Double = Double(k) * 2 * Double.pi / 33
            return "{\"x\":\(0.5 * cos(a)),\"y\":\(0.5 * sin(a))}"
        }.joined(separator: ",")
        let cases: [(String, String)] = [
            ("two points", "{\"shape\":\"polygon\",\"points\":[{\"x\":0,\"y\":0},{\"x\":1,\"y\":1}]}"),
            ("33 points", "{\"shape\":\"polygon\",\"points\":[\(many)]}"),
            ("zero area", "{\"shape\":\"polygon\",\"points\":[{\"x\":0,\"y\":0},{\"x\":0.1,\"y\":0.1},{\"x\":0.2,\"y\":0.2}]}"),
        ]
        let registry = try SceneFixtures.registry()
        for (name, json) in cases {
            let result = try decode(json)
            XCTAssertNil(result.document.layers[photoIndex].composite.mask, "\(name): mask dropped")
            let dropped = result.warnings.filter { $0.code == .droppedField }
            XCTAssertEqual(dropped.count, 1, name)
            XCTAssertEqual(dropped.first?.path, "$.layers[\(photoIndex)].composite.mask", name)
            XCTAssertTrue(dropped.first?.message.contains("mask was dropped") ?? false, name)
            let loaded = try result.document.liveState(registry: registry)
            XCTAssertNil(loaded.state.stack.entry(photoID)?.settings.mask, "\(name): unmasked")
        }
    }
}
