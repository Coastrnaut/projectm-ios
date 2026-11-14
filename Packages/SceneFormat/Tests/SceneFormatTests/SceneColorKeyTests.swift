// CMP-010-T12 (US3; CMP-010-S4, R8, R9): the scene format stores a layer's colour key as the optional
// `composite.colorKey`, written only when set with every field; it reaches the live stack (beside a luma key and a
// shape), survives decode → encode and load → capture byte for byte; out-of-range numbers are clamped
// (`valueClamped`) and unknown keys dropped (`droppedField`). CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneColorKeyTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let photoID = LayerInstanceID(rawValue: 9)
    private let p = "$.layers[2].composite.colorKey"

    private func scene(key: LayerColorKey?, luma: LayerLumaKey? = nil, mask: SceneMask? = nil) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.colorKey = key
        document.layers[photoIndex].composite.lumaKey = luma
        document.layers[photoIndex].composite.mask = mask
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    private func keyText(_ k: LayerColorKey) -> String { String(decoding: SceneJSONWriter.write(SceneEncoder.colorKey(k)), as: UTF8.self) }

    func testKeysSurviveDecodeLoadCaptureAndEncodeByteForByte() throws {
        let registry = try SceneFixtures.registry()
        let circle = try LayerMask(shape: .ellipse)
        let keys: [LayerColorKey] = [.greenKey, LayerColorKey(red: 0.123, green: 0.456, blue: 0.789, tolerance: 0.333333, feather: 0)]
        for key in keys {
            for extras in [false, true] {
                let name = "\(key)" + (extras ? " × luma key × circle" : "")
                let document = try scene(key: key, luma: extras ? .blackKey : nil, mask: extras ? .known(circle) : nil)
                let bytes = document.encoded()
                let decoded = try SceneDocument.decode(bytes)
                XCTAssertEqual(decoded.warnings, [], name)
                XCTAssertEqual(decoded.document.layers[photoIndex].composite.colorKey, key, name)
                XCTAssertEqual(decoded.document.encoded(), bytes, "\(name): decode → encode byte for byte")
                let loaded = try document.liveState(registry: registry)
                let photo = try XCTUnwrap(loaded.state.stack.entry(photoID))
                XCTAssertEqual(photo.settings.colorKey, key, "\(name) reaches the live stack")
                XCTAssertEqual(photo.settings.lumaKey, extras ? .blackKey : nil, name)
                let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
                let before = SceneJSONWriter.write(SceneEncoder.composite(document.layers[photoIndex].composite))
                let after = SceneJSONWriter.write(SceneEncoder.composite(captured.layers[photoIndex].composite))
                XCTAssertEqual(after, before, "\(name): load → capture keeps the composite byte for byte")
            }
        }
        XCTAssertEqual(keyText(.greenKey), "{\"blue\":0.0,\"feather\":0.1,\"green\":1.0,\"red\":0.0,\"tolerance\":0.2}", "the saved form")
    }

    func testASceneWithoutAKeyIsUnchangedAndHasNoField() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"colorKey\""))
        let loaded = try document.liveState(registry: try SceneFixtures.registry())
        XCTAssertTrue(loaded.state.stack.entries.allSatisfy { $0.settings.colorKey == nil })
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertFalse(text(captured).contains("\"colorKey\""))
        XCTAssertEqual(try SceneDocument.decode(document.encoded()).document.encoded(), document.encoded())
        XCTAssertEqual(SceneDocument.currentVersion, 1, "no format version change")
    }

    /// Decodes the fixture scene with the photo's key replaced by `json`.
    private func decode(_ json: String) throws(SceneDecodeError) -> SceneDecodeResult {
        let base = text(try! scene(key: .greenKey))
        let edited = base.replacingOccurrences(of: "\"colorKey\":" + keyText(.greenKey), with: "\"colorKey\":" + json)
        precondition(edited != base, "the fixture text changed")
        return try SceneDocument.decode(Array(edited.utf8))
    }

    func testOutOfRangeValuesAreClampedAndUnknownKeysDropped() throws {
        let result = try decode("{\"red\":-0.5,\"green\":3,\"blue\":0.5,\"tolerance\":2,\"feather\":0.9,\"spill\":1}")
        XCTAssertEqual(result.document.layers[photoIndex].composite.colorKey,
                       LayerColorKey(red: 0, green: 1, blue: 0.5, tolerance: 1, feather: 0.5))
        XCTAssertEqual(Set(result.warnings.filter { $0.code == .valueClamped }.map(\.path)),
                       [p + ".red", p + ".green", p + ".tolerance", p + ".feather"])
        XCTAssertEqual(result.warnings.filter { $0.code == .droppedField }.map(\.path), [p], "spill")
        let bare = try decode("{}")
        XCTAssertEqual(bare.warnings, [])
        XCTAssertEqual(bare.document.layers[photoIndex].composite.colorKey, .greenKey, "missing fields read the green key's")
        let blue = try decode("{\"blue\":1,\"green\":0}")
        XCTAssertEqual(blue.document.layers[photoIndex].composite.colorKey, LayerColorKey(red: 0, green: 0, blue: 1))
        for bad in ["1", "{\"red\":\"green\"}", "{\"feather\":true}"] {
            XCTAssertThrowsError(try decode(bad), "refused: \(bad)") { error in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("malformed expected, got \(error)") }
            }
        }
    }
}
