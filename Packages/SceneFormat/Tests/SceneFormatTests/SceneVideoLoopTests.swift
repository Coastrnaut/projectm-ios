// MED-003-T16 (MED-003-R8, S5): a video asset's optional `loop` survives encode and decode, a
// malformed value reads as the whole file, and a scene without one re-saves byte-identically.
// CPU only, runs on Linux.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneVideoLoopTests: XCTestCase {
    private func roundTrip(_ document: SceneDocument) throws -> SceneDecodeResult {
        try SceneDocument.decode(document.encoded())
    }

    func testLoopRoundTripsOnTheVideoAsset() throws {
        var document = try SceneFixtures.allKinds()
        XCTAssertNil(document.assets["clip"]?.videoLoop, "the fixture has no loop")
        document.assets["clip"]?.videoLoop = SceneVideoLoop(inMilliseconds: 1500, outMilliseconds: 3000)
        let text = String(decoding: document.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"loop\":{\"inMilliseconds\":1500,\"outMilliseconds\":3000}"), text)
        let decoded = try roundTrip(document)
        XCTAssertEqual(decoded.document.assets["clip"]?.videoLoop, SceneVideoLoop(inMilliseconds: 1500, outMilliseconds: 3000))
        XCTAssertFalse(decoded.warnings.contains { (w: SceneIssue) -> Bool in w.path.contains("loop") }, "no warning for the field")
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "re-saved byte-identically")
        var cleared = decoded.document
        cleared.assets["clip"]?.videoLoop = nil
        XCTAssertNil(cleared.assets["clip"]?.extra["loop"])
    }

    func testSceneWithoutALoopResavesByteIdentically() throws {
        let document = try SceneFixtures.allKinds()
        let bytes = document.encoded()
        XCTAssertEqual(try SceneDocument.decode(bytes).document.encoded(), bytes)
    }

    func testMalformedLoopsReadAsTheWholeFile() {
        let bad: [SceneJSON] = [
            .string("1-2"),
            .object(["inMilliseconds": .integer(10)]),
            .object(["inMilliseconds": .integer(-1), "outMilliseconds": .integer(10)]),
            .object(["inMilliseconds": .integer(20), "outMilliseconds": .integer(10)]),
            .object(["inMilliseconds": .double(1.5), "outMilliseconds": .integer(10)]),
            .object(["inMilliseconds": .integer(0), "outMilliseconds": .integer(10), "x": .null]),
        ]
        for value in bad {
            var asset = SceneAsset.video(storeID: "A")
            asset.extra["loop"] = value
            XCTAssertNil(asset.videoLoop, "\(value)")
        }
        var photo = SceneAsset.photo(storeID: "A")
        photo.videoLoop = SceneVideoLoop(inMilliseconds: 0, outMilliseconds: 10)
        XCTAssertNil(photo.extra["loop"], "only video assets loop")
    }
}
