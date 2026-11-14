// FeatureAgeAppTests.swift — PERF-013-T09 (specs/216-perf-013-audio-render-sync, R2, R8-R10; contracts/feature-age.md
// C2-C4): the app's feature age attachment follows the overlay and the shown visual, the overlay line's text
// (available, unavailable, AUD-013 offset, drift), one signpost per drift verdict change, and the PERF-012 report's
// audioSync section. Injected stamps and times only (no wall clock).
import Compositor
import Diagnostics
import FrameTiming
import XCTest
@testable import projectM_iOS

/// A visual that only holds what it was given.
@MainActor
private final class FakeMeasuredVisual: FeatureAgeMeasured {
    var featureAge: FeatureAgeMeter?
}

@MainActor
final class FeatureAgeAppTests: XCTestCase {
    /// `frames` presentations 1/60 s apart, each consuming a frame whose audio is `age` old, with `ppm` residual growth.
    private func feed(_ meter: FeatureAgeMeter, frames: Int, age: UInt64, ppm: Double = 0) {
        for k in 0..<frames {
            let sample: Int64 = 2_048 + Int64(k) * 735
            let bus: UInt64 = 10_000_000_000 + UInt64(Double(sample) / 44_100 * 1e9)
            let growth: UInt64 = UInt64(Double(sample) / 44_100 * ppm * 1_000)
            meter.frame(FeatureFrameStamp(session: 1, sequence: UInt64(k + 1), sessionSample: sample, busHostNanoseconds: bus),
                        arrivalNanoseconds: bus + 3_000_000 + growth, presentationNanoseconds: bus + age)
        }
    }

    func testAttachmentFollowsOverlayAndVisual() {
        var events: [String] = []
        let attachment = FeatureAgeAttachment(emit: { (e: String) -> Void in events.append(e) })
        let first = FakeMeasuredVisual()
        let second = FakeMeasuredVisual()
        attachment.sync(overlayShown: false, target: first)
        XCTAssertNil(first.featureAge)
        attachment.sync(overlayShown: true, target: first)
        XCTAssertTrue(first.featureAge === attachment.meter)
        attachment.sync(overlayShown: true, target: first)
        XCTAssertEqual(attachment.sessionsBegun, 1, "same visual: no new session")
        attachment.sync(overlayShown: true, target: second)
        XCTAssertNil(first.featureAge)
        XCTAssertTrue(second.featureAge === attachment.meter)
        XCTAssertEqual(attachment.sessionsBegun, 2)
        attachment.sync(overlayShown: true, target: nil)   // projectM: consumes no feature frames
        XCTAssertNil(second.featureAge)
        XCTAssertEqual(attachment.line(offsetMilliseconds: 0), FeatureAgeAttachment.unavailableLine)
        XCTAssertEqual(events, [])
    }

    func testOverlayLineShowsAgeOffsetAndUnavailable() {
        let attachment = FeatureAgeAttachment(emit: { (_: String) -> Void in })
        let visual = FakeMeasuredVisual()
        attachment.sync(overlayShown: true, target: visual)
        XCTAssertEqual(attachment.line(offsetMilliseconds: 0), "audio age unavailable", "no frame consumed yet")
        feed(attachment.meter, frames: 120, age: 24_000_000)
        XCTAssertEqual(attachment.line(offsetMilliseconds: 0), "audio age 24.0 ms p95 24.0 ms")
        XCTAssertEqual(attachment.line(offsetMilliseconds: 40), "audio age 24.0 ms p95 24.0 ms offset 40 ms")
    }

    func testDriftVerdictLineAndOneSignpostPerChange() {
        var events: [String] = []
        let attachment = FeatureAgeAttachment(emit: { (e: String) -> Void in events.append(e) })
        let visual = FakeMeasuredVisual()
        attachment.sync(overlayShown: true, target: visual)
        feed(attachment.meter, frames: 60 * 15, age: 20_000_000, ppm: 1_000)   // 15 s of +1,000 ppm residual growth
        let line: String = attachment.line(offsetMilliseconds: 0)
        XCTAssertTrue(line.hasSuffix(", drift 1000.0 ppm corrected"), line)
        _ = attachment.line(offsetMilliseconds: 0)
        XCTAssertEqual(events, ["drift detected 1000.0 ppm"], "one event per verdict change")
        XCTAssertEqual(attachment.verdictEvents, events)
    }

    func testDecimalFormatting() {
        XCTAssertEqual(FeatureAgeAttachment.decimal(24.06), "24.1")
        XCTAssertEqual(FeatureAgeAttachment.decimal(-512.34), "-512.3")
        XCTAssertEqual(FeatureAgeAttachment.decimal(0.04), "0.0")
    }

    func testReportSectionPresentAndAbsent() throws {
        let attachment = FeatureAgeAttachment(emit: { (_: String) -> Void in })
        XCTAssertNil(PerformanceReportBuilder.audioSync(attachment.meter.appSummary()), "nothing measured: absent")
        attachment.sync(overlayShown: true, target: FakeMeasuredVisual())
        feed(attachment.meter, frames: 60, age: 18_000_000)
        let section = try XCTUnwrap(PerformanceReportBuilder.audioSync(attachment.meter.appSummary()))
        XCTAssertEqual(section.sampleCount, 60)
        XCTAssertEqual(try XCTUnwrap(section.p95Ms), 18, accuracy: 0.1)
        XCTAssertFalse(section.driftDetected)
        XCTAssertNil(section.driftPpm)
        let inputs: PerformanceReportInputs = AppCoordinator.gatherPerformanceReportInputs(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000), recorder: PerformanceStateRecorder(),
            frameDrops: FrameDropAttachment(), frameStages: FrameStageAttachment(), recording: nil, visual: .native,
            overlayShown: true, pools: [], featureAges: attachment, footprint: 1, available: 1)
        let report: PerformanceReport = PerformanceReportBuilder.build(inputs)
        XCTAssertEqual(report.audioSync, section)
    }
}
