// MotionTrackerTests.swift — CAM-011-T04, T09 (CAM-011-R1 to R7, S1, S2, S5; contract motion-sources M1 to M6).
// The roadmap acceptance: "Synthetic motion stream produces bounded normalized values". A seeded synthetic stream of
// sweeps far beyond the range, spikes, NaN/±∞, rapid shakes, yaw seam crossings and irregular sample times keeps every
// output finite and within 0…1; calibration gives 0.5; the seam never makes the yaw output jump. Deterministic: sample
// times are injected, no wall clock.
import Foundation
import ParameterGraph
import XCTest

final class MotionTrackerTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667   // 60 Hz
    private static let origin: UInt64 = 1_000_000_000

    private static func sample(_ pitch: Double, _ roll: Double = 0, _ yaw: Double = 0, accel: Double = 0,
                               at index: Int) -> MotionSample {
        MotionSample(pitch: pitch, roll: roll, yaw: yaw, accelerationX: accel, timeNanoseconds: origin + UInt64(index) * frame)
    }

    private static func wrapped(_ angle: Double) -> Double { remainder(angle, 2 * Double.pi) }

    private func assertBounded(_ values: MotionFeatureValues, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for axis in MotionAxis.allCases {
            let raw: Double
            switch axis {
            case .pitch: raw = values.pitch
            case .roll: raw = values.roll
            case .yaw: raw = values.yaw
            case .shake: raw = values.shake
            }
            XCTAssertTrue(raw.isFinite && raw >= 0 && raw <= 1, "\(axis) = \(raw) at \(message)", file: file, line: line)
        }
    }

    // MARK: Acceptance (S1)

    /// A tiny deterministic generator (no Foundation randomness), so the stream is the same on every host.
    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    func testSyntheticMotionStreamProducesBoundedNormalizedValues() {
        let tracker = MotionTracker()
        var random = LCG(state: 0xCA11)
        let specials: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, .greatestFiniteMagnitude]
        var time: UInt64 = Self.origin
        var checked = 0
        for index in 0..<2_000 {
            let phase = Double(index) / 60
            var pitch: Double = 4 * sin(phase * 3)                 // sweeps far beyond ±90°
            var roll: Double = Self.wrapped(phase * 7)              // spins through the seam
            var yaw: Double = Self.wrapped(-phase * 11)             // the other way
            var accel: Double = index % 7 == 0 ? 6 * random.next() : 0.05 * random.next()   // rapid shakes
            if random.next() < 0.1 { pitch = specials[Int(random.next() * Double(specials.count)) % specials.count] }
            if random.next() < 0.1 { roll = specials[Int(random.next() * Double(specials.count)) % specials.count] }
            if random.next() < 0.1 { yaw = specials[Int(random.next() * Double(specials.count)) % specials.count] }
            if random.next() < 0.1 { accel = specials[Int(random.next() * Double(specials.count)) % specials.count] }
            let step: Double = random.next()   // irregular times: still, backwards, normal, long gaps
            if step < 0.05 { time -= min(time, Self.frame * 3) } else if step < 0.1 { } else if step < 0.15 {
                time += 2_000_000_000
            } else { time += Self.frame }
            tracker.ingest(MotionSample(pitch: pitch, roll: roll, yaw: yaw, accelerationX: accel, accelerationY: -accel,
                                        accelerationZ: accel, timeNanoseconds: time))
            if index == 500 { tracker.calibrate() }
            if index == 900 { tracker.range = .narrow }
            if index == 1_300 { tracker.restart() }
            if index == 1_600 { tracker.range = .wide }
            assertBounded(tracker.values, "sample \(index)")
            let frame = AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0), motion: tracker.values)
            for axis in MotionAxis.allCases {
                let value: Double = AudioFeatureSource.motion(axis).value(in: frame)
                XCTAssertTrue(value.isFinite && value >= 0 && value <= 1)
                checked += 1
            }
        }
        XCTAssertEqual(checked, 8_000)
    }

    // MARK: Normalization, calibration (S2, R3, R5)

    func testRangeEndpointsMapToZeroHalfAndOne() {
        let cases: [(degrees: Double, range: MotionRange, expected: Double)] = [
            (0, .medium, 0.5), (45, .medium, 1), (-45, .medium, 0), (22.5, .medium, 0.75), (60, .medium, 1),
            (10, .narrow, 0.75), (-90, .wide, 0), (45, .wide, 0.75),
        ]
        for c in cases {
            let tracker = MotionTracker(range: c.range)
            tracker.ingest(Self.sample(c.degrees * Double.pi / 180, at: 0))   // the first sample snaps
            XCTAssertEqual(tracker.values.pitch, c.expected, accuracy: 1e-12, "\(c)")
            XCTAssertEqual(tracker.values.roll, 0.5, accuracy: 1e-12)
        }
        XCTAssertEqual(MotionRange.allCases.map(\.degrees), [20, 45, 90])
        XCTAssertEqual(MotionRange(stored: nil), .medium)
        XCTAssertEqual(MotionRange(stored: "huge"), .medium)
        XCTAssertEqual(MotionRange(stored: "wide"), .wide)
    }

    func testCalibrationMakesTheCurrentAttitudeNeutral() {
        let tracker = MotionTracker()
        for index in 0..<30 { tracker.ingest(Self.sample(0.4, -0.3, 2.0, at: index)) }
        XCTAssertGreaterThan(tracker.values.pitch, 0.7)
        XCTAssertLessThan(tracker.values.roll, 0.35)
        XCTAssertEqual(tracker.values.yaw, 0.5, accuracy: 1e-9, "uncalibrated yaw is relative to the first sample")
        tracker.calibrate()
        XCTAssertEqual(tracker.values, MotionFeatureValues(pitch: 0.5, roll: 0.5, yaw: 0.5, shake: tracker.values.shake))
        for index in 30..<90 {
            tracker.ingest(Self.sample(0.4, -0.3, 2.0, at: index))
            XCTAssertEqual(tracker.values.pitch, 0.5, accuracy: 1e-3)
            XCTAssertEqual(tracker.values.roll, 0.5, accuracy: 1e-3)
            XCTAssertEqual(tracker.values.yaw, 0.5, accuracy: 1e-3)
        }
        let quarter: Double = MotionRange.medium.radians / 2   // tilt a quarter range further: settles at 0.75
        for index in 90..<150 { tracker.ingest(Self.sample(0.4 + quarter, -0.3, 2.0, at: index)) }
        XCTAssertEqual(tracker.values.pitch, 0.75, accuracy: 1e-3)
    }

    // MARK: Seam and unwrapping (R4)

    func testYawSeamCrossingNeverJumps() {
        for neutral in [0.0, Double.pi - 0.05, -Double.pi + 0.2] {
            let tracker = MotionTracker(range: .wide)
            var yaw = neutral
            tracker.ingest(Self.sample(0, 0, Self.wrapped(neutral), at: 0))   // the first sample sets the yaw neutral
            var previous: Double? = tracker.values.yaw
            for index in 1...300 {   // 3/4 turn forward (through the sensor's ±π seam for every neutral), then back
                yaw += index <= 150 ? 0.0314 : -0.0314
                tracker.ingest(Self.sample(0, 0, Self.wrapped(yaw), at: index))
                if let previous {
                    XCTAssertLessThan(abs(tracker.values.yaw - previous), 0.01, "neutral \(neutral), sample \(index)")
                }
                previous = tracker.values.yaw
            }
            for index in 301..<330 { tracker.ingest(Self.sample(0, 0, Self.wrapped(yaw), at: index)) }   // settle
            XCTAssertEqual(tracker.values.yaw, 0.5, accuracy: 1e-3, "back at neutral reads the middle again")
        }
    }

    func testOffsetIsLimitedToOneTurn() {
        let tracker = MotionTracker(range: .medium)
        var yaw = 0.0
        var index = 0
        for _ in 0..<1_000 { yaw += 0.05; tracker.ingest(Self.sample(0, 0, Self.wrapped(yaw), at: index)); index += 1 }   // ~8 turns
        XCTAssertEqual(tracker.values.yaw, 1, accuracy: 1e-9)
        for _ in 0..<Int((2 * Double.pi / 0.05).rounded()) {   // one turn back
            yaw -= 0.05
            tracker.ingest(Self.sample(0, 0, Self.wrapped(yaw), at: index))
            index += 1
        }
        for _ in 0..<60 { tracker.ingest(Self.sample(0, 0, Self.wrapped(yaw), at: index)); index += 1 }
        XCTAssertEqual(tracker.values.yaw, 0.5, accuracy: 0.05, "one turn back returns near the middle")
    }

    func testRestartReanchorsYawKeepsPitchNeutralAndSnaps() {
        let tracker = MotionTracker()
        for index in 0..<10 { tracker.ingest(Self.sample(0.2, 0, 1.0, at: index)) }
        tracker.calibrate()
        tracker.restart()
        XCTAssertFalse(tracker.hasSamples)
        XCTAssertEqual(tracker.values.pitch, 0.5, "held until the next sample")
        let quarter: Double = MotionRange.medium.radians / 2
        tracker.ingest(Self.sample(0.2 + quarter, 0, -2.5, at: 0))   // a new yaw reference after the restart
        XCTAssertTrue(tracker.hasSamples)
        XCTAssertEqual(tracker.values.pitch, 0.75, accuracy: 1e-12, "the pitch neutral is kept; the first sample snaps")
        XCTAssertEqual(tracker.values.yaw, 0.5, accuracy: 1e-12, "the yaw neutral is taken from the first new sample")
    }

    func testNonFiniteComponentsHoldTheLastValue() {
        let tracker = MotionTracker()
        tracker.ingest(Self.sample(0.3, 0, 0, at: 0))
        let before = tracker.values
        tracker.ingest(MotionSample(pitch: .nan, roll: .infinity, yaw: -.infinity, accelerationX: .nan,
                                    timeNanoseconds: Self.origin))   // time standing still: no step
        XCTAssertEqual(tracker.values, before)
        XCTAssertEqual(MotionFeatureValues(pitch: .nan, roll: 2, yaw: -1, shake: .infinity).value(.pitch), 0.5)
        XCTAssertEqual(MotionFeatureValues(pitch: .nan, roll: 2, yaw: -1, shake: .infinity).value(.roll), 1)
        XCTAssertEqual(MotionFeatureValues(pitch: .nan, roll: 2, yaw: -1, shake: .infinity).value(.yaw), 0)
        XCTAssertEqual(MotionFeatureValues(pitch: .nan, roll: 2, yaw: -1, shake: .infinity).value(.shake), 0)
    }

    // MARK: Shake (US2, R6)

    func testShakeRisesQuicklyAndFallsBack() {
        let tracker = MotionTracker()
        for index in 0..<30 { tracker.ingest(Self.sample(0, accel: 0.001, at: index)) }
        XCTAssertLessThan(tracker.values.shake, 0.01, "still reads about 0")
        tracker.ingest(Self.sample(0, accel: 3, at: 30))   // a hard shake: 3 g → full scale
        let attack: Double = 1 - exp(-Double(Self.frame) / 1e9 / MotionTracker.shakeEnvelope.attackSeconds)
        let expected: Double = tracker.values.shake   // checked against the closed form below
        XCTAssertGreaterThan(expected, 0.5)
        XCTAssertLessThanOrEqual(expected, 1)
        XCTAssertEqual(expected, 0.0005 + (1 - 0.0005) * attack, accuracy: 0.01)
        for index in 31..<36 { tracker.ingest(Self.sample(0, accel: index % 2 == 0 ? 4 : -4, at: index)) }   // rapid shakes
        XCTAssertGreaterThan(tracker.values.shake, 0.95)
        XCTAssertLessThanOrEqual(tracker.values.shake, 1)
        for index in 36..<96 { tracker.ingest(Self.sample(0, at: index)) }   // 1 s still
        XCTAssertLessThan(tracker.values.shake, 0.05, "falls back within about a second")
    }

    func testThresholdTriggerAcceptsShake() throws {
        let bank = ThresholdTriggerBank()
        let settings = ThresholdTriggerSettings(high: 0.6, low: 0.4, minimumIntervalSeconds: 0.1, holdSeconds: 0)
        try bank.set([ThresholdTriggerBinding(source: .motion(.shake), action: .cueNext, settings: settings)])
        var fired: [ThresholdTriggerAction] = []
        for (i, shake) in [0.0, 0.9].enumerated() {
            let frame = AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0),
                                          motion: MotionFeatureValues(pitch: 0.5, roll: 0.5, yaw: 0.5, shake: shake))
            bank.advance(frame: frame, timeNanoseconds: Self.origin + UInt64(i) * 200_000_000) { (action: ThresholdTriggerAction) -> Void in
                fired.append(action)
            }
        }
        XCTAssertEqual(fired, [.cueNext])
    }

    // MARK: Sources (R1, M1, M2)

    func testMotionSourceIDsRoundTrip() {
        for axis in MotionAxis.allCases {
            let source = AudioFeatureSource.motion(axis)
            XCTAssertEqual(source.id, "audio.motion." + axis.rawValue)
            XCTAssertEqual(AudioFeatureSource(id: source.id), source)
        }
        for bad in ["audio.motion.", "audio.motion.Pitch", "audio.motion.pitch.0", "motion.pitch", "audio.motionpitch"] {
            XCTAssertNil(AudioFeatureSource(id: bad), bad)
        }
        let silent = AudioFeatureFrame.silent
        XCTAssertEqual(AudioFeatureSource.motion(.pitch).value(in: silent), 0.5, "no motion fed reads the middle")
        XCTAssertEqual(AudioFeatureSource.motion(.shake).value(in: silent), 0)
    }
}
