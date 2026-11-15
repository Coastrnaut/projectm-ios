// MED-012-T11 (MED-012-R8, S4): the scene's optional `countdown` field — round trip, malformed values read as absent
// and kept verbatim, no warning. CPU only, runs on Linux.
import Foundation
@testable import SceneFormat
import XCTest

final class SceneCountdownTests: XCTestCase {
    func testTheCountdownRoundTrips() throws {
        var document = try SceneFixtures.allKinds()
        XCTAssertNil(document.countdownSeconds, "scenes without the field have none")
        document.countdownSeconds = 90
        let bytes = document.encoded()
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(#""countdown":{"durationSeconds":90}"#))
        let decoded = try SceneDocument.decode(bytes)
        XCTAssertEqual(decoded.document.countdownSeconds, 90)
        XCTAssertEqual(decoded.document.encoded(), bytes, "re-saved byte-identically")
        XCTAssertFalse(decoded.warnings.contains { (w: SceneIssue) -> Bool in w.path.contains("countdown") }, "no warning")
        document.countdownSeconds = nil
        XCTAssertNil(document.extra[SceneCountdown.key], "nil removes the field")
    }

    func testMalformedValuesReadAsAbsentAndAreKeptVerbatim() throws {
        let bad: [SceneJSON] = [
            .integer(90), .object([:]), .object(["durationSeconds": .integer(0)]), .object(["durationSeconds": .integer(5941)]),
            .object(["durationSeconds": .double(1.5)]), .object(["durationSeconds": .string("90")]),
            .object(["durationSeconds": .integer(90), "loop": .bool(true)]),
        ]
        for value in bad {
            var document = try SceneFixtures.allKinds()
            document.extra[SceneCountdown.key] = value
            let decoded = try SceneDocument.decode(document.encoded()).document
            XCTAssertNil(decoded.countdownSeconds, "\(value) reads as absent")
            XCTAssertEqual(decoded.extra[SceneCountdown.key], value, "kept verbatim")
        }
        XCTAssertEqual(SceneCountdown.seconds(.object(["durationSeconds": .integer(5940)])), 5940)
        XCTAssertEqual(SceneCountdown.json(seconds: 99_999), .object(["durationSeconds": .integer(5940)]), "clamped on write")
    }
}
