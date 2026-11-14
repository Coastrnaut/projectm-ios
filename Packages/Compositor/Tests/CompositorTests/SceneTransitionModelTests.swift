// CMP-014-T03: the transition model (spec, easing, clock, weights). Plain Swift: runs on the Mac host and
// in the Linux shape (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`). Times are
// injected; nothing reads a clock.
import Compositor
import Foundation
import XCTest

final class SceneTransitionModelTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000
    private static let step: UInt64 = 25_000_000   // 40 frames per second

    // MARK: Clock (CMP-014-R1, S4)

    func testClockFollowsInjectedFrameTimesAndEndsExactly() {
        var clock = SceneTransitionClock(durationNanoseconds: 100_000_000, easing: .linear)
        let start = 7 * Self.second
        var seen: [Double] = []
        for k in 0..<7 {
            seen.append(clock.advance(presentationTimeNanoseconds: start + UInt64(k) * Self.step))
        }
        XCTAssertEqual(seen, [0, 0.25, 0.5, 0.75, 1, 1, 1], "the first frame adds nothing; exactly 1 at the duration")
        XCTAssertTrue(clock.isFinished)
        XCTAssertEqual(clock.easedProgress, 1)
    }

    func testClockIsExactlyOneOnTheFirstFrameAfterAnUnevenDuration() {
        var clock = SceneTransitionClock(durationNanoseconds: 100_000_000)
        let frame: UInt64 = 16_666_667
        var k: UInt64 = 0
        var progress = clock.advance(presentationTimeNanoseconds: 0)
        while progress < 1 {
            k += 1
            progress = clock.advance(presentationTimeNanoseconds: k * frame)
        }
        XCTAssertEqual(k, 6, "6 × 16.666667 ms is the first frame at or after 100 ms")
        XCTAssertEqual(progress, 1)
    }

    func testPauseHoldsProgressAcrossAnyGap() {
        var clock = SceneTransitionClock(durationNanoseconds: 100_000_000, easing: .linear)
        clock.advance(presentationTimeNanoseconds: Self.second)
        clock.advance(presentationTimeNanoseconds: Self.second + Self.step)
        XCTAssertEqual(clock.progress, 0.25)
        clock.pause()
        XCTAssertEqual(clock.advance(presentationTimeNanoseconds: 500 * Self.second), 0.25, "the first frame after a pause adds nothing")
        XCTAssertEqual(clock.advance(presentationTimeNanoseconds: 500 * Self.second + Self.step), 0.5)
    }

    func testStallsAreClampedAndBackwardTimesIgnored() {
        var clock = SceneTransitionClock(durationNanoseconds: 1_000_000_000, easing: .linear)
        clock.advance(presentationTimeNanoseconds: Self.second)
        clock.advance(presentationTimeNanoseconds: 3 * Self.second)   // a 2 s stall counts as 0.1 s
        XCTAssertEqual(clock.elapsedNanoseconds, 100_000_000)
        clock.advance(presentationTimeNanoseconds: 2 * Self.second)   // earlier: nothing
        clock.advance(presentationTimeNanoseconds: 3 * Self.second)   // repeated: nothing
        XCTAssertEqual(clock.elapsedNanoseconds, 100_000_000)
    }

    func testZeroDurationAndInstantSpecsAreFinishedAtOnce() throws {
        XCTAssertEqual(SceneTransitionClock(durationNanoseconds: 0).progress, 1)
        XCTAssertEqual(SceneTransitionClock(spec: .cut).progress, 1)
        let zero = try SceneTransitionSpec(style: .crossfade, durationSeconds: 0)
        XCTAssertTrue(zero.isInstant)
        XCTAssertEqual(SceneTransitionClock(spec: zero).progress, 1)
        XCTAssertFalse(SceneTransitionSpec.defaultCrossfade.isInstant)
    }

    // MARK: Easing and weights (CMP-014-R3)

    func testEasingIsExactAtTheEndsAndMonotonic() {
        for easing in SceneTransitionEasing.allCases {
            XCTAssertEqual(easing.ease(0), 0)
            XCTAssertEqual(easing.ease(1), 1)
            XCTAssertEqual(easing.ease(0.5), 0.5)
            var last = -1.0
            for i in 0...100 {
                let value = easing.ease(Double(i) / 100)
                XCTAssertGreaterThanOrEqual(value, last, "\(easing) is monotonic")
                last = value
            }
        }
        XCTAssertEqual(SceneTransitionEasing.easeInOut.ease(0.25), 0.15625)
    }

    func testWeights() {
        XCTAssertEqual(SceneTransitionMix.weights(style: .crossfade, eased: 0), SceneTransitionWeights(outgoing: 1, incoming: 0))
        XCTAssertEqual(SceneTransitionMix.weights(style: .crossfade, eased: 0.5), SceneTransitionWeights(outgoing: 0.5, incoming: 0.5))
        XCTAssertEqual(SceneTransitionMix.weights(style: .crossfade, eased: 1), SceneTransitionWeights(outgoing: 0, incoming: 1))
        XCTAssertEqual(SceneTransitionMix.weights(style: .dipToBlack, eased: 0.25), SceneTransitionWeights(outgoing: 0.5, incoming: 0))
        XCTAssertEqual(SceneTransitionMix.weights(style: .dipToBlack, eased: 0.5), SceneTransitionWeights(outgoing: 0, incoming: 0))
        XCTAssertEqual(SceneTransitionMix.weights(style: .dipToBlack, eased: 0.75), SceneTransitionWeights(outgoing: 0, incoming: 0.5))
        XCTAssertEqual(SceneTransitionMix.weights(style: .cut, eased: 0.3), SceneTransitionWeights(outgoing: 0, incoming: 1))
    }

    // MARK: Spec (validation, Codable, Reduce Motion)

    func testSpecValidation() {
        XCTAssertThrowsError(try SceneTransitionSpec(style: .crossfade, durationSeconds: .nan))
        XCTAssertThrowsError(try SceneTransitionSpec(style: .crossfade, durationSeconds: -0.1))
        XCTAssertThrowsError(try SceneTransitionSpec(style: .crossfade, durationSeconds: 10.5))
        XCTAssertNoThrow(try SceneTransitionSpec(style: .dipToBlack, durationSeconds: 10))
        XCTAssertEqual(SceneTransitionSpec.defaultCrossfade.durationNanoseconds, 1_000_000_000)
    }

    func testSpecCodableRoundTripAndRefusal() throws {
        let spec = try SceneTransitionSpec(style: .dipToBlack, durationSeconds: 2.5, easing: .linear)
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(SceneTransitionSpec.self, from: data), spec)
        let bad = Data(#"{"style":"crossfade","durationSeconds":99}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneTransitionSpec.self, from: bad))
        let unknown = Data(#"{"style":"wipe","durationSeconds":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneTransitionSpec.self, from: unknown))
        let noEasing = Data(#"{"style":"crossfade","durationSeconds":1}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SceneTransitionSpec.self, from: noEasing), .defaultCrossfade)
    }

    func testReduceMotionResolvesToACut() throws {
        let fade = try SceneTransitionSpec(style: .crossfade, durationSeconds: 3)
        XCTAssertEqual(fade.resolved(reduceMotion: true), .cut)
        XCTAssertEqual(fade.resolved(reduceMotion: false), fade)
        XCTAssertEqual(SceneTransitionSpec.cut.resolved(reduceMotion: false), .cut)
    }
}
