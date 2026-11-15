// MED-007-T10 (MED-007-R10, S3): a photo asset's optional `kenBurns` survives encode and decode exactly, a malformed
// value reads as absent, only photo assets carry one, and scenes without one re-save byte-identically. CPU only, runs
// on Linux.
import Compositor
import Foundation
@testable import SceneFormat
import XCTest

final class SceneKenBurnsTests: XCTestCase {
    private let motion = KenBurnsMotion(start: KenBurnsRect(validatingX: 16.0 / 96, y: 0.125, width: 0.5, height: 0.5)!,
                                        end: KenBurnsRect(validatingX: 0.625, y: 0.625, width: 0.25, height: 1.0 / 3)!,
                                        durationMilliseconds: 8_000, easing: .linear)

    func testKenBurnsRoundTripsExactlyOnThePhotoAsset() throws {
        var document = try SceneFixtures.allKinds()
        XCTAssertNil(document.assets["photo1"]?.photoKenBurns)
        let before = document.encoded()
        document.assets["photo1"]?.photoKenBurns = motion
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.assets["photo1"]?.photoKenBurns, motion, "every rectangle value bit for bit")
        XCTAssertFalse(decoded.warnings.contains { (w: SceneIssue) -> Bool in w.path.contains("kenBurns") }, "no warning")
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "re-saved byte-identically")
        var cleared = decoded.document
        cleared.assets["photo1"]?.photoKenBurns = nil
        XCTAssertNil(cleared.assets["photo1"]?.extra[SceneKenBurns.key])
        XCTAssertEqual(cleared.encoded(), before, "removing it restores the original bytes")
    }

    func testOnlyPhotosCarryAMovement() throws {
        var document = try SceneFixtures.allKinds()
        document.assets["clip"]?.photoKenBurns = motion
        XCTAssertNil(document.assets["clip"]?.extra[SceneKenBurns.key], "a video asset ignores it")
    }

    func testMalformedMovementsReadAsAbsent() {
        let good = SceneKenBurns.json(motion)
        guard case var .object(o) = good, case var .object(start)? = o["start"] else { return XCTFail("object") }
        var cases: [SceneJSON] = [.string("on"), .object([:])]
        var outside = start; outside["x"] = .double(0.9); var m1 = o; m1["start"] = .object(outside); cases.append(.object(m1))
        var tiny = start; tiny["width"] = .double(0.01); var m2 = o; m2["start"] = .object(tiny); cases.append(.object(m2))
        start["extra"] = .integer(1); var m3 = o; m3["start"] = .object(start); cases.append(.object(m3))
        var m4 = o; m4["easing"] = .string("bounce"); cases.append(.object(m4))
        var m5 = o; m5["durationMilliseconds"] = .integer(500); cases.append(.object(m5))
        var m6 = o; m6["durationMilliseconds"] = .double(2500.5); cases.append(.object(m6))
        o["end"] = nil; cases.append(.object(o))
        for value in cases {
            let asset = SceneAsset(.photo(storeID: "0000A000-0000-4000-8000-000000000001"), extra: [SceneKenBurns.key: value])
            XCTAssertNil(asset.photoKenBurns, "\(value)")
        }
    }
}
