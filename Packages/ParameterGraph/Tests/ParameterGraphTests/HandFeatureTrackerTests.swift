// HandFeatureTrackerTests.swift — CAM-010-T13 (CAM-010-R6 to R9, S2, S3; contract hand-sources H1, H2). The roadmap
// acceptance: "Recorded synthetic pose frames drive deterministic parameter changes."
// * Normalisation: an open hand, a pinch, a fist, mirroring, the picture's aspect, two hands, low confidence,
//   degenerate and non-finite joints: every value finite and within 0…1.
// * Determinism: a recorded fixture (joint positions over time) goes through the tracker (source smoothing) and a
//   binding (`AudioFeatureModulator`) to a test parameter. Two runs agree exactly; the values at sample times match the
//   closed-form one-pole; a jittered frame cadence gives the same values at the shared times.
// Deterministic: times are passed in; no clock, no sleep.
import Foundation
import ParameterGraph
import XCTest

/// A recorded pose sequence: each segment's frame holds from its start until the next segment.
struct RecordedHandPoses {
    let segments: [(startNanoseconds: UInt64, frame: HandPoseFrame?)]

    func frame(at time: UInt64) -> HandPoseFrame? {
        var current: HandPoseFrame?
        for segment in segments where segment.startNanoseconds <= time { current = segment.frame }
        return current
    }

    static func joint(_ x: Double, _ y: Double, _ confidence: Double = 0.9) -> HandJointPoint {
        HandJointPoint(x: x, y: y, confidence: confidence)
    }

    /// An open hand, wrist at (0.5, 0.3), palm 0.15 tall, thumb and index apart.
    static let openHand = HandObservationSample(
        wrist: joint(0.5, 0.3), thumbTip: joint(0.30, 0.45), indexTip: joint(0.45, 0.58), middleTip: joint(0.5, 0.59),
        ringTip: joint(0.55, 0.58), littleTip: joint(0.65, 0.52), middleKnuckle: joint(0.5, 0.45))

    /// The same hand pinching: thumb tip on index tip.
    static var pinchingHand: HandObservationSample {
        var hand = openHand
        hand.thumbTip = joint(0.47, 0.5)
        hand.indexTip = joint(0.47, 0.5)
        return hand
    }

    /// Open hand 0–0.5 s, pinch 0.5–1.0 s, no hand from 1.0 s.
    static let fixture = RecordedHandPoses(segments: [
        (0, HandPoseFrame(hands: [openHand])),
        (500_000_000, HandPoseFrame(hands: [pinchingHand])),
        (1_000_000_000, nil),
    ])
}

final class HandFeatureTrackerTests: XCTestCase {
    private static let target: ParameterID = "test.hand.target"
    private static let millisecond: UInt64 = 1_000_000

