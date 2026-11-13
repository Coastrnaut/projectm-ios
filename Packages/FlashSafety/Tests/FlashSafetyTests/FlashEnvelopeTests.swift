// FlashEnvelopeTests.swift — FX-019-T04: the decision rule (FX-019-R5 to R8, R10, R11) on small
// hand-checked cases. Pure arithmetic with constant frame times; no clock.
import XCTest
@testable import FlashSafety

final class FlashEnvelopeTests: XCTestCase {
    private let dt = 1.0 / 60

    /// One frame whose 17 areas all have `levels` (a full-screen solid frame).
    @discardableResult
    func solid(_ envelope: FlashEnvelope, _ luminance: Double, redness: Double = 0, frameTime: Double = 1.0 / 60,
               _ configuration: FlashEnvelopeConfiguration) -> Float {
        let inputs = [FlashLevels](repeating: FlashLevels(luminance: luminance, redness: redness), count: FlashZones.count)
        return inputs.withUnsafeBufferPointer { envelope.gain(inputs: $0, frameTime: frameTime, configuration: configuration) }
    }

    func testConfigurations() {
        let on = FlashEnvelopeConfiguration.reduceFlashing, off = FlashEnvelopeConfiguration.alwaysOn
        XCTAssertEqual(on.transitionBudget, 4)
        XCTAssertEqual(on.riseRatePerSecond, 0.25)
        XCTAssertEqual(off.transitionBudget, 6)
        XCTAssertNil(off.riseRatePerSecond)
        for c in [on, off] {
            XCTAssertEqual(c.window, 1)
            XCTAssertEqual(c.luminanceThreshold, 0.10)
            XCTAssertEqual(c.rednessThreshold, 0.0625)
            XCTAssertEqual(c.gateMargin, 0.005)
            XCTAssertEqual(c.maxFrameTime, 0.1)
        }
        XCTAssertEqual(FlashEnvelopeConfiguration.forReduceFlashing(true), on)
        XCTAssertEqual(FlashEnvelopeConfiguration.forReduceFlashing(false), off)
        var c = on
        c.transitionBudget = 99
        XCTAssertEqual(c.transitionBudget, 6, "clamped to 2…6")
        c.transitionBudget = 0
        XCTAssertEqual(c.transitionBudget, 2)
        XCTAssertEqual(on.clampedFrameTime(5), 0.1)
        XCTAssertEqual(on.clampedFrameTime(-1), 0)
        XCTAssertEqual(on.clampedFrameTime(.nan), 0)
    }

    func testFirstFrameAndResetShowTheInput() {
        let e = FlashEnvelope()
        XCTAssertEqual(solid(e, 1, .reduceFlashing), 1, "no history: shown as it is")
        solid(e, 0, .reduceFlashing)
        XCTAssertLessThan(solid(e, 1, .reduceFlashing), 1)
        e.reset()
        XCTAssertEqual(solid(e, 1, .reduceFlashing), 1)
    }

    func testGainIsAlwaysWithinZeroAndOne() {
        let e = FlashEnvelope()
        for v in [0.5, .nan, .infinity, -3, 1e9, 0, 1] {
            let g = solid(e, v, redness: v, .reduceFlashing)
            XCTAssertTrue(g >= 0 && g <= 1, "gain \(g) for \(v)")
        }
    }

