// MED-007-T03: the Ken Burns model (contracts/ken-burns.md K1; MED-007-R2 to R5, S2). Plain Swift, runs on Linux.
import Compositor
import Foundation
import XCTest

final class KenBurnsModelTests: XCTestCase {
    private let start = KenBurnsRect(validatingX: 0.1, y: 0.2, width: 0.5, height: 0.4)!
    private let end = KenBurnsRect(validatingX: 0.3, y: 0.05, width: 0.25, height: 0.2)!

    /// MED-007-R3: elapsed 0 is the stored start, elapsed ≥ duration the stored end, bit for bit.
    func testEndsAreTheStoredRectanglesExactly() {
        for easing in KenBurnsEasing.allCases {
            let motion = KenBurnsMotion(start: start, end: end, durationMilliseconds: 7_000, easing: easing)
            let d: UInt64 = motion.durationNanoseconds
            XCTAssertEqual(d, 7_000_000_000)
            XCTAssertEqual(motion.crop(elapsedNanoseconds: 0), start)
            XCTAssertEqual(motion.crop(elapsedNanoseconds: d), end)
            XCTAssertEqual(motion.crop(elapsedNanoseconds: d + 1), end)
            XCTAssertEqual(motion.crop(elapsedNanoseconds: .max), end)
            XCTAssertEqual(motion.crop(elapsedNanoseconds: 5, durationNanoseconds: 0), end, "a zero duration shows the end")
            let mid = motion.crop(elapsedNanoseconds: d / 2)
            XCTAssertEqual(mid.x, 0.2, accuracy: 1e-12, "\(easing): halfway is the midpoint for both easings")
            XCTAssertEqual(mid.width, 0.375, accuracy: 1e-12)
        }
    }

    /// MED-007-R4, S2: every edge moves monotonically from start to end; every rectangle stays valid.
    func testEveryEdgeIsMonotonicAndEveryRectangleValid() {
        var motions: [KenBurnsMotion] = [KenBurnsMotion(start: start, end: end), KenBurnsMotion(start: end, end: start, easing: .linear)]
        for preset in KenBurnsPreset.allCases {
            if let m = preset.motion() { motions.append(m) }
        }
        for motion in motions {
            let d: UInt64 = motion.durationNanoseconds
            let steps: UInt64 = 600
            var previous: KenBurnsRect = motion.crop(elapsedNanoseconds: 0)
            for k in 1...steps {
                let r = motion.crop(elapsedNanoseconds: d * k / steps)
                XCTAssertTrue(KenBurnsRect.isValid(x: r.x, y: r.y, width: r.width, height: r.height), "inside the image")
                XCTAssertTrue(Self.between(previous.x, r.x, motion.end.x), "x monotonic")
                XCTAssertTrue(Self.between(previous.y, r.y, motion.end.y), "y monotonic")
                XCTAssertTrue(Self.between(previous.width, r.width, motion.end.width), "width monotonic")
                XCTAssertTrue(Self.between(previous.height, r.height, motion.end.height), "height monotonic")
                previous = r
            }
            XCTAssertEqual(previous, motion.end)
        }
    }

    /// `next` lies between `previous` and `target` (inclusive, 1e-12 slack): no step goes backwards.
    private static func between(_ previous: Double, _ next: Double, _ target: Double) -> Bool {
        let lo: Double = min(previous, target) - 1e-12
        let hi: Double = max(previous, target) + 1e-12
        return next >= lo && next <= hi
    }

    func testEasingsAreMonotonicAndPinned() {
        for easing in KenBurnsEasing.allCases {
            XCTAssertEqual(easing.shaped(0), 0)
            XCTAssertEqual(easing.shaped(1), 1)
            XCTAssertEqual(easing.shaped(-3), 0)
            XCTAssertEqual(easing.shaped(.nan), 0)
            var last: Double = 0
            for k in 1...100 {
                let v: Double = easing.shaped(Double(k) / 100)
                XCTAssertGreaterThanOrEqual(v, last)
                last = v
            }
        }
        XCTAssertEqual(KenBurnsEasing.easeInOut.shaped(0.25), 0.15625, accuracy: 1e-12)
    }

