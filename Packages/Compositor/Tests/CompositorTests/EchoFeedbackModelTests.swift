// FX-010-T03: the echo model in plain Swift (also runs in the Linux shape): the cap, the ranges, the weights and their
// cap, ACC-012, the bounded history size, the storing schedule and the CPU references (FX-010-R2 to R6, R10, R15).
@testable import Compositor
import FlashSafety
import XCTest

final class EchoFeedbackModelTests: XCTestCase {
    private let on = EchoFeedback(isEnabled: true)

    // MARK: - The cap (roadmap acceptance, FX-010-S1)

    func testCountIsCappedAtFourEverywhere() {
        XCTAssertEqual(EchoFeedback.cap, 4)
        for request in [5, 8, 1000, Int.max] {
            XCTAssertEqual(EchoFeedback.clampCount(request), 4, "\(request)")
            let e = EchoFeedback(isEnabled: true, count: request)
            XCTAssertEqual(e.effectiveCount, 4)
            XCTAssertEqual(e.weights(valid: 1000).count, 4, "\(request) echoes draw exactly 4")
            XCTAssertEqual(e.clamped.count, 4)
        }
        XCTAssertEqual(EchoFeedback.clampCount(Double.infinity), 4)
        XCTAssertEqual(EchoFeedback.clampCount(7.6), 4)
        XCTAssertEqual(EchoFeedback.clampCount(2.4), 2)
        XCTAssertEqual(EchoFeedback.clampCount(-3), 0)
        XCTAssertEqual(EchoFeedback.clampCount(Double.nan), EchoFeedback.defaultCount)
    }

    func testInactiveWhenOffZeroCountOrZeroCap() {
        XCTAssertFalse(EchoFeedback.off.isActive)
        XCTAssertFalse(EchoFeedback(isEnabled: true, count: 0).isActive)
        XCTAssertFalse(EchoFeedback(isEnabled: true, weightCap: 0).isActive)
        XCTAssertTrue(on.isActive)
        XCTAssertEqual(EchoFeedback(isEnabled: true, count: 0).weights(valid: 4), [])
        XCTAssertEqual(on.weights(valid: 0), [], "nothing stored: no echo")
    }

    func testRangesClamp() {
        XCTAssertEqual(EchoFeedback.clampDelay(0), 0.01)
        XCTAssertEqual(EchoFeedback.clampDelay(9), 0.5)
        XCTAssertEqual(EchoFeedback.clampDelay(.nan), EchoFeedback.defaultDelay)
        XCTAssertEqual(EchoFeedback.clampDecay(1), 0.9)
        XCTAssertEqual(EchoFeedback.clampDecay(-1), 0.1)
        XCTAssertEqual(EchoFeedback.clampDecay(.nan), EchoFeedback.defaultDecay)
        XCTAssertEqual(EchoFeedback.clampWeightCap(3), 1)
        XCTAssertEqual(EchoFeedback.clampWeightCap(-.infinity), 0)
    }

    // MARK: - Weights (FX-010-R2, S3)

