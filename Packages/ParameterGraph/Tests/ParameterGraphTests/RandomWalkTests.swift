// RandomWalkTests.swift — MOD-016-T03, T05, T06, T07: the seeded random walk oscillator (MOD-016-R1 to R8;
// specs/253-mod-016-random-walk, research MOD-016-D1 to D3, contract W1 to W7).
//
// The acceptance ("Seeded timeline reproduces identical values and never leaves bounds"): banks with the same
// settings, seed and origin, driven at 60 Hz, 120 Hz and with jittery frame times, give exactly the same value (==) at
// every shared time and the same value as a direct seek; a different seed differs; every value over dense sweeps and
// spot sweeps through ten hours stays finite and inside clamp(centre ± depth/2, 0, 1), and between two targets the
// walk never goes beyond either. Frame times are integer nanoseconds passed in; no clock, no sleep.
import ParameterGraph
import XCTest

final class RandomWalkTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000
    private static let origin: UInt64 = 5 * second
    private static let frame60: UInt64 = 16_666_666
    private static let frame120: UInt64 = 8_333_333

    /// Frame times from the origin to `origin + duration` with gaps from `gap(index)`.
    private static func frames(duration: UInt64, gap: (Int) -> UInt64) -> [UInt64] {
        var times: [UInt64] = []
        var t: UInt64 = origin
        var index = 0
        while t <= origin + duration {
            times.append(t)
            t += gap(index)
            index += 1
        }
        return times
    }

    /// Deterministic irregular gaps of 1…40 ms (a fixed linear congruential sequence).
    private static func jitteryGaps() -> (Int) -> UInt64 {
        var state: UInt64 = 0x0BAD_5EED
        return { (_: Int) -> UInt64 in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return 1_000_000 + (state >> 33) % 39_000_000
        }
    }

    /// Slot `slot` of a fresh bank holding `lfos`, sampled at every frame time.
    private static func run(_ lfos: [LFO?], times: [UInt64], slot: Int = 0, tempo: (UInt64) -> Double? = { _ in nil },
                            cap: Double = .infinity) throws -> [Double] {
        let bank = LFOBank()
        try bank.set(lfos)
        var out: [Double] = Array(repeating: -1, count: LFOBank.maximumOscillators)
        var values: [Double] = []
        values.reserveCapacity(times.count)
        for t in times {
            out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Void in
                bank.values(atNanoseconds: t, tempoBPM: tempo(t), maximumRateHz: cap, into: buffer)
            }
            values.append(out[slot])
        }
        return values
    }

    /// The bounds of contract W4: clamp(centre ± depth/2, 0, 1).
    private static func bounds(_ lfo: LFO) -> (low: Double, high: Double) {
        (min(max(lfo.center - lfo.amplitude / 2, 0), 1), min(max(lfo.center + lfo.amplitude / 2, 0), 1))
    }

    // MARK: Acceptance: reproducible (MOD-016-S1)

    func testSameSeedAndTimebaseReproduceIdenticalValues() throws {
        let lfo = try LFO(shape: .randomWalk, rateHz: 5.3, phaseOffset: 0.3, seed: 160_016)
        let duration: UInt64 = 20 * Self.second   // 106 cycles
        let at60 = Self.frames(duration: duration) { (_: Int) -> UInt64 in Self.frame60 }
        let at120 = Self.frames(duration: duration) { (_: Int) -> UInt64 in Self.frame120 }
        let jittery = Self.frames(duration: duration, gap: Self.jitteryGaps())
        let a = try Self.run([lfo], times: at60)
        let b = try Self.run([lfo], times: at120)
        let c = try Self.run([lfo], times: jittery)
        var shared = 0
        for (index, t) in at60.enumerated() {
            XCTAssertEqual(at120[2 * index], t)
            XCTAssertEqual(a[index], b[2 * index], "60 Hz and 120 Hz agree exactly at \(t - Self.origin) ns")
            shared += 1
        }
        XCTAssertGreaterThanOrEqual(shared, 1_200)
        for (t, v) in zip(jittery, c) {
            XCTAssertEqual(v, lfo.value(elapsedNanoseconds: t - Self.origin), "jittery frames equal a direct seek")
        }
        for (t, v) in zip(at60, a) {
            let cycle: LFOCycle = lfo.cycle(elapsedNanoseconds: t - Self.origin, rateHz: lfo.rateHz)
            let from: Double = SteppedRandom.level(seed: 160_016, step: cycle.step)
            let to: Double = SteppedRandom.level(seed: 160_016, step: cycle.step + 1)
            let walk: Double = from + (to - from) * RandomWalk.ease(cycle.phase, smoothness: 1)
            XCTAssertEqual(v, 0.5 + (walk - 0.5), accuracy: 1e-15, "the contract W2 value at \(t - Self.origin) ns")
        }
        XCTAssertGreaterThan(Set(a).count, 1_000, "the walk moves")

        // A seek far along the timeline equals a run that played up to it.
        let late: UInt64 = Self.origin + 3_600 * Self.second + 123_456_789
        let seek = try Self.run([lfo], times: [Self.origin, late])
        XCTAssertEqual(seek[1], lfo.value(elapsedNanoseconds: late - Self.origin))

        let other = try LFO(shape: .randomWalk, rateHz: 5.3, phaseOffset: 0.3, seed: 160_017)
        let d = try Self.run([other], times: at60)
        let differing: Int = zip(a, d).filter { (pair: (Double, Double)) -> Bool in pair.0 != pair.1 }.count
        XCTAssertGreaterThan(differing, at60.count * 9 / 10, "a different seed gives a different motion")
    }

    func testUnseededSlotsDifferAndRepeat() throws {
        let lfo = try LFO(shape: .randomWalk, rateHz: 3)
        let times = Self.frames(duration: 4 * Self.second) { (_: Int) -> UInt64 in Self.frame60 }
        let slot0 = try Self.run([lfo, lfo], times: times, slot: 0)
        let slot1 = try Self.run([lfo, lfo], times: times, slot: 1)
        XCTAssertNotEqual(slot0, slot1, "two unseeded walks do not move in lockstep")
        XCTAssertEqual(slot0, try Self.run([lfo, lfo], times: times, slot: 0), "and every playback repeats")
        let seeded = try LFO(shape: .randomWalk, rateHz: 3, seed: 8)
        XCTAssertEqual(try Self.run([seeded, seeded], times: times, slot: 0),
                       try Self.run([seeded, seeded], times: times, slot: 1), "a stored seed is the same in every slot")
    }

    func testEachCycleStartReadsItsTargetExactly() throws {
        let lfo = try LFO(shape: .randomWalk, rateHz: 2, seed: 99)
        for n in [Int64(0), 1, 2, 7, 7_200, 72_000] {   // 72 000 cycles = 10 h at 2 Hz
            let t = UInt64(n) * Self.second / 2
            let target: Double = SteppedRandom.level(seed: 99, step: n)
            XCTAssertEqual(lfo.value(elapsedNanoseconds: t), 0.5 + (target - 0.5), "cycle \(n) starts at its target")
            XCTAssertEqual(lfo.cycle(elapsedNanoseconds: t, rateHz: 2).step, n)
        }
    }

    // MARK: Acceptance: bounded (MOD-016-S2)

    func testEveryValueStaysInBoundsOverTenHours() throws {
        var checked = 0
        for center in [0.0, 0.5, 1.0] {
            for depth in [0.0, 0.3, 1.0] {
                for smoothness in [0.0, 0.5, 1.0] {
                    for rate in [0.01, 1.0, 20.0] {
                        let lfo = try LFO(shape: .randomWalk, rateHz: rate, phaseOffset: 0.7, amplitude: depth, center: center,
                                          seed: 4_242, smoothness: smoothness)
                        checked += try checkBounds(lfo)
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 600_000)
    }

    /// A dense 2-minute 60 Hz sweep plus a 1 s 60 Hz sweep at every hour through 10 h; returns the sample count.
    private func checkBounds(_ lfo: LFO) throws -> Int {
        let (low, high) = Self.bounds(lfo)
        var starts: [UInt64] = [0]
        for hour in 1...10 { starts.append(UInt64(hour) * 3_600 * Self.second - Self.second / 2) }
        var count = 0
        for start in starts {
            let frames: Int = start == 0 ? 7_200 : 60
            for index in 0..<frames {
                let t: UInt64 = start + UInt64(index) * Self.frame60
                let v: Double = lfo.value(elapsedNanoseconds: t)
                count += 1
                guard v.isFinite, v >= low, v <= high else {
                    XCTFail("\(v) leaves [\(low), \(high)] at \(t) ns for \(lfo)")
                    return count
                }
            }
        }
        if lfo.amplitude == 0 { XCTAssertEqual(lfo.value(elapsedNanoseconds: 12_345_678_901), min(max(lfo.center, 0), 1)) }
        return count
    }

    func testTheWalkNeverOvershootsItsTwoTargets() throws {
        for smoothness in [0.0, 0.25, 1.0] {
            let lfo = try LFO(shape: .randomWalk, rateHz: 1.7, seed: 31_337, smoothness: smoothness)
            for index in 0..<6_000 {   // 100 s at 60 Hz: 170 cycles
                let t = UInt64(index) * Self.frame60
                let cycle: LFOCycle = lfo.cycle(elapsedNanoseconds: t, rateHz: lfo.rateHz)
                let from: Double = SteppedRandom.level(seed: 31_337, step: cycle.step)
                let to: Double = SteppedRandom.level(seed: 31_337, step: cycle.step + 1)
                let v: Double = lfo.value(elapsedNanoseconds: t)
                let low: Double = 0.5 + (min(from, to) - 0.5)
                let high: Double = 0.5 + (max(from, to) - 0.5)
                XCTAssertTrue(v >= low && v <= high, "\(v) beyond the targets \(from), \(to) at \(t) ns")
            }
        }
    }

    // MARK: Continuity and the ease (MOD-016-R5, R6, S3)

    func testFrameToFrameChangeIsBounded() throws {
        for smoothness in [0.0, 0.6, 1.0] {
            let lfo = try LFO(shape: .randomWalk, rateHz: 4, phaseOffset: 0.2, amplitude: 0.8, center: 0.5, seed: 77,
                              smoothness: smoothness)
            let slope: Double = lfo.amplitude * RandomWalk.maximumSlope(smoothness: smoothness) * lfo.rateHz
            for gap in [Self.jitteryGaps(), { (_: Int) -> UInt64 in Self.frame60 }] {
                let times = Self.frames(duration: 30 * Self.second, gap: gap)   // 120 cycles, every boundary crossed
                let values = try Self.run([lfo], times: times)
                var largest = 0.0
                for i in 1..<times.count {
                    let dt = Double(times[i] - times[i - 1]) / 1e9
                    let change: Double = abs(values[i] - values[i - 1])
                    largest = max(largest, change / dt)
                    XCTAssertLessThanOrEqual(change, slope * dt + 1e-12, "no jump at frame \(i) (smoothness \(smoothness))")
                }
                XCTAssertGreaterThan(largest, slope * 0.3, "the bound is not vacuous")
            }
        }
    }

    func testEaseIsMonotoneFromZeroToOne() {
        for s in [0.0, 0.3, 1.0] {
            XCTAssertEqual(RandomWalk.ease(0, smoothness: s), 0)
            XCTAssertEqual(RandomWalk.ease(1, smoothness: s), 1)
            var previous = 0.0
            for i in 0...10_000 {
                let phi = Double(i) / 10_000
                let e: Double = RandomWalk.ease(phi, smoothness: s)
                XCTAssertGreaterThanOrEqual(e, previous, "monotone at \(phi)")
                XCTAssertLessThanOrEqual(e - previous, RandomWalk.maximumSlope(smoothness: s) / 10_000 + 1e-12)
                previous = e
            }
        }
        for phi in [0.1, 0.37, 0.9] { XCTAssertEqual(RandomWalk.ease(phi, smoothness: 0), phi, "smoothness 0 is linear") }
        let h = 1e-4
        XCTAssertLessThan(RandomWalk.ease(h, smoothness: 1) / h, 1e-6, "smoothness 1 starts with zero slope")
        XCTAssertLessThan((1 - RandomWalk.ease(1 - h, smoothness: 1)) / h, 1e-6, "and arrives with zero slope")
        XCTAssertEqual(RandomWalk.maximumSlope(smoothness: 0), 1)
        XCTAssertEqual(RandomWalk.maximumSlope(smoothness: 1), 1.875)
        XCTAssertEqual(RandomWalk.ease(.nan, smoothness: 1), 0, "a non-finite phase reads the start")
    }

    func testSmoothnessIsValidated() {
        for bad in [-0.1, 1.1, Double.nan, .infinity] {
            XCTAssertThrowsError(try LFO(shape: .randomWalk, rateHz: 1, smoothness: bad), "smoothness \(bad)")
            XCTAssertThrowsError(try LFO(shape: .sine, rateHz: 1, smoothness: bad), "validated for every shape")
        }
        XCTAssertNoThrow(try LFO(shape: .randomWalk, rateHz: 1, smoothness: 0))
        XCTAssertEqual(try LFO(shape: .randomWalk, rateHz: 1).smoothness, 1, "default 1")
        XCTAssertEqual(LFOShape(rawValue: "randomWalk"), .randomWalk)
        XCTAssertEqual(LFOShape.randomWalk.wave(0.3), 0, "the phase-only wave reads the centre")
    }

    // MARK: Tempo sync and Reduce flashing (MOD-016-R8, T07)

    func testSyncedWalkContinuesAcrossATempoChange() throws {
        let lfo = try LFO(shape: .randomWalk, rateHz: 0.5, sync: LFOSync(beatsPerCycle: 1), seed: 31)
        let times = Self.frames(duration: 6 * Self.second) { (_: Int) -> UInt64 in Self.frame60 }
        let change: UInt64 = Self.origin + 3 * Self.second + 100_000_000   // mid-cycle at 120 BPM
        let values = try Self.run([lfo], times: times) { (t: UInt64) -> Double? in t < change ? 120 : 90 }
        let switchTime: UInt64 = try XCTUnwrap(times.first { (t: UInt64) -> Bool in t >= change })
        let reached = Double(switchTime - Self.origin) / 1e9 * 2   // cycles at 2 Hz until the switch frame
        let slope: Double = RandomWalk.maximumSlope(smoothness: 1) * 2   // the larger rate
        for (i, t) in times.enumerated() {
            let cycles: Double = t < switchTime ? Double(t - Self.origin) / 1e9 * 2 : reached + Double(t - switchTime) / 1e9 * 1.5
            let step = Int64(cycles.rounded(.down))
            let phase: Double = cycles - cycles.rounded(.down)
            let from: Double = SteppedRandom.level(seed: 31, step: step)
            let to: Double = SteppedRandom.level(seed: 31, step: step + 1)
            let expected: Double = from + (to - from) * RandomWalk.ease(phase, smoothness: 1)
            XCTAssertEqual(values[i], expected, accuracy: 1e-9, "frame \(i): steps continue across 120 → 90 BPM")
            if i > 0 {
                let dt = Double(t - times[i - 1]) / 1e9
                XCTAssertLessThanOrEqual(abs(values[i] - values[i - 1]), slope * dt + 1e-12, "no jump at frame \(i)")
            }
        }
    }

    func testReduceFlashingCapsTheWalkAtThreeTargetsPerSecond() throws {
        let fast = try LFO(shape: .randomWalk, rateHz: 20, seed: 5)
        let three = try LFO(shape: .randomWalk, rateHz: 3, seed: 5)
        let times = Self.frames(duration: 2 * Self.second) { (_: Int) -> UInt64 in Self.frame60 }
        let capped = try Self.run([fast], times: times, cap: LFOBank.reduceFlashingMaximumRateHz)
        XCTAssertEqual(capped, try Self.run([three], times: times), "capped, it is the 3 Hz walk: 3 new targets per second")
        XCTAssertNotEqual(try Self.run([fast], times: times), capped, "uncapped it runs at 20 Hz")
    }
}
