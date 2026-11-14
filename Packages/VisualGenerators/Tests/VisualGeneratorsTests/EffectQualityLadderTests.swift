// EffectQualityLadderTests.swift — PERF-003-T03: the ladder's order, holds, hysteresis and fades with an injected
// clock (PERF-003-R1 to R5, R9; S1, S4). Pure arithmetic; runs on Linux (`-Xswiftc -DVISUAL_NO_METAL`).
import XCTest
@testable import VisualEffects

final class EffectQualityLadderTests: XCTestCase {
    /// Steps the ladder at 60 Hz from `from` for `seconds`; returns the time reached.
    @discardableResult
    private func run(_ ladder: EffectQualityLadder, from: Double, seconds: Double, thermal: EffectThermalState,
                     lowPower: Bool = false, budget: EffectBudgetSignal = .unavailable) -> Double {
        let frames = Int((seconds * 60).rounded())
        var t = from
        for i in 1...max(frames, 1) {
            t = from + Double(i) / 60
            ladder.step(time: t, thermal: thermal, lowPower: lowPower, budget: budget)
        }
        return t
    }

    /// A fresh loop whose clock starts at 0 (the first step after `start` only records the time).
    private func begin(_ ladder: EffectQualityLadder, _ thermal: EffectThermalState, _ lowPower: Bool) {
        ladder.start(thermal: thermal, lowPower: lowPower)
        ladder.step(time: 0, thermal: thermal, lowPower: lowPower, budget: .unavailable)
    }

