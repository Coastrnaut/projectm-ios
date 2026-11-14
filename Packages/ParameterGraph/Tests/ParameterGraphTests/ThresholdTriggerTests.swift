// ThresholdTriggerTests.swift — MOD-006-T02, T04, T05 (specs/148-mod-006-threshold-trigger, contract T1-T3).
//
// * The roadmap acceptance, "Noise around threshold produces no trigger storm": 10 s of seeded noise at 60 fps
//   around the fire level, the re-arm level and their midpoint gives at most one trigger (MOD-006-S1).
// * Pulse trains fire once per pulse and never closer than the minimum interval, at 60 fps, 120 fps and with
//   seeded jitter (S2). Hold, equality edges, non-finite input, clock anomalies, validation, determinism (S3).
// * The bank: features from `AudioFeatureFrame`, fire order, limit, atomic replacement.
// Deterministic: a local SplitMix64, injected frame times; no wall clock.
import XCTest
@testable import ParameterGraph

/// TriggerNoise (SplitMix64): a small deterministic generator.
private struct TriggerNoise {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in −1…1.
    mutating func signed() -> Double { Double(next() >> 11) / Double(1 << 52) - 1 }
}

final class ThresholdTriggerTests: XCTestCase {
    private static let ms: UInt64 = 1_000_000
    private static let start: UInt64 = 1_000_000_000

    private static func settings(high: Double = 0.6, low: Double = 0.4, interval: Double = 0.1,
                                 hold: Double = 0) -> ThresholdTriggerSettings {
        ThresholdTriggerSettings(high: high, low: low, minimumIntervalSeconds: interval, holdSeconds: hold)
    }

    /// Frame times: `count` frames of `duration` ns, or seeded jitter of 4…40 ms when `jitterSeed` is set.
    private static func frameTimes(seconds: Double, frameNanoseconds: UInt64, jitterSeed: UInt64? = nil) -> [UInt64] {
        var times: [UInt64] = []
        var t: UInt64 = start
        var random = TriggerNoise(state: jitterSeed ?? 0)
        let end: UInt64 = start + UInt64(seconds * 1e9)
        while t < end {
            times.append(t)
            if jitterSeed != nil {
                let jitter: Double = (random.signed() + 1) / 2   // 0…1
                t += 4 * ms + UInt64(jitter * 36e6)
            } else {
                t += frameNanoseconds
            }
        }
        return times
    }

    /// Runs `input(t)` at `times`; returns the fire times.
    private static func run(_ settings: ThresholdTriggerSettings, times: [UInt64],
                            input: (UInt64) -> Double) throws -> [UInt64] {
        var trigger = try ThresholdTrigger(settings: settings)
        var fires: [UInt64] = []
        for t in times where trigger.step(value: input(t), timeNanoseconds: t) { fires.append(t) }
        return fires
    }

    /// A pulse train: `level` for `width` ms every `period` ms starting at `start`, `rest` otherwise.
    private static func pulse(_ t: UInt64, period: UInt64, width: UInt64, level: Double = 0.9, rest: Double = 0.1) -> Double {
        let phase: UInt64 = ((t - start) / ms) % period
        return phase < width ? level : rest
    }

    // MARK: Acceptance (MOD-006-S1, S2)

    func testNoiseAroundThresholdProducesNoTriggerStorm() throws {
        let times: [UInt64] = Self.frameTimes(seconds: 10, frameNanoseconds: 16_666_667)
        XCTAssertEqual(times.count, 600)
        // Width 0.2: ±0.19 around either level, ±0.09 around the midpoint (never crossing both levels).
        let cases: [(centre: Double, amplitude: Double)] = [(0.6, 0.19), (0.4, 0.19), (0.5, 0.09)]
        for (index, noise) in cases.enumerated() {
            for (interval, hold) in [(0.1, 0.0), (0.0, 0.0), (0.0, 0.05)] {
                var random = TriggerNoise(state: 0x6006 + UInt64(index))
                let fires: [UInt64] = try Self.run(Self.settings(interval: interval, hold: hold), times: times) { (_: UInt64) -> Double in
                    noise.centre + noise.amplitude * random.signed()
                }
                XCTAssertLessThanOrEqual(fires.count, 1, "centre \(noise.centre) ±\(noise.amplitude), interval \(interval), hold \(hold)")
            }
        }
        // Control: the same noise with no hysteresis gap would storm, so the test can fail.
        var random = TriggerNoise(state: 0x6006)
        let storm: [UInt64] = try Self.run(Self.settings(high: 0.6, low: 0.599, interval: 0), times: times) { (_: UInt64) -> Double in
            0.6 + 0.19 * random.signed()
        }
        XCTAssertGreaterThan(storm.count, 50, "without hysteresis the same noise fires many times")
    }

