// FaceFeatureTrackerTests.swift — CAM-009-T03 (CAM-009-R6 to R10, S2; contract face-sources F1 to F3). Synthetic face
// observations (plain values standing in for Vision's): a centred face reads neutral, extremes and degenerate or
// non-finite samples stay finite within 0…1, smoothing and absence follow the injected clock, the schedule throttles,
// the gate needs all three conditions, and the source IDs round-trip. Deterministic: no wall clock.
import Foundation
import ParameterGraph
import XCTest

final class FaceFeatureTrackerTests: XCTestCase {
    private static let origin: UInt64 = 1_000_000_000
    private static let tick: UInt64 = 66_666_667   // 15 Hz

    /// A face box centred in the picture, with a closed mouth and eyes of `eyeRatio` (height ÷ width, box square).
    private static func face(x: Double = 0.4, y: Double = 0.35, size: Double = 0.3, roll: Double? = 0, yaw: Double? = 0,
                             lipGap: Double = 0, eyeRatio: Double = 0.1) -> FaceObservationSample {
        let lips: [FacePoint] = [FacePoint(x: 0.4, y: 0.25), FacePoint(x: 0.6, y: 0.25 + lipGap)]
        let eyeHeight: Double = 0.2 * eyeRatio
        let left: [FacePoint] = [FacePoint(x: 0.2, y: 0.7), FacePoint(x: 0.4, y: 0.7 + eyeHeight)]
        let right: [FacePoint] = [FacePoint(x: 0.6, y: 0.7), FacePoint(x: 0.8, y: 0.7 + eyeHeight)]
        return FaceObservationSample(boxX: x, boxY: y, boxWidth: size, boxHeight: size, roll: roll, yaw: yaw,
                                     innerLips: lips, leftEye: left, rightEye: right)
    }

    private func assertBounded(_ values: FaceFeatureValues, file: StaticString = #filePath, line: UInt = #line) {
        for feature in FaceFeature.allCases {
            let v: Double = values.value(feature)
            XCTAssertTrue(v.isFinite && v >= 0 && v <= 1, "\(feature) = \(v)", file: file, line: line)
        }
        let raw: [Double] = [values.present, values.x, values.y, values.size, values.roll, values.yaw, values.mouth, values.eyes]
        XCTAssertTrue(raw.allSatisfy { (v: Double) -> Bool in v.isFinite && v >= 0 && v <= 1 }, "stored \(raw)", file: file, line: line)
    }

    // MARK: Normalisation (R7)

