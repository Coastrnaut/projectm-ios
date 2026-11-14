// MED-006-T16 (MED-006-R12): a photo asset's optional `slideshow` survives encode and decode, a
// malformed value reads as absent, only photo assets carry one, and scenes without one re-save
// byte-identically. CPU only, runs on Linux.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneSlideshowTests: XCTestCase {
    private let a = "0000A000-0000-4000-8000-000000000001"
    private let b = "0000A000-0000-4000-8000-000000000002"

    func testSlideshowRoundTripsOnThePhotoAsset() throws {
        var document = try SceneFixtures.allKinds()
        XCTAssertNil(document.assets["photo1"]?.photoSlideshow)
        let show = SceneSlideshow(enabled: true, storeIDs: [b, a], mode: "beats", seconds: 7, beats: 2)
        document.assets["photo1"]?.photoSlideshow = show
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.assets["photo1"]?.photoSlideshow, show)
        XCTAssertFalse(decoded.warnings.contains { (w: SceneIssue) -> Bool in w.path.contains("slideshow") }, "no warning")
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "re-saved byte-identically")
        var cleared = decoded.document
        cleared.assets["photo1"]?.photoSlideshow = nil
        XCTAssertNil(cleared.assets["photo1"]?.extra[SceneSlideshow.key])
    }

    func testOnlyPhotosCarryASlideshowAndOldScenesResaveUnchanged() throws {
        var document = try SceneFixtures.allKinds()
        let bytes = document.encoded()
        XCTAssertEqual(try SceneDocument.decode(bytes).document.encoded(), bytes)
        document.assets["clip"]?.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: [a], mode: "time", seconds: 5, beats: 4)
        XCTAssertNil(document.assets["clip"]?.extra[SceneSlideshow.key], "a video asset ignores it")
        XCTAssertNil(document.assets["clip"]?.photoSlideshow)
    }

    func testMalformedSlideshowsReadAsAbsentAndBadIdentifiersAreDropped() {
        let bad: [SceneJSON] = [
            .string("on"),
            .object(["enabled": .bool(true)]),
            .object(["enabled": .string("yes"), "storeIDs": .array([]), "mode": .string("time"), "seconds": .integer(5), "beats": .integer(4)]),
            .object(["enabled": .bool(true), "storeIDs": .array([]), "mode": .string("kicks"), "seconds": .integer(5), "beats": .integer(4)]),
            .object(["enabled": .bool(true), "storeIDs": .array([]), "mode": .string("time"), "seconds": .double(1.5), "beats": .integer(4)]),
        ]
        for value in bad {
            let asset = SceneAsset(.photo(storeID: a), extra: [SceneSlideshow.key: value])
            XCTAssertNil(asset.photoSlideshow, "\(value)")
        }
        let many: [SceneJSON] = [.string("lower-case"), .integer(3)] + (0..<30).map { (n: Int) -> SceneJSON in
            .string(String(format: "0000A000-0000-4000-8000-%012d", n))
        }
        let asset = SceneAsset(.photo(storeID: a), extra: [SceneSlideshow.key: .object([
            "enabled": .bool(false), "storeIDs": .array(many), "mode": .string("time"), "seconds": .integer(9), "beats": .integer(8)])])
        let show = asset.photoSlideshow
        XCTAssertEqual(show?.storeIDs.count, 20, "canonical identifiers only, at most 20")
        XCTAssertEqual(show?.storeIDs.first, "0000A000-0000-4000-8000-000000000000")
        XCTAssertEqual(show?.seconds, 9)
    }
}
