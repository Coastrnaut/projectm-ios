// MED-008-T03: the plain-Swift animation model (MED-008-R4 to R6, R8, R13): delay clamps, the looping timeline, the
// budget classes and decoded size, and the frame cache's byte accounting. Runs on Linux too.
import ImageLayer
import XCTest

final class AnimatedImageModelTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    func testDelaysFollowTheBrowserRuleTheCapAndReduceFlashing() {
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: nil, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.01, reduceFlashing: false), 100 * ms, "under 20 ms → 100 ms")
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: .nan, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: -1, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.02, reduceFlashing: false), 20 * ms, "20 ms is kept")
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.25, reduceFlashing: false), 250 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: Double(Float(0.2)), reduceFlashing: false), 200 * ms, "32-bit float delays")
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: Double(Float(0.02)), reduceFlashing: false), 20 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.0195, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 3600, reduceFlashing: false), 60_000 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: .infinity, reduceFlashing: false), 100 * ms)
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.1, reduceFlashing: true), 334 * ms, "at most 3 changes a second")
        XCTAssertEqual(AnimationDelayRule.clamped(seconds: 0.5, reduceFlashing: true), 500 * ms)
    }

    /// MED-008-S1 (model): frame(t + total) == frame(t); boundaries at the clamped delays.
    func testTheTimelineLoopsAndChangesFrameAtTheClampedDelays() {
        let timeline = AnimationTimeline(rawDelays: [0.01, 0.2, nil, 0.3], reduceFlashing: false)
        XCTAssertEqual(timeline.delays, [100 * ms, 200 * ms, 100 * ms, 300 * ms])
        XCTAssertEqual(timeline.starts, [0, 100 * ms, 300 * ms, 400 * ms])
        XCTAssertEqual(timeline.totalNanoseconds, 700 * ms)
        let expected: [(UInt64, Int)] = [(0, 0), (100 * ms - 1, 0), (100 * ms, 1), (300 * ms - 1, 1), (300 * ms, 2),
                                         (400 * ms, 3), (700 * ms - 1, 3), (700 * ms, 0)]
        for (t, frame) in expected { XCTAssertEqual(timeline.frameIndex(elapsedNanoseconds: t), frame, "t = \(t)") }
        var t: UInt64 = 0
        while t < 2 * timeline.totalNanoseconds {
            let a: Int = timeline.frameIndex(elapsedNanoseconds: t)
            XCTAssertEqual(timeline.frameIndex(elapsedNanoseconds: t + timeline.totalNanoseconds), a)
            XCTAssertEqual(timeline.frameIndex(elapsedNanoseconds: t + 50 * timeline.totalNanoseconds), a)
            t += 7 * ms
        }
        XCTAssertEqual(AnimationTimeline(rawDelays: [], reduceFlashing: false).frameCount, 1)
        let reduced = AnimationTimeline(rawDelays: [0.1, 0.1], reduceFlashing: true)
        XCTAssertEqual(reduced.frameIndex(elapsedNanoseconds: 333 * ms), 0)
        XCTAssertEqual(reduced.frameIndex(elapsedNanoseconds: 334 * ms), 1)
    }

    func testBudgetClassesAndTheDecodedSizeFit() {
        let gib: UInt64 = 1 << 30
        XCTAssertEqual(AnimatedFrameBudget.bytes(physicalMemory: 3 * gib), 32 << 20)
        XCTAssertEqual(AnimatedFrameBudget.bytes(physicalMemory: 6 * gib), 64 << 20)
        XCTAssertEqual(AnimatedFrameBudget.bytes(physicalMemory: 16 * gib), 128 << 20)
        for budget in [16 << 20, 32 << 20, 64 << 20, 1 << 16] {
            let size = AnimatedFrameBudget.decodedSize(width: 2048, height: 1024, budget: budget, maxSide: 2048)
            let frames: Int = AnimatedFrameBudget.residentFrames + AnimatedFrameBudget.reserveFrames
            XCTAssertLessThanOrEqual(frames * AnimatedFrameBudget.accountedFrameBytes(width: size.width, height: size.height), budget)
            XCTAssertLessThanOrEqual(size.width, 2048)
            XCTAssertEqual(Double(size.width) / Double(size.height), 2, accuracy: 0.1)
        }
        let small = AnimatedFrameBudget.decodedSize(width: 64, height: 48, budget: 32 << 20, maxSide: 2048)
        XCTAssertTrue(small == (64, 48), "a small animation is never scaled up or down")
    }

    func testTheCacheEvictsLeastRecentlyUsedNeverFrameZeroOrThePinnedAndStaysInBudget() {
        var cache = AnimatedFrameCache<Int>(budgetBytes: 600)
        XCTAssertTrue(cache.reserve(400))
        XCTAssertTrue(cache.commit(0, payload: 0, bytes: 100, reserved: 400))
        for index in 1...20 {
            cache.pinned = index - 1
            XCTAssertTrue(cache.reserve(400), "frame \(index)")
            XCTAssertTrue(cache.contains(0), "frame 0 stays")
            if index > 1 { XCTAssertTrue(cache.contains(index - 1), "the pinned frame stays") }
            XCTAssertTrue(cache.commit(index, payload: index, bytes: 100, reserved: 400))
            XCTAssertLessThanOrEqual(cache.accountedBytes, 600)
        }
        XCTAssertEqual(cache.peakBytes, 600)
        XCTAssertLessThanOrEqual(cache.residentFrames, 3)
        XCTAssertEqual(cache.payload(at: 20), 20)
        XCTAssertNil(cache.payload(at: 5))
        cache.pinned = 20
        XCTAssertFalse(cache.reserve(500), "cannot fit beside frame 0 and the pinned frame")
        XCTAssertEqual(cache.reservedBytes, 0)
        XCTAssertTrue(cache.reserve(300))
        cache.cancel(reserved: 300)
        XCTAssertEqual(cache.reservedBytes, 0)
    }

    func testImportLimitsScaleFramesToTheTotalPixelCap() {
        let limits = AnimatedImportLimits.standard
        let big = limits.storedSize(width: 2048, height: 2048, frames: 200, base: .standard)
        XCTAssertLessThanOrEqual(200 * big.width * big.height, limits.maxTotalPixels)
        XCTAssertEqual(big.width, big.height)
        let small = limits.storedSize(width: 320, height: 240, frames: 20, base: .standard)
        XCTAssertTrue(small == (320, 240))
        let wide = limits.storedSize(width: 8000, height: 1000, frames: 2, base: .standard)
        XCTAssertEqual(wide.width, 2048)
        let halved = limits.storedSize(width: 2048, height: 2048, frames: 200, base: .standard, pixelFactor: 0.5)
        XCTAssertLessThanOrEqual(halved.width * halved.height * 2, big.width * big.height + 2 * big.width)
    }
}