    func testCentredLevelFaceReadsNeutralAndClosed() {
        let v: FaceFeatureValues = FaceFeatureNormalizer.measure(Self.face(), mirrored: false)
        XCTAssertEqual(v.present, 1)
        XCTAssertEqual(v.x, 0.55, accuracy: 1e-9)
        XCTAssertEqual(v.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(v.size, 0.3, accuracy: 1e-9)
        XCTAssertEqual(v.roll, 0.5, accuracy: 0.01)
        XCTAssertEqual(v.yaw, 0.5, accuracy: 0.01)
        XCTAssertEqual(v.mouth, 0, accuracy: 1e-9)
        XCTAssertEqual(v.eyes, 0, accuracy: 1e-9, "a 0.1 ratio reads closed")
    }

    func testMouthEyesAnglesAndMirroring() {
        let open: FaceFeatureValues = FaceFeatureNormalizer.measure(
            Self.face(roll: Double.pi / 8, yaw: -Double.pi / 2, lipGap: 0.25, eyeRatio: 0.2), mirrored: false)
        XCTAssertEqual(open.mouth, 1, "a gap beyond 0.2 of the face reads fully open")
        XCTAssertEqual(open.eyes, 0.5, accuracy: 1e-9, "0.2 is halfway between closed and open")
        XCTAssertEqual(open.roll, 0.75, accuracy: 1e-9, "22.5° of a ±45° range")
        XCTAssertEqual(open.yaw, 0, "beyond −45° clamps")
        let mirrored: FaceFeatureValues = FaceFeatureNormalizer.measure(Self.face(roll: Double.pi / 8), mirrored: true)
        XCTAssertEqual(mirrored.x, 0.45, accuracy: 1e-9, "x follows the mirrored picture")
        XCTAssertEqual(mirrored.roll, 0.25, accuracy: 1e-9, "roll turns with the mirror")
    }

    // MARK: Bounds (S2)

    func testExtremeDegenerateAndNonFiniteSamplesStayBounded() {
        let tracker = FaceFeatureTracker()
        let samples: [FaceObservationSample?] = [
            Self.face(x: -3, y: 9, size: 40, roll: 1e9, yaw: -.infinity, lipGap: 7, eyeRatio: 50),
            FaceObservationSample(boxX: .nan, boxY: .infinity, boxWidth: 0, boxHeight: -1, roll: .nan, yaw: nil,
                                  innerLips: [FacePoint(x: .nan, y: 1)], leftEye: [FacePoint(x: 0.5, y: 0.5), FacePoint(x: 0.5, y: 0.9)]),
            FaceObservationSample(boxX: 0.2, boxY: 0.2, boxWidth: 1e-300, boxHeight: 1e300),
            nil,
            Self.face(),
        ]
        for (i, sample) in samples.enumerated() {
            tracker.ingest(sample, mirrored: i % 2 == 0, timeNanoseconds: Self.origin + UInt64(i) * Self.tick)
            assertBounded(tracker.values)
        }
    }

    // MARK: Smoothing and absence (R9)

    func testFirstFaceSnapsThenSmoothsAndAbsenceFadesToNeutral() {
        let tracker = FaceFeatureTracker()
        tracker.ingest(Self.face(), mirrored: false, timeNanoseconds: Self.origin)
        XCTAssertEqual(tracker.values.present, 1, "the first face snaps")
        XCTAssertEqual(tracker.values.mouth, 0)

        tracker.ingest(Self.face(lipGap: 0.2), mirrored: false, timeNanoseconds: Self.origin + 80_000_000)
        XCTAssertEqual(tracker.values.mouth, 1 - exp(-1), accuracy: 1e-6, "one 80 ms time constant toward open")

        var time: UInt64 = Self.origin + 80_000_000
        for _ in 0..<20 {   // 1.3 s without a face
            time += Self.tick
            tracker.ingest(nil, mirrored: false, timeNanoseconds: time)
        }
        XCTAssertEqual(tracker.values.present, 0, accuracy: 0.02, "present falls to 0")
        XCTAssertEqual(tracker.values.x, 0.5, accuracy: 0.02, "x eases to neutral")
        XCTAssertEqual(tracker.values.mouth, 0, accuracy: 0.02)

        tracker.ingest(Self.face(roll: nil), mirrored: false, timeNanoseconds: time)
        XCTAssertEqual(tracker.values.roll, 0.5, accuracy: 0.02, "a missing angle holds")
        tracker.reset()
        XCTAssertEqual(tracker.values, .neutral)
    }

    // MARK: Schedule and rate (R10)

    func testScheduleThrottlesAndNeverOverlaps() {
        var schedule = FaceAnalysisSchedule(intervalNanoseconds: FaceTrackingRate.normalInterval)
        XCTAssertTrue(schedule.offer(at: Self.origin))
        XCTAssertFalse(schedule.offer(at: Self.origin + Self.tick * 3), "one in flight")
        schedule.finish()
        XCTAssertFalse(schedule.offer(at: Self.origin + 16_000_000), "too soon after the last start")
        XCTAssertTrue(schedule.offer(at: Self.origin + Self.tick))
        schedule.finish()
        var started = 0
        for frame in 0..<60 {   // one second of 60 Hz pictures
            if schedule.offer(at: Self.origin + 2 * Self.tick + UInt64(frame) * 16_666_667) {
                started += 1
                schedule.finish()
            }
        }
        XCTAssertLessThanOrEqual(started, 15, "at most 15 a second")
        XCTAssertGreaterThanOrEqual(started, 14)
        XCTAssertNil(FaceTrackingRate.interval(warm: true, reducedPower: false), "paused when warm")
        XCTAssertEqual(FaceTrackingRate.interval(warm: false, reducedPower: true), FaceTrackingRate.reducedPowerInterval)
        var paused = FaceAnalysisSchedule(intervalNanoseconds: nil)
        XCTAssertFalse(paused.offer(at: Self.origin))
    }

    // MARK: Gate (R1, R4, R5)

    func testGateNeedsSwitchConsentAndCamera() {
        for switchOn in [false, true] {
            for consented in [false, true] {
                for camera in [false, true] {
                    let gate = FaceTrackingGate(switchOn: switchOn, consented: consented, cameraAuthorized: camera)
                    XCTAssertEqual(gate.allowsAnalysis, switchOn && consented && camera)
                }
            }
        }
    }

    // MARK: Sources (R8, F1)

    func testSourceIDsRoundTripAndReadNeutralWithoutFaceValues() {
        for feature in FaceFeature.allCases {
            let source = AudioFeatureSource.face(feature)
            XCTAssertEqual(source.id, "audio.face." + feature.rawValue)
            XCTAssertEqual(AudioFeatureSource(id: source.id), source)
            XCTAssertEqual(source.value(in: .silent), FaceFeatureValues.neutralValue(feature))
        }
        XCTAssertNil(AudioFeatureSource(id: "audio.face.nose"))
        XCTAssertNil(AudioFeatureSource(id: "audio.face."))
        var frame = AudioFeatureFrame.silent
        frame.face = FaceFeatureValues(present: 1, x: 0.2, y: 0.9, size: 0.4, roll: .nan, yaw: 3, mouth: 0.7, eyes: -1)
        XCTAssertEqual(AudioFeatureSource.face(.mouth).value(in: frame), 0.7)
        XCTAssertEqual(AudioFeatureSource.face(.roll).value(in: frame), 0.5, "non-finite reads neutral")
        XCTAssertEqual(AudioFeatureSource.face(.yaw).value(in: frame), 1, "clamped")
        XCTAssertEqual(AudioFeatureSource.face(.eyes).value(in: frame), 0)
    }
}
