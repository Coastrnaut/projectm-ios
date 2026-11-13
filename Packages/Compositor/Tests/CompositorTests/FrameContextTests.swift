// CMP-001-T04: the frame clock (CMP-001-R3; research CMP-001-D3). CPU only; every host.
import XCTest
@testable import Compositor

final class FrameContextTests: XCTestCase {
    private func next(_ clock: inout LayerFrameClock, _ t: UInt64, scale: Double = 2, reduce: Bool = false) -> LayerFrameContext {
        clock.next(presentationTimeNanoseconds: t, outputWidth: 64, outputHeight: 32, contentScale: scale, reduceFlashing: reduce)
    }

    func testFirstFrameHasIndexZeroAndNoDuration() {
        var clock = LayerFrameClock()
        let c = next(&clock, 5_000_000_000, reduce: true)
        XCTAssertEqual(c, LayerFrameContext(presentationTimeNanoseconds: 5_000_000_000, frameIndex: 0, frameDuration: 0,
                                            outputWidth: 64, outputHeight: 32, contentScale: 2, reduceFlashing: true))
    }

    func testDurationIsTheDifferenceClampedToOneTenthSecond() {
        var clock = LayerFrameClock()
        _ = next(&clock, 1_000_000_000)
        let a = next(&clock, 1_016_666_667)
        XCTAssertEqual(a.frameIndex, 1)
        XCTAssertEqual(a.frameDuration, 0.016666667, accuracy: 1e-12)
        let b = next(&clock, 3_000_000_000)   // a 2 s stall
        XCTAssertEqual(b.frameIndex, 2)
        XCTAssertEqual(b.frameDuration, LayerFrameClock.maxFrameDuration)
        XCTAssertEqual(LayerFrameClock.maxFrameDuration, 0.1)
    }

    func testTimeNeverRunsBackwards() {
        var clock = LayerFrameClock()
        _ = next(&clock, 2_000_000_000)
        let back = next(&clock, 1_000_000_000)
        XCTAssertEqual(back.presentationTimeNanoseconds, 2_000_000_000)
        XCTAssertEqual(back.frameDuration, 0)
        XCTAssertEqual(back.frameIndex, 1)
        let same = next(&clock, 2_000_000_000)
        XCTAssertEqual(same.frameDuration, 0)
        XCTAssertEqual(same.frameIndex, 2)
    }

    func testInvalidScaleReadsOne() {
        var clock = LayerFrameClock()
        XCTAssertEqual(next(&clock, 1, scale: .nan).contentScale, 1)
        XCTAssertEqual(next(&clock, 2, scale: 0).contentScale, 1)
        XCTAssertEqual(next(&clock, 3, scale: -2).contentScale, 1)
        XCTAssertEqual(next(&clock, 4, scale: .infinity).contentScale, 1)
        XCTAssertEqual(next(&clock, 5, scale: 3).contentScale, 3)
    }

    func testResetStartsOver() {
        var clock = LayerFrameClock()
        _ = next(&clock, 9_000_000_000)
        clock.reset()
        let c = next(&clock, 1_000_000_000)
        XCTAssertEqual(c.frameIndex, 0)
        XCTAssertEqual(c.presentationTimeNanoseconds, 1_000_000_000)
        XCTAssertEqual(c.frameDuration, 0)
    }
}