    func testCleanPulseTrainFiresOncePerPulse() throws {
        let times: [UInt64] = Self.frameTimes(seconds: 3, frameNanoseconds: 16_666_667)
        let fires: [UInt64] = try Self.run(Self.settings(), times: times) { (t: UInt64) -> Double in
            Self.pulse(t, period: 300, width: 50)
        }
        XCTAssertEqual(fires.count, 10)
        for (k, fire) in fires.enumerated() {
            // The first frame at or after the pulse start.
            let pulseStart: UInt64 = Self.start + UInt64(k) * 300 * Self.ms
            let first: UInt64? = times.first { (t: UInt64) -> Bool in t >= pulseStart }
            XCTAssertEqual(fire, first, "pulse \(k) fires on its first frame above high")
        }
    }

    // MARK: Frame rates, hold, edges (MOD-006-S2, S3)

    func testMinimumIntervalAt60And120FpsAndJitter() throws {
        let patterns: [[UInt64]] = [
            Self.frameTimes(seconds: 3, frameNanoseconds: 16_666_667),
            Self.frameTimes(seconds: 3, frameNanoseconds: 8_333_333),
            Self.frameTimes(seconds: 3, frameNanoseconds: 0, jitterSeed: 0x1234),
        ]
        var counts: [Int] = []
        for times in patterns {
            // Pulses every 80 ms (40 ms wide), interval 100 ms: gaps never below the interval.
            let fast: [UInt64] = try Self.run(Self.settings(), times: times) { (t: UInt64) -> Double in
                Self.pulse(t, period: 80, width: 40)
            }
            XCTAssertGreaterThan(fast.count, 5)
            for (a, b) in zip(fast, fast.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 100 * Self.ms) }
            // Pulses every 300 ms: one per pulse at every rate.
            let slow: [UInt64] = try Self.run(Self.settings(), times: times) { (t: UInt64) -> Double in
                Self.pulse(t, period: 300, width: 60)
            }
            counts.append(slow.count)
        }
        XCTAssertEqual(counts, [10, 10, 10])
    }

    func testHoldRequiresContinuousTimeAboveHigh() throws {
        let times: [UInt64] = Self.frameTimes(seconds: 1, frameNanoseconds: 8_333_333)
        let hold = Self.settings(hold: 0.05)
        let short: [UInt64] = try Self.run(hold, times: times) { (t: UInt64) -> Double in t - Self.start < 30 * Self.ms ? 0.9 : 0.1 }
        XCTAssertEqual(short.count, 0, "30 ms above high is shorter than the 50 ms hold")
        let long: [UInt64] = try Self.run(hold, times: times) { (t: UInt64) -> Double in t - Self.start < 70 * Self.ms ? 0.9 : 0.1 }
        XCTAssertEqual(long.count, 1)
        XCTAssertGreaterThanOrEqual(long[0] - Self.start, 50 * Self.ms)
        // A NaN in the middle restarts the hold: 40 ms + NaN + 40 ms never reaches 50 ms continuously.
        let broken: [UInt64] = try Self.run(hold, times: times) { (t: UInt64) -> Double in
            let ms: UInt64 = (t - Self.start) / Self.ms
            if ms < 40 || (ms >= 50 && ms < 90) { return 0.9 }
            return ms < 50 ? .nan : 0.1
        }
        XCTAssertEqual(broken.count, 0)
    }

    func testEdgeInputs() throws {
        var trigger = try ThresholdTrigger(settings: Self.settings(interval: 0))
        var t: UInt64 = Self.start
        func step(_ v: Double) -> Bool {
            t += 10 * Self.ms
            return trigger.step(value: v, timeNanoseconds: t)
        }
        XCTAssertFalse(step(0.6), "equal to high does not fire")
        XCTAssertTrue(step(0.61), "a new trigger is armed")
        XCTAssertFalse(step(0.4), "equal to low does not re-arm")
        XCTAssertFalse(step(0.9))
        XCTAssertFalse(step(.nan), "NaN does not re-arm")
        XCTAssertFalse(step(-.infinity), "−∞ does not re-arm")
        XCTAssertFalse(step(0.9))
        XCTAssertFalse(step(0.39), "re-arms")
        XCTAssertFalse(step(.infinity), "+∞ does not fire")
        XCTAssertFalse(step(.nan))
        XCTAssertTrue(step(0.7))

        // Repeated and backwards times count as no elapsed time for the interval.
        var timed = try ThresholdTrigger(settings: Self.settings(interval: 0.1))
        XCTAssertTrue(timed.step(value: 0.9, timeNanoseconds: Self.start + 100 * Self.ms))
        XCTAssertFalse(timed.step(value: 0.1, timeNanoseconds: Self.start + 150 * Self.ms))
        XCTAssertFalse(timed.step(value: 0.9, timeNanoseconds: Self.start), "backwards: still inside the interval; consumed")
        XCTAssertFalse(timed.step(value: 0.1, timeNanoseconds: Self.start + 150 * Self.ms))
        XCTAssertFalse(timed.step(value: 0.9, timeNanoseconds: Self.start + 150 * Self.ms), "repeated time: 50 ms < interval")
        XCTAssertFalse(timed.step(value: 0.1, timeNanoseconds: Self.start + 210 * Self.ms))
        XCTAssertTrue(timed.step(value: 0.9, timeNanoseconds: Self.start + 210 * Self.ms), "110 ms after the fire")

        // Validation (MOD-006-R7).
        let invalid: [ThresholdTriggerSettings] = [
            Self.settings(high: 0.4, low: 0.4), Self.settings(high: 0.3, low: 0.4), Self.settings(high: .nan),
            Self.settings(high: 1.5), Self.settings(low: -0.1), Self.settings(interval: -1), Self.settings(interval: 61),
            Self.settings(hold: .infinity),
        ]
        for settings in invalid {
            XCTAssertNotNil(settings.validationProblem, "\(settings)")
            XCTAssertThrowsError(try ThresholdTrigger(settings: settings))
        }
        XCTAssertNil(Self.settings(high: 1, low: 0, interval: 60, hold: 60).validationProblem)
        XCTAssertEqual(ThresholdTriggerSettings(high: 0.6, low: 0.4).minimumIntervalSeconds, 0.1, "default interval 100 ms")
        XCTAssertEqual(ThresholdTriggerSettings(high: 0.6, low: 0.4).holdSeconds, 0)
    }

    func testDeterministic() throws {
        let times: [UInt64] = Self.frameTimes(seconds: 5, frameNanoseconds: 0, jitterSeed: 0xBEEF)
        func once() throws -> [UInt64] {
            var random = TriggerNoise(state: 42)
            return try Self.run(Self.settings(hold: 0.02), times: times) { (t: UInt64) -> Double in
                Self.pulse(t, period: 170, width: 70) + 0.15 * random.signed()
            }
        }
        let first: [UInt64] = try once()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, try once())
    }

    // MARK: Bank (contract T3)

    private func advance(_ bank: ThresholdTriggerBank, bands: [Float], kick: Float?, at t: UInt64) -> [ThresholdTriggerAction] {
        var fired: [ThresholdTriggerAction] = []
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            bank.advance(frame: AudioFeatureFrame(bands: buffer, kick: kick), timeNanoseconds: t) { (action: ThresholdTriggerAction) -> Void in
                fired.append(action)
            }
        }
        return fired
    }

    func testBankReadsFeaturesAndFiresInOrder() throws {
        let bank = ThresholdTriggerBank()
        XCTAssertFalse(bank.hasTriggers)
        try bank.set([
            ThresholdTriggerBinding(source: .band(1), action: .blackout, settings: Self.settings()),
            ThresholdTriggerBinding(source: .kick, action: .cueNext, settings: Self.settings()),
        ])
        XCTAssertTrue(bank.hasTriggers)
        XCTAssertEqual(advance(bank, bands: [0, 0.9], kick: 0.9, at: Self.start), [.blackout, .cueNext])
        XCTAssertEqual(advance(bank, bands: [0, 0.9], kick: 0.1, at: Self.start + 200 * Self.ms), [])
        XCTAssertEqual(advance(bank, bands: [0, 0.1], kick: 0.9, at: Self.start + 400 * Self.ms), [.cueNext])
        XCTAssertEqual(advance(bank, bands: [0, 0.9], kick: nil, at: Self.start + 600 * Self.ms), [.blackout], "a missing kick reads 0")
        XCTAssertEqual(ThresholdTriggerAction.allCases.map(\.rawValue), ["cue.next", "cue.previous", "blackout"])
    }

    func testBankLimitAndAtomicReplacement() throws {
        let bank = ThresholdTriggerBank()
        let one = ThresholdTriggerBinding(source: .kick, action: .cueNext, settings: Self.settings())
        try bank.set(Array(repeating: one, count: ThresholdTriggerBank.maximumTriggers))
        XCTAssertEqual(ThresholdTriggerBank.maximumTriggers, 8)
        XCTAssertThrowsError(try bank.set(Array(repeating: one, count: 9)))
        let bad = ThresholdTriggerBinding(source: .kick, action: .cueNext, settings: Self.settings(high: 0.2, low: 0.4))
        XCTAssertThrowsError(try bank.set([one, bad]))
        XCTAssertEqual(bank.bindings.count, 8, "a refused set leaves the bank unchanged")
        try bank.set([])
        XCTAssertFalse(bank.hasTriggers)
    }
}
