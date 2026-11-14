// BeatRingFieldTests.swift — VIS-006-T03: the roadmap acceptance ("Four synthetic beats create exactly four
// independently timed rings") and the ring field's caps (VIS-006-S1 to S3, R3 to R6). The clock is injected
// as nanoseconds; nothing reads a wall clock. Pure Swift.
import FlashSafety
import XCTest
@testable import VisualGenerators

final class BeatRingFieldTests: XCTestCase {
    private static func ns(_ seconds: Double) -> UInt64 { UInt64((seconds * 1e9).rounded()) }

    private let beats: [Double] = [0, 0.4, 0.8, 1.2]
    private let life = BeatRingConfiguration.defaultLife

    private func fourBeats() -> BeatRingField {
        let field = BeatRingField()
        for t in beats {
            XCTAssertTrue(field.emit(atNanoseconds: Self.ns(10 + t), minimumInterval: BeatRingConfiguration.minimumInterval))
        }
        return field
    }

    /// The acceptance: four beats → exactly four rings, each following the curves at its own age; none after
    /// the last ring's life.
    func testFourSyntheticBeatsCreateFourIndependentlyTimedRings() {
        let field = fourBeats()
        let sample = 10 + 1.3
        let rings = field.rings(atNanoseconds: Self.ns(sample), life: life)
        XCTAssertEqual(rings.count, 4, "exactly four rings")
        XCTAssertEqual(rings.map(\.sequence), [0, 1, 2, 3])
        for (ring, beat) in zip(rings, beats) {
            let age = sample - (10 + beat)
            XCTAssertEqual(ring.age, age, accuracy: 1e-9)
            XCTAssertEqual(ring.radius, BeatRingConfiguration.radius(age: age, life: life), accuracy: 1e-9)
            XCTAssertEqual(ring.alpha, BeatRingConfiguration.alpha(age: age, life: life), accuracy: 1e-9)
        }
        // Independent: four distinct radii and brightnesses, the youngest smallest; the oldest dimmest.
        XCTAssertEqual(Set(rings.map(\.radius)).count, 4)
        XCTAssertEqual(rings.map(\.radius), rings.map(\.radius).sorted(by: >), "older rings are larger")
        XCTAssertLessThan(rings[0].alpha, rings[1].alpha)
        // Explicit curve values at age 0.5 s of a 1.5 s life: p = 1/3.
        let q = 1 - 1.0 / 3
        XCTAssertEqual(rings[2].radius, 0.05 + 0.9 * (1 - q * q), accuracy: 1e-9)
        XCTAssertEqual(rings[2].alpha, 0.8 * q * q, accuracy: 1e-9)
        // A ring's state does not depend on the others: the third beat alone gives the same third ring.
        let alone = BeatRingField()
        alone.emit(atNanoseconds: Self.ns(10.8), minimumInterval: 0)
        let single = alone.rings(atNanoseconds: Self.ns(sample), life: life)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].radius, rings[2].radius)
        XCTAssertEqual(single[0].alpha, rings[2].alpha)
        // After the last ring's life: zero rings.
        XCTAssertEqual(field.rings(atNanoseconds: Self.ns(10 + 1.2 + life - 1e-6), life: life).count, 1)
        XCTAssertEqual(field.rings(atNanoseconds: Self.ns(10 + 2.8), life: life).count, 0)
        XCTAssertEqual(field.storedCount, 0, "expired rings are removed")
    }

    func testCurvesStartAndEnd() {
        XCTAssertEqual(BeatRingConfiguration.radius(age: 0, life: 1.5), BeatRingConfiguration.startRadius)
        XCTAssertEqual(BeatRingConfiguration.radius(age: 1.5, life: 1.5), BeatRingConfiguration.endRadius, accuracy: 1e-12)
        XCTAssertEqual(BeatRingConfiguration.alpha(age: 0, life: 1.5), 0, "the attack starts dark")
        XCTAssertEqual(BeatRingConfiguration.alpha(age: 0.05, life: 1.5), 0.8 * pow(1 - 0.05 / 1.5, 2), accuracy: 1e-12)
        XCTAssertEqual(BeatRingConfiguration.alpha(age: 1.5, life: 1.5), 0)
        for age in stride(from: 0.0, through: 1.5, by: 0.01) {
            XCTAssertLessThanOrEqual(BeatRingConfiguration.alpha(age: age, life: 1.5), BeatRingConfiguration.peakAlpha)
        }
    }

    func testCapDropsTheOldest() {
        let field = BeatRingField()
        for i in 0..<20 { field.emit(atNanoseconds: Self.ns(Double(i) * 0.2), minimumInterval: BeatRingConfiguration.minimumInterval) }
        XCTAssertEqual(field.accepted, 20)
        let rings = field.rings(atNanoseconds: Self.ns(19 * 0.2), life: 5)
        XCTAssertEqual(rings.count, BeatRingConfiguration.maximumRings, "never more than 16 live")
        XCTAssertEqual(rings.map(\.sequence), Array(4..<20), "the four oldest were dropped")
    }

    /// Accepted rings in the worst 1 s window when beats come every 50 ms for 2 s.
    private func worstPerSecond(_ envelope: FlashEnvelopeConfiguration) -> Int {
        let field = BeatRingField()
        var accepted: [Double] = []
        for i in 0..<40 {
            let t = Double(i) * 0.05
            if field.emit(atNanoseconds: Self.ns(t), minimumInterval: BeatRingConfiguration.minimumInterval(for: envelope)) {
                accepted.append(t)
            }
        }
        return accepted.map { (start: Double) -> Int in accepted.filter { $0 >= start && $0 < start + 1 - 1e-9 }.count }.max() ?? 0
    }

    func testReduceFlashingCapsTheRateAtThreePerSecond() {
        XCTAssertEqual(worstPerSecond(.forReduceFlashing(true)), 3)
        let normal = worstPerSecond(.forReduceFlashing(false))
        XCTAssertLessThanOrEqual(normal, 6)
        XCTAssertGreaterThan(normal, 3, "the reduced cap applies only under a rise-limited envelope")
        // A stricter ACC-012 profile (a rise limit) takes the reduced interval too.
        let strict = FlashEnvelopeConfiguration(transitionBudget: 2, riseRatePerSecond: 0.1)
        XCTAssertEqual(BeatRingConfiguration.minimumInterval(for: strict), BeatRingConfiguration.reducedInterval)
    }

    func testOutOfOrderEmissionsAreIgnoredAndResetClears() {
        let field = BeatRingField()
        XCTAssertTrue(field.emit(atNanoseconds: Self.ns(5), minimumInterval: 0))
        XCTAssertFalse(field.emit(atNanoseconds: Self.ns(4), minimumInterval: 0), "earlier than the newest birth")
        XCTAssertFalse(field.emit(atNanoseconds: Self.ns(5.1), minimumInterval: 1.0 / 6), "inside the rate cap")
        XCTAssertEqual(field.rings(atNanoseconds: Self.ns(4.5), life: life).count, 0, "not born yet")
        field.reset()
        XCTAssertEqual(field.storedCount, 0)
        XCTAssertNil(field.newestBirth)
        XCTAssertTrue(field.emit(atNanoseconds: Self.ns(1), minimumInterval: 1))
    }

    func testReplayIsIdentical() {
        let a = fourBeats(), b = fourBeats()
        for t in stride(from: 10.0, to: 13.0, by: 0.1) {
            XCTAssertEqual(a.rings(atNanoseconds: Self.ns(t), life: life), b.rings(atNanoseconds: Self.ns(t), life: life))
        }
    }

    func testConfigurationClamps() {
        let c = BeatRingConfiguration(life: .nan, lineThickness: 9)
        XCTAssertEqual(c.life, BeatRingConfiguration.defaultLife)
        XCTAssertEqual(c.lineThickness, BeatRingConfiguration.thicknessRange.upperBound)
        XCTAssertEqual(BeatRingConfiguration(life: 0.1).life, 0.5)
    }
}