    func testWeightsDecayAndNeverSumAboveTheCap() {
        let light = EchoFeedback(isEnabled: true, count: 2, decay: 0.3)   // 0.3 + 0.09 < 1: unscaled
        XCTAssertEqual(light.weights(valid: 4)[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(light.weights(valid: 4)[1], 0.09, accuracy: 1e-6)
        for decay in [0.1, 0.5, 0.6, 0.9] {
            for count in 1...4 {
                for cap in [1.0, 0.5, 0.25] {
                    let e = EchoFeedback(isEnabled: true, count: count, decay: decay, weightCap: cap)
                    let w: [Float] = e.weights(valid: 4)
                    XCTAssertEqual(w.count, count)
                    XCTAssertLessThanOrEqual(w.reduce(Float(0), +), Float(cap), "\(decay) \(count) \(cap)")
                    for k in 1..<w.count {
                        XCTAssertEqual(w[k] / w[k - 1], Float(decay), accuracy: 1e-5, "each echo is weaker by the fade")
                    }
                }
            }
        }
        XCTAssertEqual(on.weights(valid: 2).count, 2, "only stored frames are drawn")
    }

    // MARK: - ACC-012 (FX-010-R10)

    func testSafetyProfileLimitsTheWeightSum() {
        XCTAssertEqual(on.limited(by: .standard), on, "Standard leaves the value unchanged")
        let reduce = SafetyClamp(profile: .standard, reduceFlashingSetting: true)
        XCTAssertEqual(on.limited(by: reduce).weightCap, 0.5)
        XCTAssertLessThanOrEqual(on.limited(by: reduce).weights(valid: 4).reduce(Float(0), +), 0.5)
        let zero = SafetyClamp(profile: SensorySafetyProfile(preset: .custom,
                                                             custom: SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: nil,
                                                                                         intensityLimit: 0)),
                               reduceFlashingSetting: false)
        XCTAssertFalse(on.limited(by: zero).isActive, "a cap of 0 turns Echo off")
        XCTAssertEqual(EchoFeedback.off.limited(by: reduce), .off)
    }

    // MARK: - Bounded history (roadmap acceptance, FX-010-R6, R7)

    func testHistorySizePerDeviceClassStaysUnderTheBound() {
        let cases: [(Int, Int, Int, Int)] = [
            (2556, 1179, 960, 432),   // D1 iPhone 15
            (2752, 2064, 960, 720),   // D2 iPad Pro M5
            (2360, 1640, 960, 656),   // D3 iPad A16
            (3840, 2160, 960, 544),   // 4K external display
            (1920, 1080, 960, 544),
            (32, 32, 16, 16),
            (1, 1, 16, 16),
        ]
        for (w, h, hw, hh) in cases {
            let size = EchoFeedback.historySize(width: w, height: h)
            XCTAssertEqual(size?.width, hw, "\(w)×\(h)")
            XCTAssertEqual(size?.height, hh, "\(w)×\(h)")
            XCTAssertLessThanOrEqual(EchoFeedback.historyBytes(width: w, height: h), EchoFeedback.historyBytesBound)
        }
        XCTAssertEqual(EchoFeedback.historyBytesBound, 29_491_200)
        XCTAssertEqual(EchoFeedback.historyBytes(width: 2556, height: 1179), 13_271_040)
        for side in [100, 1000, 5000, 16_384] {
            XCTAssertLessThanOrEqual(EchoFeedback.historyBytes(width: side, height: side), EchoFeedback.historyBytesBound)
            XCTAssertLessThanOrEqual(EchoFeedback.historyBytes(width: side, height: 7), EchoFeedback.historyBytesBound)
        }
        XCTAssertNil(EchoFeedback.historySize(width: 0, height: 10))
        let a = EchoFeedback.historySize(width: 32, height: 32), b = EchoFeedback.historySize(width: 34, height: 30)
        XCTAssertTrue(a?.width == b?.width && a?.height == b?.height, "a small resize keeps the size class")
    }

    // MARK: - Schedule (FX-010-R5, R11)

    func testOneFrameDelayStoresEveryFrameAndEchoKIsKFramesOld() {
        var s = EchoSchedule()
        var storedFrame: [Int: Int] = [:]   // slot → frame
        for frame in 0..<10 {
            if frame >= 1 {   // before this frame's store, echo k reads frame − k
                for k in 1...min(s.valid, 4) { XCTAssertEqual(storedFrame[s.slot(echo: k)], frame - k, "frame \(frame) echo \(k)") }
            }
            XCTAssertTrue(s.advance(frameDuration: 0.0625, delay: 0.05))
            storedFrame[s.nextSlot] = frame
            s.stored(delay: 0.05)
        }
        XCTAssertEqual(s.valid, 4, "the ring holds the cap")
    }

    func testLongerDelayStoresOncePerDelay() {
        var s = EchoSchedule()
        var stores: [Int] = []
        for frame in 0..<9 where s.advance(frameDuration: 0.0625, delay: 0.125) {
            stores.append(frame)
            s.stored(delay: 0.125)
        }
        XCTAssertEqual(stores, [0, 2, 4, 6, 8], "the first frame at once, then every 125 ms")
        var t = EchoSchedule()
        var long: [Int] = []
        for frame in 0..<4 where t.advance(frameDuration: 1, delay: 0.1) {   // a 1 s frame stores once, not ten times
            long.append(frame)
            t.stored(delay: 0.1)
        }
        XCTAssertEqual(long, [0, 1, 2, 3])
        t.reset()
        XCTAssertEqual(t.valid, 0)
        XCTAssertTrue(t.advance(frameDuration: 0, delay: 0.5), "after a reset the next frame stores at once")
    }

    // MARK: - CPU references (FX-010-R15)

    func testDownsampleIsAnExactBoxAtHalfSizeAndSanitises() {
        var pixels = [SIMD4<Float>](repeating: .zero, count: 4 * 4)
        pixels[0] = SIMD4<Float>(1, 1, 1, 1)
        pixels[5] = SIMD4<Float>(.nan, 2, -1, 3)
        let out: [SIMD4<Float>] = EchoFeedback.downsample(pixels, width: 4, height: 4, historyWidth: 2, historyHeight: 2)
        XCTAssertEqual(out[0], SIMD4<Float>(0.25, 0.75, 0.25, 0.5), "mean of the 2 × 2 block, NaN → 0, < 0 → 0, alpha ≤ 1")
        XCTAssertEqual(out[3], .zero)
    }

    func testReferencePixelIsTheBrighterOfCurrentAndWeightedEchoes() {
        let history: [[SIMD4<Float>]] = [[SIMD4<Float>](repeating: SIMD4<Float>(1, 0, 0, 1), count: 4),
                                         [SIMD4<Float>](repeating: SIMD4<Float>(0, 1, 0, 1), count: 4)]
        let current = SIMD4<Float>(0.1, 0.1, 0.9, 1)
        let p: SIMD4<Float> = EchoFeedback.referencePixel(current: current, x: 1, y: 1, width: 4, height: 4, history: history,
                                                          historyWidth: 2, historyHeight: 2, weights: [0.5, 0.25])
        XCTAssertEqual(p, SIMD4<Float>(0.5, 0.25, 0.9, 1))
        let bad = SIMD4<Float>(.infinity, 0, 0, 1)
        XCTAssertEqual(EchoFeedback.referencePixel(current: bad, x: 0, y: 0, width: 4, height: 4, history: history,
                                                   historyWidth: 2, historyHeight: 2, weights: [0.5]).x, .infinity)
        let frame = [SIMD4<Float>](repeating: current, count: 16)
        XCTAssertEqual(EchoFeedback.reference(frame, width: 4, height: 4, history: history, historyWidth: 2, historyHeight: 2,
                                              weights: []), frame, "no echo: the input itself")
    }
}