    func testFloorTable() {
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .nominal, lowPower: false), .full)
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .fair, lowPower: false), .full)
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .serious, lowPower: false), .reduced)
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .critical, lowPower: false), .minimal)
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .nominal, lowPower: true), .reduced)
        XCTAssertEqual(EffectQualityLadder.floor(thermal: .critical, lowPower: true), .minimal)
    }

    /// Acceptance (S1): nominal → serious → critical steps Full → Reduced → Minimal, each after one fade.
    func testThermalStressStepsDownInOrder() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, false)
        var t = run(ladder, from: 0, seconds: 1, thermal: .nominal)
        XCTAssertEqual(ladder.applied, .full)
        XCTAssertEqual(ladder.overlayLine, "effect quality full")
        ladder.step(time: t + 1.0 / 60, thermal: .serious, lowPower: false, budget: .unavailable)
        XCTAssertEqual(ladder.target, .reduced, "thermal step-downs are immediate")
        XCTAssertEqual(ladder.applied, .full, "the plan switches only at zero glow")
        t = run(ladder, from: t + 1.0 / 60, seconds: 1, thermal: .serious)
        XCTAssertEqual(ladder.applied, .reduced)
        XCTAssertEqual(ladder.glowWeight, 1)
        XCTAssertEqual(ladder.overlayLine, "effect quality reduced (thermal)")
        t = run(ladder, from: t, seconds: 1, thermal: .critical)
        XCTAssertEqual(ladder.applied, .minimal)
        XCTAssertEqual(ladder.intensityFactor, 0)
        XCTAssertEqual(ladder.overlayLine, "effect quality minimal (thermal)")
    }

    func testNominalToCriticalGoesStraightToMinimalWithOneFade() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, false)
        var seen: Set<Int> = []
        var t = 0.0
        for i in 1...60 {
            t = Double(i) / 60
            ladder.step(time: t, thermal: .critical, lowPower: false, budget: .unavailable)
            seen.insert(ladder.applied.rawValue)
        }
        XCTAssertEqual(seen, [EffectQualityLevel.full.rawValue, EffectQualityLevel.minimal.rawValue], "never drawn at Reduced")
        XCTAssertEqual(ladder.applied, .minimal)
    }

    func testLowPowerGivesReducedWithItsReason() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, true)
        XCTAssertEqual(ladder.applied, .reduced)
        XCTAssertEqual(ladder.overlayLine, "effect quality reduced (low power)")
        XCTAssertEqual(ladder.glowWeight, 1, "start applies the floor without a fade")
    }

    /// R3: a sustained over-budget verdict lowers one step per 3 s; 2.9 s is not enough; unavailable clears the timer.
    func testSustainedOverBudgetStepsDown() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, false)
        var t = run(ladder, from: 0, seconds: 2.9, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .full)
        t = run(ladder, from: t, seconds: 0.5, thermal: .nominal, budget: .unavailable)   // clears the timer
        t = run(ladder, from: t, seconds: 2.9, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .full, "the over-budget time restarted")
        t = run(ladder, from: t, seconds: 0.2, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .reduced)
        XCTAssertEqual(ladder.reason, .budget)
        t = run(ladder, from: t, seconds: 3.0, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .minimal)
        run(ladder, from: t, seconds: 6, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .minimal, "never below Minimal")
        XCTAssertEqual(ladder.applied, .minimal)
    }

    /// R4, S4: recovery from Minimal takes two steps, each after at least 10 s of good conditions.
    func testRecoveryStepsUpWithHysteresis() {
        let ladder = EffectQualityLadder()
        begin(ladder, .critical, false)
        var t = run(ladder, from: 0, seconds: 9.9, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.target, .minimal, "9.9 s is not enough")
        t = run(ladder, from: t, seconds: 0.2, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.target, .reduced)
        XCTAssertEqual(ladder.reason, .budget, "below Full with no thermal or Low Power cause")
        t = run(ladder, from: t, seconds: 5, thermal: .nominal, budget: .within)
        t = run(ladder, from: t, seconds: 3.1, thermal: .nominal, budget: .over)   // an over-budget spell resets recovery
        XCTAssertEqual(ladder.target, .minimal, "3 s over budget steps down again")
        t = run(ladder, from: t, seconds: 10.1, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.target, .reduced)
        t = run(ladder, from: t, seconds: 10.1, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.target, .full)
        run(ladder, from: t, seconds: 1, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.applied, .full)
        XCTAssertEqual(ladder.glowWeight, 1)
        XCTAssertNil(ladder.reason)
    }

    func testRecoveryNeverRisesAboveTheFloor() {
        let ladder = EffectQualityLadder()
        begin(ladder, .critical, false)
        run(ladder, from: 0, seconds: 30, thermal: .serious)
        XCTAssertEqual(ladder.target, .reduced)
        XCTAssertEqual(ladder.reason, .thermal)
    }

    /// R9: fade out over 0.4 s, switch at zero, fade in over 0.4 s; the weight never jumps.
    func testLevelChangesFadeAndNeverJump() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, false)
        var previous: Float = ladder.glowWeight
        var switchedAt: Double?
        var restoredAt: Double?
        for i in 1...120 {
            let t = Double(i) / 60
            ladder.step(time: t, thermal: .serious, lowPower: false, budget: .unavailable)
            XCTAssertLessThanOrEqual(abs(ladder.glowWeight - previous), Float(1.0 / 60 / 0.4) + 1e-5, "t=\(t)")
            if ladder.applied == .reduced, switchedAt == nil {
                switchedAt = t
                XCTAssertEqual(ladder.glowWeight, 0)
            }
            if switchedAt != nil, ladder.glowWeight == 1, restoredAt == nil { restoredAt = t }
            previous = ladder.glowWeight
        }
        XCTAssertEqual(try XCTUnwrap(switchedAt), 0.4, accuracy: 1.0 / 60 + 1e-9)
        XCTAssertEqual(try XCTUnwrap(restoredAt), 0.8, accuracy: 2.0 / 60 + 1e-9)
    }

    func testAChangeMidFadeReversesFromTheCurrentWeight() {
        let ladder = EffectQualityLadder()
        begin(ladder, .nominal, false)
        for i in 1...12 { ladder.step(time: Double(i) / 60, thermal: .serious, lowPower: false, budget: .unavailable) }   // 0.2 s
        XCTAssertEqual(ladder.glowWeight, 0.5, accuracy: 1e-4)
        // Low Power alone would ask Reduced too; nominal with no Low Power asks Full, but recovery needs 10 s, so the
        // target stays Reduced: the fade keeps going down.
        ladder.step(time: 13.0 / 60, thermal: .nominal, lowPower: false, budget: .unavailable)
        XCTAssertEqual(ladder.target, .reduced)
        XCTAssertLessThan(ladder.glowWeight, 0.5)
    }

    func testTargetReturningMidFadeFadesBackIn() {
        let ladder = EffectQualityLadder(policy: EffectQualityPolicy(overBudgetHold: 0.1, recoveryHold: 0.1))
        begin(ladder, .nominal, false)
        var t = run(ladder, from: 0, seconds: 0.15, thermal: .nominal, budget: .over)
        XCTAssertEqual(ladder.target, .reduced)
        let low = ladder.glowWeight
        XCTAssertLessThan(low, 1)
        XCTAssertGreaterThan(low, 0)
        t = run(ladder, from: t, seconds: 0.12, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.target, .full)
        XCTAssertEqual(ladder.applied, .full, "the switch never happened")
        run(ladder, from: t, seconds: 0.5, thermal: .nominal, budget: .within)
        XCTAssertEqual(ladder.glowWeight, 1)
    }

    func testBackwardsAndNonFiniteTimesAreIgnored() {
        let ladder = EffectQualityLadder()
        ladder.start(thermal: .nominal, lowPower: false)
        ladder.step(time: 10, thermal: .nominal, lowPower: false, budget: .over)
        ladder.step(time: .nan, thermal: .nominal, lowPower: false, budget: .over)
        ladder.step(time: .infinity, thermal: .nominal, lowPower: false, budget: .over)
        ladder.step(time: 5, thermal: .nominal, lowPower: false, budget: .over)
        ladder.step(time: 12.9, thermal: .nominal, lowPower: false, budget: .over)
        XCTAssertEqual(ladder.target, .full, "only 2.9 s of valid over-budget time")
        ladder.step(time: 13.1, thermal: .nominal, lowPower: false, budget: .over)
        XCTAssertEqual(ladder.target, .reduced)
    }

    func testDeterministic() {
        func trace() -> [String] {
            let ladder = EffectQualityLadder()
            begin(ladder, .nominal, false)
            var out: [String] = []
            let thermals: [EffectThermalState] = [.nominal, .serious, .critical, .fair]
            for i in 1...1200 {
                let thermal = thermals[(i / 300) % thermals.count]
                let budget: EffectBudgetSignal = i % 400 < 250 ? .over : .within
                ladder.step(time: Double(i) / 60, thermal: thermal, lowPower: false, budget: budget)
                out.append("\(ladder.target.rawValue)\(ladder.applied.rawValue)\(ladder.glowWeight)")
            }
            return out
        }
        XCTAssertEqual(trace(), trace())
    }

    func testPolicyRejectsInvalidValues() {
        let policy = EffectQualityPolicy(overBudgetHold: .nan, recoveryHold: -1, fadeDuration: 0)
        XCTAssertEqual(policy, .standard)
        XCTAssertEqual(EffectThermalState(label: "serious"), .serious)
        XCTAssertNil(EffectThermalState(label: "hot"))
    }
}
