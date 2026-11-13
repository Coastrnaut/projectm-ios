// SceneForwardCompatibilityTests.swift — unknown kinds, asset types and fields survive decode and
// encode byte for byte (SCN-001-T18; SCN-001-S4; SCN-001-R10; research SCN-001-D3).
import Foundation
@testable import SceneFormat
import XCTest

final class SceneForwardCompatibilityTests: XCTestCase {
    /// A document written by a hypothetical later version 1 app, in canonical form.
    private let future = "{\"assets\":{\"cloud\":{\"density\":0.25,\"type\":\"volume\",\"voxels\":[1,2,3]},"
        + "\"p\":{\"capturedOn\":\"iPad17,3\",\"storeID\":\"0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9\",\"type\":\"photo\"}},"
        + "\"bindings\":[{\"curve\":{\"kind\":\"easeIn\",\"power\":2.0},\"envelope\":{\"attack\":0.0,\"release\":0.0},"
        + "\"input\":{\"maximum\":1.0,\"minimum\":0.0},\"mix\":\"replace\",\"output\":{\"end\":0.5,\"start\":0.0},"
        + "\"source\":\"audio.bandMean\",\"target\":\"visual.circularSpectrum.gap\"}],"
        + "\"cues\":[{\"at\":1.5,\"name\":\"Drop\"}],\"format\":\"projectm-ios.scene\",\"id\":\"6F9619FF-8B86-D011-B42D-00C04FC964FF\","
        + "\"layers\":[{\"composite\":{\"blend\":\"normal\",\"opacity\":1.0,\"transform\":{\"anchor\":{\"x\":0.5,\"y\":0.5},"
        + "\"rotation\":0.0,\"scale\":{\"x\":1.0,\"y\":1.0},\"translation\":{\"x\":0.0,\"y\":0.0},\"version\":1}},"
        + "\"content\":{\"emitters\":[{\"rate\":1e+21,\"shape\":\"ring\"}],\"seed\":42},\"instance\":3,\"kind\":\"particles\","
        + "\"locked\":true,\"values\":{}},"
        + "{\"composite\":{\"blend\":\"softLight\",\"opacity\":1.0,\"transform\":{\"anchor\":{\"x\":0.5,\"y\":0.5},"
        + "\"rotation\":0.0,\"scale\":{\"x\":1.0,\"y\":1.0},\"translation\":{\"x\":0.0,\"y\":0.0},\"version\":1}},"
        + "\"content\":{\"asset\":\"p\"},\"instance\":4,\"kind\":\"photo\",\"mask\":{\"invert\":false},\"values\":{}}],"
        + "\"name\":\"From the future\",\"parameters\":{},\"version\":1}"

    func testUnknownContentRoundTripsByteForByte() throws {
        let decoded = try SceneDocument.decode(future.bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.document.encoded().text, future)
        let d = decoded.document
        XCTAssertEqual(d.layers[0].content, .unknown(kind: "particles"))
        XCTAssertEqual(d.layers[0].extra.keys.sorted(), ["content", "locked"])
        XCTAssertEqual(d.layers[1].extra.keys.sorted(), ["mask"])
        XCTAssertEqual(d.layers[1].composite.blendMode, "softLight")
        XCTAssertEqual(d.bindings[0].extra.keys.sorted(), ["curve"])
        XCTAssertEqual(d.assets["cloud"]?.kind, .unknown(type: "volume"))
        XCTAssertEqual(d.assets["p"]?.extra.keys.sorted(), ["capturedOn"])
        XCTAssertEqual(d.extra.keys.sorted(), ["cues"])

        // It still opens: the unknown kind and blend mode are warnings, the unknown layer is not shown.
        let loaded = try d.liveState(registry: try SceneFixtures.registry(), assets: FakeAvailability())
        XCTAssertEqual(loaded.warnings.map(\.code), [.unknownLayerKind, .unsupportedBlendMode, .unknownAssetType])
        XCTAssertEqual(loaded.state.stack.ids.map(\.rawValue), [4])
    }

    func testUnknownFieldsInClosedObjectsAreDroppedWithAWarning() throws {
        let edited = future.replacingOccurrences(of: "\"rotation\":0.0,\"scale\"", with: "\"rotation\":0.0,\"skew\":0.2,\"scale\"")
        let decoded = try SceneDocument.decode(edited.bytes)
        XCTAssertEqual(decoded.warnings.map(\.message), [
            "$.layers[0].composite.transform has the unknown field \"skew\"; it was dropped.",
            "$.layers[1].composite.transform has the unknown field \"skew\"; it was dropped.",
        ])
        XCTAssertEqual(decoded.document.encoded().text, future)
    }
}
