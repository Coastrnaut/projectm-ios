// SHD-008-T09 (US2; SHD-008-R6, S1, S2): a path mask is saved as `composite.mask` with `"shape": "path"` and its
// points in full; decode → encode and decode → load → capture → encode keep every point exactly. A saved path that
// crosses itself (or repeats a point, or has too few points) drops the mask with a `droppedField` warning naming
// the reason; the scene still opens and the layer is drawn unmasked. CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualGenerators
import XCTest

final class ScenePathMaskTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let photoID = LayerInstanceID(rawValue: 9)

    private static func arrowMask() throws -> LayerMask {
        let points: [VectorPoint] = [VectorPoint(x: 0.123456789012345, y: 0.1), VectorPoint(x: 0.9, y: 0.5),
                                     VectorPoint(x: 0.1, y: 0.987654321098765), VectorPoint(x: 0.5, y: 0.5)]
        return try LayerMask(shape: .path(try VectorPath(points)),
                             transform: LayerMaskTransform(center: LayerPoint(x: 0.4, y: 0.6), scale: LayerPoint(x: 0.8, y: 0.9),
                                                           rotation: 0.25), feather: 0.02, inverted: false)
    }

    private func scene(_ mask: SceneMask?) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.mask = mask
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    func testSavedPathRestoresEveryPointThroughDecodeLoadCaptureAndEncode() throws {
        let mask = try Self.arrowMask()
        let document = try scene(.known(mask))
        let bytes = document.encoded()
        XCTAssertTrue(text(document).contains("\"shape\":\"path\""))
        let decoded = try SceneDocument.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        let restored = try XCTUnwrap(decoded.document.layers[photoIndex].composite.mask?.layerMask)
        guard case let .path(path) = restored.shape, case let .path(original) = mask.shape else { return XCTFail("a path mask") }
        XCTAssertEqual(path.points, original.points, "every point exactly")
        XCTAssertEqual(decoded.document.encoded(), bytes, "decode → encode byte for byte")
        let registry = try SceneFixtures.registry()
        XCTAssertFalse(document.validate(registry: registry).contains { $0.code == .unsupportedMaskShape })
        let loaded = try document.liveState(registry: registry)
        XCTAssertEqual(try XCTUnwrap(loaded.state.stack.entry(photoID)).settings.mask, mask, "reaches the live stack")
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertEqual(captured.layers[photoIndex].composite.mask, .known(mask))
        XCTAssertEqual(try SceneDocument.decode(captured.encoded()).document.encoded(), captured.encoded())
    }

    private func decode(_ maskJSON: String) throws -> SceneDecodeResult {
        let marker = SceneMask.known(try LayerMask(shape: .ellipse))
        let markerText = String(decoding: SceneJSONWriter.write(SceneEncoder.mask(marker)), as: UTF8.self)
        let base = text(try scene(marker))
        let edited = base.replacingOccurrences(of: "\"mask\":" + markerText, with: "\"mask\":" + maskJSON)
        XCTAssertNotEqual(edited, base)
        return try SceneDocument.decode(Array(edited.utf8))
    }

    func testInvalidSavedPathsDropTheMaskWithAWarningAndTheSceneOpens() throws {
        func pts(_ xy: [(Double, Double)]) -> String {
            xy.map { (p: (Double, Double)) -> String in "{\"x\":\(p.0),\"y\":\(p.1)}" }.joined(separator: ",")
        }
        let cases: [(String, String, String)] = [
            ("bow-tie", pts([(0.1, 0.1), (0.9, 0.9), (0.9, 0.1), (0.1, 0.9)]), "crosses itself"),
            ("figure-8", pts([(0.1, 0.1), (0.9, 0.9), (0.9, 0.1), (0.5, 0.05), (0.1, 0.9)]), "crosses itself"),
            ("duplicate", pts([(0.1, 0.1), (0.1, 0.1), (0.9, 0.9), (0.1, 0.9)]), "repeats"),
            ("out of range", pts([(0.1, 0.1), (1.5, 0.5), (0.1, 0.9)]), "outside"),
            ("two points", pts([(0.1, 0.1), (0.9, 0.9)]), "2 points"),
        ]
        let registry = try SceneFixtures.registry()
        for (name, points, reason) in cases {
            let result = try decode("{\"shape\":\"path\",\"points\":[\(points)]}")
            XCTAssertNil(result.document.layers[photoIndex].composite.mask, "\(name): dropped")
            let dropped = result.warnings.filter { $0.code == .droppedField }
            XCTAssertEqual(dropped.count, 1, name)
            XCTAssertTrue(dropped.first?.message.contains(reason) ?? false, "\(name): \(dropped.first?.message ?? "")")
            XCTAssertTrue(dropped.first?.message.contains("mask was dropped") ?? false, name)
            XCTAssertNil(try result.document.liveState(registry: registry).state.stack.entry(photoID)?.settings.mask, "\(name): unmasked")
        }
    }
}