    func testRiseRate() {
        let e = FlashEnvelope()
        solid(e, 0, frameTime: 0.1, .reduceFlashing)
        let g1 = solid(e, 1, frameTime: 0.1, .reduceFlashing)
        XCTAssertEqual(Double(g1), 0.025, accuracy: 1e-6, "0.25/s × 0.1 s")
        XCTAssertEqual(e.shown(zone: FlashZones.wholeFrame).luminance, 0.025, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(e.shown(zone: FlashZones.wholeFrame).luminance, 0.025)
        let g2 = solid(e, 1, frameTime: 5, .reduceFlashing)
        XCTAssertEqual(Double(g2), 0.05, accuracy: 1e-6, "a stall counts as 0.1 s")
        let g3 = solid(e, 1, frameTime: -1, .reduceFlashing)
        XCTAssertEqual(Double(g3), 0.05, accuracy: 1e-6, "a negative frame time moves nothing")
        XCTAssertEqual(solid(e, 0.01, .reduceFlashing), 1, "darker frames are never changed")
    }

    func testGateHoldsARiseOnceTheBudgetIsReservedAndReleasesItAfterTheWindow() {
        let off = FlashEnvelopeConfiguration.alwaysOn   // budget 6, no rate limit
        let e = FlashEnvelope()
        solid(e, 1, off)                                // t = 0, first frame
        var transitions = 0
        var frame = 0
        // white/black every frame: fall, rise, fall, rise, fall are allowed (5 ≤ 6)…
        while transitions < 5 {
            frame += 1
            let white = frame % 2 == 0
            XCTAssertEqual(solid(e, white ? 1 : 0, off), 1, "frame \(frame) passes")
            transitions += 1
        }
        // …the next rise would leave no room for its fall: held below black + 0.10.
        let held = solid(e, 1, off)
        XCTAssertEqual(Double(held), 0.095, accuracy: 1e-6)
        // Falls are never held.
        XCTAssertEqual(solid(e, 0, off), 1)
        // Once the oldest transition is older than the window, the rise is allowed again.
        var released: Float = 0
        for _ in 0..<60 { released = solid(e, 1, off) }
        XCTAssertEqual(released, 1)
    }

    func testRednessHasItsOwnThresholdAndGate() {
        let off = FlashEnvelopeConfiguration.alwaysOn
        let e = FlashEnvelope()
        // Dark red: luminance 0.085 (sub-threshold) but redness 0.4 (over 0.0625).
        solid(e, 0, redness: 0, off)
        for n in 0..<6 { XCTAssertEqual(solid(e, n % 2 == 0 ? 0.085 : 0, redness: n % 2 == 0 ? 0.4 : 0, off), 1, "frame \(n)") }
        let held = solid(e, 0.085, redness: 0.4, off)
        XCTAssertEqual(Double(held) * 0.4, 0.0625 - 0.005, accuracy: 1e-6, "redness held below its threshold")
    }

    func testALocalStrobeDimsTheWholeFrame() {
        let off = FlashEnvelopeConfiguration.alwaysOn
        let e = FlashEnvelope()
        var inputs = [FlashLevels](repeating: FlashLevels(luminance: 0.2, redness: 0), count: FlashZones.count)
        var gains: [Float] = []
        for n in 0..<8 {
            inputs[5].luminance = n % 2 == 0 ? 1 : 0           // one tile strobes
            inputs[FlashZones.wholeFrame].luminance = 0.2 + (n % 2 == 0 ? 1.0 / 16 : 0)  // the mean barely moves
            gains.append(inputs.withUnsafeBufferPointer { e.gain(inputs: $0, frameTime: dt, configuration: off) })
        }
        XCTAssertEqual(Array(gains.prefix(6)), [1, 1, 1, 1, 1, 1])
        XCTAssertLessThan(gains[6], 0.2, "tile 5's seventh transition is refused, so the frame is dimmed")
    }

    func testClosureAPIMatchesTheLinearAPI() {
        let a = FlashEnvelope(), b = FlashEnvelope()
        var seed: UInt64 = 7
        for _ in 0..<120 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = Double(seed >> 11) / Double(1 << 53)
            let inputs = (0..<FlashZones.count).map { FlashLevels(luminance: v * Double($0 + 1) / 17, redness: v / 3) }
            let ga = inputs.withUnsafeBufferPointer { a.gain(inputs: $0, frameTime: dt, configuration: .reduceFlashing) }
            let gb = b.gain(frameTime: dt, configuration: .reduceFlashing) { g, out in
                for z in 0..<FlashZones.count {
                    out[z] = FlashLevels(luminance: inputs[z].luminance * Double(g), redness: inputs[z].redness * Double(g))
                }
            }
            XCTAssertEqual(ga, gb, accuracy: 1e-5, "bisection (2⁻²⁴) and float rounding, compounding through the rate limit")
        }
    }

    func testClosureAPIWithABrightFloorGivesZero() {
        let e = FlashEnvelope()
        let floor = 0.3
        _ = e.gain(frameTime: dt, configuration: .reduceFlashing) { _, out in
            for z in 0..<FlashZones.count { out[z] = FlashLevels(luminance: 0, redness: 0) }
        }
        let g = e.gain(frameTime: dt, configuration: .reduceFlashing) { g, out in
            for z in 0..<FlashZones.count { out[z] = FlashLevels(luminance: floor + 0.5 * Double(g), redness: 0) }
        }
        XCTAssertEqual(g, 0, "even gain 0 exceeds the ceiling: the darkest possible frame")
    }

    func testHistorySurvivesAConfigurationChange() {
        let e = FlashEnvelope()
        let off = FlashEnvelopeConfiguration.alwaysOn
        solid(e, 1, off)
        for n in 0..<3 { solid(e, n % 2 == 0 ? 0 : 1, off) }   // 3 transitions; now black
        // Switching to budget 4 (no rate limit, to isolate the gate): 3 > 4 − 2, so the rise is held
        // at once — the three earlier transitions were kept.
        var strict = FlashEnvelopeConfiguration.reduceFlashing
        strict.riseRatePerSecond = nil
        XCTAssertEqual(Double(solid(e, 1, strict)), 0.095, accuracy: 1e-6)
        e.reset()
        XCTAssertEqual(solid(e, 1, .reduceFlashing), 1)
    }
}