    /// MED-007-R2: validation refuses, clamping repairs.
    func testValidationAndClamping() {
        XCTAssertNil(KenBurnsRect(validatingX: 0.6, y: 0, width: 0.5, height: 0.5), "outside on the right")
        XCTAssertNil(KenBurnsRect(validatingX: -0.01, y: 0, width: 0.5, height: 0.5))
        XCTAssertNil(KenBurnsRect(validatingX: 0, y: 0, width: 0.01, height: 0.5), "below the minimum size")
        XCTAssertNil(KenBurnsRect(validatingX: 0, y: 0, width: 0, height: 0.5))
        XCTAssertNil(KenBurnsRect(validatingX: .nan, y: 0, width: 0.5, height: 0.5))
        XCTAssertNil(KenBurnsRect(validatingX: 0, y: 0, width: .infinity, height: 0.5))
        XCTAssertNotNil(KenBurnsRect(validatingX: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let c = KenBurnsRect.clamped(x: 0.9, y: -2, width: 3, height: 0.001)
        XCTAssertEqual(c, KenBurnsRect(validatingX: 0, y: 0, width: 1, height: KenBurnsRect.minimumSize))
        let n = KenBurnsRect.clamped(x: .nan, y: 0.2, width: .nan, height: 0.5)
        XCTAssertEqual(n, KenBurnsRect.full.mixedHeight(0.5, y: 0.2))
        XCTAssertEqual(KenBurnsMotion(start: start, end: end, durationMilliseconds: 10).durationMilliseconds, 2_000)
        XCTAssertEqual(KenBurnsMotion(start: start, end: end, durationMilliseconds: 999_999).durationMilliseconds, 60_000)
    }

    func testZoomAndPositionMapToImageShapedRectangles() {
        let r = KenBurnsRect.zoom(2, positionX: 1, positionY: 0)
        XCTAssertEqual(r, KenBurnsRect(validatingX: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(r.zoom, 2, accuracy: 1e-12)
        XCTAssertEqual(r.position.x, 1, accuracy: 1e-12)
        XCTAssertEqual(KenBurnsRect.zoom(1, positionX: 0.3, positionY: 0.9), .full)
        XCTAssertEqual(KenBurnsRect.zoom(400, positionX: 0.5, positionY: 0.5).width, KenBurnsRect.minimumSize, accuracy: 1e-12)
        XCTAssertEqual(KenBurnsRect.full.position.x, 0.5)
    }

    func testPresetsRoundTripThroughMatching() {
        for preset in KenBurnsPreset.allCases {
            guard let motion = preset.motion(durationMilliseconds: 4_000, easing: .linear) else {
                XCTAssertEqual(preset, .custom)
                continue
            }
            XCTAssertEqual(KenBurnsPreset.matching(motion), preset)
        }
        XCTAssertEqual(KenBurnsPreset.matching(KenBurnsMotion(start: start, end: end)), .custom)
    }

    /// MED-007-R5: the first frame stays at 0, later frames add the clock's durations, saturating; restart re-arms.
    func testPlayheadCountsFrameDurationsAndSaturates() {
        var p = KenBurnsPlayhead()
        let limit: UInt64 = 250_000_000
        XCTAssertEqual(p.advance(frameDuration: 0.1, limit: limit), 0, "the first frame shows the start")
        XCTAssertEqual(p.advance(frameDuration: 0.1, limit: limit), 100_000_000)
        XCTAssertEqual(p.advance(frameDuration: .nan, limit: limit), 100_000_000)
        XCTAssertEqual(p.advance(frameDuration: -1, limit: limit), 100_000_000)
        XCTAssertFalse(p.isFinished(limit: limit))
        XCTAssertEqual(p.advance(frameDuration: 0.1, limit: limit), 200_000_000)
        XCTAssertEqual(p.advance(frameDuration: 0.1, limit: limit), limit)
        XCTAssertTrue(p.isFinished(limit: limit))
        p.restart()
        XCTAssertFalse(p.started)
        XCTAssertEqual(p.advance(frameDuration: 0.05, limit: limit), 0)
    }

    func testJSONRoundTripAndMalformedInput() throws {
        let motion = KenBurnsMotion(start: start, end: end, durationMilliseconds: 8_000, easing: .linear)
        let data = try JSONEncoder().encode(motion)
        XCTAssertEqual(try JSONDecoder().decode(KenBurnsMotion.self, from: data), motion)
        let bad: [String] = [
            #"{"start":{"x":0.9,"y":0,"width":0.5,"height":0.5},"end":{"x":0,"y":0,"width":1,"height":1},"durationMilliseconds":5000,"easing":"linear"}"#,
            #"{"start":{"x":0,"y":0,"width":1,"height":1},"end":{"x":0,"y":0,"width":1,"height":1},"durationMilliseconds":5000,"easing":"bounce"}"#,
            #"{"start":{"x":0,"y":0,"width":1,"height":1},"durationMilliseconds":5000,"easing":"linear"}"#,
            #"[1,2]"#,
        ]
        for text in bad {
            XCTAssertThrowsError(try JSONDecoder().decode(KenBurnsMotion.self, from: Data(text.utf8)), text)
        }
    }
}

private extension KenBurnsRect {
    func mixedHeight(_ h: Double, y: Double) -> KenBurnsRect? { KenBurnsRect(validatingX: 0, y: y, width: 1, height: h) }
}
