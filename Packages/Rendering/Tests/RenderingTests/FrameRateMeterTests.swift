// Task T070: frame rate from presentation timestamps in 1-second windows (FR-048 overlay).
import XCTest
@testable import Rendering

final class FrameRateMeterTests: XCTestCase {
    func testSixtyFramesPerSecond() {
        var meter = FrameRateMeter()
        var completed = 0
        for i in 0...120 { if meter.record(presentedAt: Double(i) / 60) { completed += 1 } }
        XCTAssertEqual(completed, 2)
        XCTAssertEqual(meter.metrics.framesPerSecond, 60, accuracy: 0.01)
        XCTAssertEqual(meter.metrics.meanFrameTimeMs, 1000.0 / 60, accuracy: 0.01)
    }

    func testSlowFrameRaisesTheMaximum() {
        var meter = FrameRateMeter()
        var t = 0.0
        _ = meter.record(presentedAt: t)
        for i in 1...40 {
            t += i == 20 ? 0.1 : 1.0 / 30   // one 100 ms frame
            meter.record(presentedAt: t)
        }
        XCTAssertEqual(meter.metrics.maxFrameTimeMs, 100, accuracy: 0.5)
        XCTAssertLessThan(meter.metrics.framesPerSecond, 30)
        XCTAssertGreaterThan(meter.metrics.framesPerSecond, 25)
    }

    func testAPauseStartsANewWindowInsteadOfCountingAsAFrame() {
        var meter = FrameRateMeter()
        for i in 0...30 { meter.record(presentedAt: Double(i) / 60) }   // half a window
        for i in 0...60 { meter.record(presentedAt: 10 + Double(i) / 60) }
        XCTAssertEqual(meter.metrics.framesPerSecond, 60, accuracy: 0.01)
        XCTAssertLessThan(meter.metrics.maxFrameTimeMs, 20)
    }

    func testNoMetricsBeforeTheFirstWindow() {
        var meter = FrameRateMeter()
        for i in 0..<30 { meter.record(presentedAt: Double(i) / 60) }
        XCTAssertEqual(meter.metrics, .zero)
    }
}