    private static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: target, displayName: "Target", group: ParameterGroup(id: "test.hand", displayName: "Hand"),
                                unit: .normalized, kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.25),
                                modulation: .continuousDefault),
        ])
    }

    // MARK: Normalisation (R6, R7, S3)

    func testOpenHandPinchAndFist() {
        let open: HandFeatureValues = HandFeatureNormalizer.measure(HandPoseFrame(hands: [RecordedHandPoses.openHand]), mirrored: false)
        XCTAssertEqual(open.present, 1)
        XCTAssertEqual(open.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(open.y, 0.3, accuracy: 1e-9)
        XCTAssertEqual(open.pinch, 0, "thumb and index apart")
        XCTAssertGreaterThan(open.open, 0.5, "a spread hand")
        XCTAssertEqual(open.size, 0.15 / 0.4, accuracy: 1e-9)
        XCTAssertEqual(open.second, 0)

        let pinch: HandFeatureValues = HandFeatureNormalizer.measure(HandPoseFrame(hands: [RecordedHandPoses.pinchingHand]), mirrored: true)
        XCTAssertEqual(pinch.pinch, 1, "touching tips")
        XCTAssertEqual(pinch.x, 0.5, accuracy: 1e-9)

        var fist = RecordedHandPoses.openHand
        for path in [\HandObservationSample.thumbTip, \.indexTip, \.middleTip, \.ringTip, \.littleTip] {
            fist[keyPath: path] = RecordedHandPoses.joint(0.5, 0.44)   // tips curled to just below the knuckle
        }
        XCTAssertEqual(HandFeatureNormalizer.measure(HandPoseFrame(hands: [fist]), mirrored: false).open, 0, "a fist")
    }

    func testMirroringAspectAndTwoHands() {
        var left = RecordedHandPoses.openHand
        left.wrist = RecordedHandPoses.joint(0.2, 0.3)
        left.middleKnuckle = RecordedHandPoses.joint(0.2, 0.35)   // a smaller (farther) hand
        var right = RecordedHandPoses.openHand
        right.wrist = RecordedHandPoses.joint(0.8, 0.6)
        right.middleKnuckle = RecordedHandPoses.joint(0.8, 0.8)
        let both: HandFeatureValues = HandFeatureNormalizer.measure(HandPoseFrame(hands: [left, right]), mirrored: true)
        XCTAssertEqual(both.second, 1)
        XCTAssertEqual(both.x, 0.2, accuracy: 1e-9, "the larger hand is first; mirrored x")
        XCTAssertEqual(both.secondX, 0.8, accuracy: 1e-9)
        XCTAssertEqual(both.secondY, 0.3, accuracy: 1e-9)

        var sideways = RecordedHandPoses.openHand   // a horizontal palm in a 0.5-aspect (portrait) picture
        sideways.middleKnuckle = RecordedHandPoses.joint(0.8, 0.3)
        let size: Double = HandFeatureNormalizer.measure(HandPoseFrame(hands: [sideways], aspect: 0.5), mirrored: false).size
        XCTAssertEqual(size, 0.15 / 0.4, accuracy: 1e-9, "0.3 picture widths at aspect 0.5 is 0.15 heights")
    }

    func testLowConfidenceDegenerateAndNonFiniteStayInRange() {
        var faint = RecordedHandPoses.openHand
        faint.thumbTip.confidence = 0.1
        faint.indexTip.confidence = 0.2
        XCTAssertEqual(HandFeatureNormalizer.measure(HandPoseFrame(hands: [faint]), mirrored: false), .neutral,
                       "5 confident joints: no hand")

        var flat = RecordedHandPoses.openHand
        flat.middleKnuckle = flat.wrist   // zero palm: pinch, open, size cannot be measured
        let degenerate: HandFeatureValues = HandFeatureNormalizer.measure(HandPoseFrame(hands: [flat]), mirrored: false)
        XCTAssertTrue(degenerate.pinch.isNaN && degenerate.open.isNaN && degenerate.size.isNaN)

        var broken = RecordedHandPoses.openHand
        broken.indexTip = HandJointPoint(x: .nan, y: .infinity, confidence: 0.9)
        broken.wrist = HandJointPoint(x: 7, y: -3, confidence: 0.9)
        let tracker = HandFeatureTracker()
        for (i, frame) in [HandPoseFrame(hands: [flat]), HandPoseFrame(hands: [broken], aspect: .nan),
                           HandPoseFrame(hands: [RecordedHandPoses.openHand]), HandPoseFrame(hands: [flat])].enumerated() {
            tracker.ingest(frame, mirrored: false, timeNanoseconds: UInt64(i) * 50 * Self.millisecond)
            for feature in HandFeature.allCases {
                let raw: Double = tracker.values.value(feature)
                XCTAssertTrue(raw.isFinite && raw >= 0 && raw <= 1, "\(feature) at frame \(i): \(raw)")
            }
        }
        XCTAssertEqual(AudioFeatureSource(id: "audio.hand.pinch"), .hand(.pinch))
        XCTAssertEqual(AudioFeatureSource.hand(.secondY).id, "audio.hand.secondY")
        XCTAssertNil(AudioFeatureSource(id: "audio.hand.wave"))
        let empty: [Float] = []
        empty.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            XCTAssertEqual(AudioFeatureSource.hand(.x).value(in: AudioFeatureFrame(bands: b)), 0.5, "no hand fed: neutral")
        }
    }

    // MARK: Recorded poses → smoothing → binding (R9, S2: the roadmap acceptance)

    /// Feeds the fixture at `analysisTimes` and reads the bound parameter at each of `sampleTimes` (each also an
    /// analysis time), through the tracker and a binding.
    private func run(_ poses: RecordedHandPoses, analysisTimes: [UInt64], sampleTimes: Set<UInt64>) throws -> [UInt64: Double] {
        let modulator = AudioFeatureModulator(registry: try Self.registry())
        try modulator.bind(AudioFeatureBinding(source: .hand(.pinch), target: Self.target, outputStart: 0.1, outputEnd: 0.9))
        let tracker = HandFeatureTracker()
        var readings: [UInt64: Double] = [:]
        let bands: [Float] = []
        for time in analysisTimes {
            tracker.ingest(poses.frame(at: time), mirrored: false, timeNanoseconds: time)
            guard sampleTimes.contains(time) else { continue }
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: b, hand: tracker.values), timeNanoseconds: time)
            }
            readings[time] = modulator.value(for: Self.target, manual: 0.25)
        }
        return readings
    }

    func testRecordedPoseFramesDriveDeterministicParameterChanges() throws {
        let step: UInt64 = 100 * Self.millisecond
        let regular: [UInt64] = (0...15).map { (i: UInt64) -> UInt64 in i * step }
        let shared = Set(regular)
        var jittered: [UInt64] = []   // the regular times plus 0-3 extra frames at irregular offsets in between
        var seed: UInt64 = 0x2545_F491_4F6C_DD1D
        for time in regular {
            jittered.append(time)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let extra: Int = Int(seed >> 62)
            var offsets: [UInt64] = []
            for k in 0..<extra { offsets.append(UInt64((seed >> UInt64(8 * k + 8)) % 97 + 1) * Self.millisecond) }
            for offset in Set(offsets).sorted() where time + offset < (regular.last ?? 0) { jittered.append(time + offset) }
        }
        XCTAssertGreaterThan(jittered.count, regular.count, "the jittered cadence has extra frames")

        let first: [UInt64: Double] = try run(RecordedHandPoses.fixture, analysisTimes: regular, sampleTimes: shared)
        let second: [UInt64: Double] = try run(RecordedHandPoses.fixture, analysisTimes: regular, sampleTimes: shared)
        XCTAssertEqual(first, second, "two runs of the same recording agree exactly")

        let shuffled: [UInt64: Double] = try run(RecordedHandPoses.fixture, analysisTimes: jittered, sampleTimes: shared)
        for time in regular {
            XCTAssertEqual(shuffled[time] ?? -1, first[time] ?? -2, accuracy: 1e-9, "the same value at \(time / Self.millisecond) ms")
        }

        // Closed form: pinch 0 until 0.5 s; toward 1 with τ = 80 ms until 1.0 s; then toward 0 with τ = 300 ms. Mapped
        // to 0.1…0.9 by the binding.
        func expected(_ seconds: Double) -> Double {
            let pinch: Double
            if seconds <= 0.5 {
                pinch = 0
            } else if seconds <= 1.0 {
                pinch = 1 - exp(-(seconds - 0.5) / 0.08)
            } else {
                pinch = (1 - exp(-0.5 / 0.08)) * exp(-(seconds - 1.0) / 0.3)
            }
            return 0.1 + 0.8 * pinch
        }
        for time in regular {
            let seconds: Double = Double(time) / 1e9
            XCTAssertEqual(first[time] ?? -1, expected(seconds), accuracy: 0.001, "at \(seconds) s")
        }
        XCTAssertEqual(first[600 * Self.millisecond] ?? 0, 0.1 + 0.8 * 0.713495, accuracy: 0.001, "a pinch shows within 100 ms")
    }
}
