// CMP-009-T12 (US3; CMP-009-S4, R8, R9): the scene format stores a layer's luma key as the optional
// `composite.lumaKey`, written only when set with every field; it reaches the live stack (beside a shape and a
// gradient), survives decode → encode and load → capture byte for byte; out-of-range numbers are clamped, a reversed
// range swapped (`valueClamped`) and unknown keys dropped (`droppedField`). CPU only, runs on Linux.
import Compositor
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneLumaKeyTests: XCTestCase {
    private let photoIndex = 2   // SceneFixtures.allKinds(): instance 9
    private let photoID = LayerInstanceID(rawValue: 9)
    private let p = "$.layers[2].composite.lumaKey"

    private func scene(key: LayerLumaKey?, mask: SceneMask? = nil, gradient: SceneGradientMask? = nil) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.layers[photoIndex].composite.lumaKey = key
        document.layers[photoIndex].composite.mask = mask
        document.layers[photoIndex].composite.gradientMask = gradient
        return document
    }

    private func text(_ document: SceneDocument) -> String { String(decoding: document.encoded(), as: UTF8.self) }

    private func keyText(_ k: LayerLumaKey) -> String { String(decoding: SceneJSONWriter.write(SceneEncoder.lumaKey(k)), as: UTF8.self) }

    func testKeysSurviveDecodeLoadCaptureAndEncodeByteForByte() throws {
        let registry = try SceneFixtures.registry()
        let circle = try LayerMask(shape: .ellipse)
        let keys: [LayerLumaKey] = [.blackKey, LayerLumaKey(low: 0.123456789, high: 0.9, softness: 0.31, inverted: true)]
        for key in keys {
            for extras in [false, true] {
                let name = "\(key)" + (extras ? " × circle × linear" : "")
                let document = try scene(key: key, mask: extras ? .known(circle) : nil, gradient: extras ? .known(.linearDefault) : nil)
                let bytes = document.encoded()
                let decoded = try SceneDocument.decode(bytes)
                XCTAssertEqual(decoded.warnings, [], name)
                XCTAssertEqual(decoded.document.layers[photoIndex].composite.lumaKey, key, name)
                XCTAssertEqual(decoded.document.encoded(), bytes, "\(name): decode → encode byte for byte")
                let loaded = try document.liveState(registry: registry)
                let photo = try XCTUnwrap(loaded.state.stack.entry(photoID))
                XCTAssertEqual(photo.settings.lumaKey, key, "\(name) reaches the live stack")
                XCTAssertEqual(photo.settings.mask, extras ? circle : nil, name)
                let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
                let before = SceneJSONWriter.write(SceneEncoder.composite(document.layers[photoIndex].composite))
                let after = SceneJSONWriter.write(SceneEncoder.composite(captured.layers[photoIndex].composite))
                XCTAssertEqual(after, before, "\(name): load → capture keeps the composite byte for byte")
            }
        }
        XCTAssertEqual(keyText(.blackKey), "{\"high\":0.1,\"invert\":false,\"low\":0.0,\"softness\":0.05}", "the saved form")
    }

    func testASceneWithoutAKeyIsUnchangedAndHasNoField() throws {
        let document = try SceneFixtures.allKinds()
        XCTAssertFalse(text(document).contains("\"lumaKey\""))
        let loaded = try document.liveState(registry: try SceneFixtures.registry())
        XCTAssertTrue(loaded.state.stack.entries.allSatisfy { $0.settings.lumaKey == nil })
        let captured = try SceneDocument(capturing: loaded.state, id: document.id, name: document.name)
        XCTAssertFalse(text(captured).contains("\"lumaKey\""))
        XCTAssertEqual(try SceneDocument.decode(document.encoded()).document.encoded(), document.encoded())
        XCTAssertEqual(SceneDocument.currentVersion, 1, "no format version change")
    }

    /// Decodes the fixture scene with the photo's key replaced by `json`.
    private func decode(_ json: String) throws(SceneDecodeError) -> SceneDecodeResult {
        let base = text(try! scene(key: .blackKey))
        let edited = base.replacingOccurrences(of: "\"lumaKey\":" + keyText(.blackKey), with: "\"lumaKey\":" + json)
        precondition(edited != base, "the fixture text changed")
        return try SceneDocument.decode(Array(edited.utf8))
    }

    func testOutOfRangeValuesAreClampedAReversedRangeSwappedAndUnknownKeysDropped() throws {
        let result = try decode("{\"low\":-0.5,\"high\":3,\"softness\":0.9,\"invert\":true,\"chroma\":1}")
        XCTAssertEqual(result.document.layers[photoIndex].composite.lumaKey, LayerLumaKey(low: 0, high: 1, softness: 0.5, inverted: true))
        XCTAssertEqual(Set(result.warnings.filter { $0.code == .valueClamped }.map(\.path)), [p + ".low", p + ".high", p + ".softness"])
        XCTAssertEqual(result.warnings.filter { $0.code == .droppedField }.map(\.path), [p], "chroma")
        let reversed = try decode("{\"low\":0.6,\"high\":0.2,\"softness\":0,\"invert\":false}")
        XCTAssertEqual(reversed.document.layers[photoIndex].composite.lumaKey, LayerLumaKey(low: 0.2, high: 0.6))
        XCTAssertEqual(reversed.warnings.map(\.code), [.valueClamped])
        XCTAssertEqual(reversed.warnings.map(\.path), [p])
        let bare = try decode("{}")
        XCTAssertEqual(bare.warnings, [])
        XCTAssertEqual(bare.document.layers[photoIndex].composite.lumaKey, .blackKey, "missing fields read the black key's")
        for bad in ["1", "{\"low\":\"dark\"}", "{\"invert\":1}"] {
            XCTAssertThrowsError(try decode(bad), "refused: \(bad)") { error in
                guard case .malformed = error as? SceneDecodeError else { return XCTFail("malformed expected, got \(error)") }
            }
        }
    }
}
