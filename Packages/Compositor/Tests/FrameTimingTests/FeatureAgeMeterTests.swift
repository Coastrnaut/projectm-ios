// FeatureAgeMeterTests.swift — PERF-013-T05 (specs/216-perf-013-audio-render-sync, US1, R1, R2, S4; contract C1):
// known injected ages read back within the 0.1 ms resolution. Injected times only.
import FrameTiming
import XCTest

final class FeatureAgeMeterTests: XCTestCase {
    /// `frames` presentations 1/60 s apart, each consuming a new frame whose audio is `age` old at presentation.
    func feed(_ meter: FeatureAgeMeter, frames: Int, age: UInt64, session: UInt64 = 1, start: UInt64 = 5_000_000_000) {
        for k in 0..<frames {
            let presentation: UInt64 = start + UInt64(k) * 16_666_667
            let bus: UInt64 = presentation - age
            let sample: Int64 = Int64(Double(bus - 1_000_000_000) / 1e9 * 44_100)
            meter.frame(FeatureFrameStamp(session: session, sequence: UInt64(k + 1), sessionSample: sample, busHostNanoseconds: bus),
                        arrivalNanoseconds: bus + 2_000_000, presentationNanoseconds: presentation)
        }
    }

    func testKnownAgeReadsBack() throws {
        let meter = FeatureAgeMeter()
        feed(meter, frames: 120, age: 20_000_000)
        let summary = meter.summary()
        XCTAssertEqual(summary.count, 120)
        XCTAssertEqual(try XCTUnwrap(summary.smoothedMs), 20, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(summary.p50Ms), 20, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(summary.p95Ms), 20, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(summary.maxMs), 20, accuracy: 0.001)
        XCTAssertEqual(summary.anomalies, 0)
        XCTAssertFalse(summary.driftDetected)
        XCTAssertEqual(summary.correctionMs, 0)
    }

    func testNoConsumedFrameIsUnavailable() {
        let meter = FeatureAgeMeter()
        XCTAssertNil(meter.frame(nil, arrivalNanoseconds: 1, presentationNanoseconds: 2))
        let summary = meter.summary()
        XCTAssertEqual(summary.count, 0)
        XCTAssertNil(summary.smoothedMs)
        XCTAssertNil(summary.p50Ms)
        XCTAssertNil(summary.p95Ms)
        XCTAssertNil(summary.maxMs)
    }

    func testTheNewestFrameAgesUntilTheNextArrives() throws {
        let meter = FeatureAgeMeter()
        let stamp = FeatureFrameStamp(session: 1, sequence: 1, sessionSample: 44_100, busHostNanoseconds: 2_000_000_000)
        meter.frame(stamp, arrivalNanoseconds: 2_001_000_000, presentationNanoseconds: 2_010_000_000)
        let later = try XCTUnwrap(meter.frame(nil, arrivalNanoseconds: 2_017_000_000, presentationNanoseconds: 2_026_666_667))
        XCTAssertEqual(later, 26_666_667, accuracy: 1)
    }

    func testNegativeAgeIsAnAnomaly() {
        let meter = FeatureAgeMeter()
        let stamp = FeatureFrameStamp(session: 1, sequence: 1, sessionSample: 44_100, busHostNanoseconds: 3_000_000_000)
        meter.frame(stamp, arrivalNanoseconds: 3_000_000_000, presentationNanoseconds: 2_990_000_000)
        XCTAssertEqual(meter.summary().anomalies, 1)
        XCTAssertEqual(meter.summary().count, 0)
    }

    func testCountingSessionResetKeepsTheAppSession() throws {
        let meter = FeatureAgeMeter()
        feed(meter, frames: 60, age: 30_000_000)
        meter.beginCountingSession()
        XCTAssertEqual(meter.summary().count, 0)
        XCTAssertNil(meter.summary().p95Ms)
        feed(meter, frames: 60, age: 10_000_000, start: 7_000_000_000)
        XCTAssertEqual(try XCTUnwrap(meter.summary().p95Ms), 10, accuracy: 0.1)
        let app = meter.appSummary()
        XCTAssertEqual(app.count, 120)
        XCTAssertEqual(try XCTUnwrap(app.maxMs), 30, accuracy: 0.001)
    }
}
