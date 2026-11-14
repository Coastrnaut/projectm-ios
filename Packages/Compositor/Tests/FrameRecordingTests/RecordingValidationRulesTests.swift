// RecordingValidationRulesTests.swift — QA-008-T02 (QA-008-S3, R3-R10): the rules on synthetic time series
// and measurements, including the faults no writer will produce. Foundation-free; runs on Linux.
@testable import FrameRecording
import XCTest

final class RecordingValidationRulesTests: XCTestCase {
    private func regular(_ count: Int, interval: Int64 = 20, from start: Int64 = 0) -> [Int64] {
        (0..<count).map { (k: Int) -> Int64 in start + Int64(k) * interval }
    }

    private func codes(_ issues: [RecordingIssue]) -> Set<RecordingIssue.Code> {
        Set(issues.map { (i: RecordingIssue) -> RecordingIssue.Code in i.code })
    }

    /// A clean one-second 30 fps measurement.
    private func good(frames: Int = 30) -> RecordingMeasurement {
        RecordingMeasurement(codec: "avc1", width: 160, height: 120, presentationTicks: regular(frames),
                             durationSeconds: Double(frames) / 30)
    }

    // MARK: - Timestamp series (R3)

    func testRegularSeriesHasNoIssue() {
        XCTAssertEqual(RecordingValidation.checkTimestamps(regular(300), frameRate: 30), [])
        XCTAssertEqual(RecordingValidation.checkTimestamps(regular(60, interval: 10), frameRate: 60), [])
        XCTAssertEqual(RecordingValidation.checkTimestamps(regular(24, interval: 25), frameRate: 24), [])
    }

    func testSingleFrameHasNoIntervalIssue() {
        XCTAssertEqual(RecordingValidation.checkTimestamps([0], frameRate: 30), [])
        XCTAssertTrue(RecordingValidation.evaluate(good(frames: 1), against: RecordingExpectation(durationSeconds: 1.0 / 30)).passed)
    }

    func testEachTimestampFault() {
        // Each fault on its own (a repeated frame inserted; one frame stamped 10 ticks early): a replaced
        // time would also leave a double step, a real second fault.
        var duplicate = regular(10); duplicate.insert(duplicate[4], at: 5)
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(duplicate, frameRate: 30)), [.duplicateTimestamp])
        var replaced = regular(10); replaced[5] = replaced[4]
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(replaced, frameRate: 30)), [.duplicateTimestamp, .timestampGap])
        var backwards = regular(10); backwards.insert(50, at: 4)   // 60 → 50 → 80
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(backwards, frameRate: 30)), [.notIncreasing])
        var gap = regular(10); gap[9] += 20   // a 40-tick step > 1.5 × 20
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(gap, frameRate: 30)), [.timestampGap])
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(regular(10, from: 20), frameRate: 30)), [.firstTimeNotAtStart])
        XCTAssertEqual(RecordingValidation.checkTimestamps(regular(10, from: 20), frameRate: 30, startTick: 20), [])
    }

    func testGapThresholdIsOneAndAHalfIntervals() {
        var within = regular(10); within[9] = within[8] + 30   // exactly 1.5 ×: allowed
        XCTAssertEqual(RecordingValidation.checkTimestamps(within, frameRate: 30), [])
        within[9] += 1
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps(within, frameRate: 30)), [.timestampGap])
    }

    func testOneIssuePerCodeNamingTheFirstPlace() {
        var series = regular(20); series.insert(series[9], at: 10); series.insert(series[4], at: 5)
        let issues = RecordingValidation.checkTimestamps(series, frameRate: 30)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].detail.hasPrefix("frame 5:"), issues[0].detail)
    }

    func testNoFramesIsADurationFault() {
        XCTAssertEqual(codes(RecordingValidation.checkTimestamps([], frameRate: 30)), [.durationMismatch])
    }

    // MARK: - Duration and frame count (R4, R5) and precedence

    func testDurationRules() {
        XCTAssertTrue(RecordingValidation.evaluate(good(), against: RecordingExpectation(durationSeconds: 1.0)).passed)
        XCTAssertTrue(RecordingValidation.evaluate(good(), against: RecordingExpectation(durationSeconds: 1.0 + 1.0 / 30)).passed, "±1 frame")
        XCTAssertEqual(RecordingValidation.evaluate(good(), against: RecordingExpectation(durationSeconds: 1.1)).codes, [.durationMismatch])
        var long = good(); long.durationSeconds = 2
        XCTAssertEqual(RecordingValidation.evaluate(long, against: RecordingExpectation()).codes, [.durationMismatch],
                       "the frame-count fault is not repeated")
    }

    func testFrameCountRuleOnlyWhenTimesAndDurationPass() {
        let fps24 = RecordingMeasurement(codec: "hvc1", presentationTicks: regular(24, interval: 25), durationSeconds: 1)
        XCTAssertEqual(RecordingValidation.evaluate(fps24, against: RecordingExpectation()).codes, [.frameCountMismatch])
        XCTAssertTrue(RecordingValidation.evaluate(fps24, against: RecordingExpectation(frameRate: 24)).passed)
        var gap = good(); gap.presentationTicks.removeSubrange(10..<13)
        XCTAssertEqual(RecordingValidation.evaluate(gap, against: RecordingExpectation()).codes, [.timestampGap])
    }

    // MARK: - Codec (R2)

    func testCodecAllowList() {
        XCTAssertEqual(RecordingExpectation().allowedCodecs, ["hvc1", "avc1"])
        var jpeg = good(); jpeg.codec = "jpeg"
        XCTAssertEqual(RecordingValidation.evaluate(jpeg, against: RecordingExpectation()).codes, [.codecNotAllowed])
        XCTAssertTrue(RecordingValidation.evaluate(jpeg, against: RecordingExpectation(allowedCodecs: ["jpeg"])).passed)
    }

    // MARK: - Audio and sync (R6, R7)

    private func withAudio(flash: Double? = 1.0, click: Double? = 1.005) -> RecordingMeasurement {
        var m = good()
        m.audioTrackCount = 1
        m.audioSampleRate = 44_100
        m.audioChannels = 2
        m.audioSampleCount = 44_100
        m.flashSeconds = flash
        m.clickSeconds = click
        return m
    }

    private let marker = RecordingExpectation(expectsAudio: true, checksSyncMarker: true, markerSeconds: 1.0)

    func testAudioPresenceAndPrecedence() {
        XCTAssertTrue(RecordingValidation.evaluate(withAudio(), against: marker).passed)
        XCTAssertEqual(RecordingValidation.evaluate(good(), against: marker).codes, [.audioMissing])
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(), against: RecordingExpectation()).codes, [.audioUnexpected])
    }

    func testAudioFormatAndContiguity() {
        var mono = withAudio(); mono.audioChannels = 1
        XCTAssertEqual(RecordingValidation.evaluate(mono, against: marker).codes, [.audioFormat])
        var broken = withAudio(); broken.audioBreaks = 2
        XCTAssertEqual(RecordingValidation.evaluate(broken, against: marker).codes, [.audioNotContiguous])
        var empty = withAudio(); empty.audioSampleCount = 0
        XCTAssertEqual(RecordingValidation.evaluate(empty, against: marker).codes, [.audioNotContiguous])
    }

    func testSyncTolerance() {
        XCTAssertTrue(RecordingValidation.evaluate(withAudio(click: 1.020), against: marker).passed, "20 ms is within")
        XCTAssertTrue(RecordingValidation.evaluate(withAudio(click: 0.981), against: marker).passed)
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(click: 1.080), against: marker).codes, [.syncOutOfTolerance])
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(click: 0.970), against: marker).codes, [.syncOutOfTolerance])
    }

    func testMarkerMissingAndMarkerTime() {
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(flash: nil), against: marker).codes, [.syncMarkerMissing])
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(click: nil), against: marker).codes, [.syncMarkerMissing])
        XCTAssertEqual(RecordingValidation.evaluate(withAudio(flash: 0.5, click: 0.5), against: marker).codes, [.markerTimeMismatch])
        let noMarker = RecordingExpectation(expectsAudio: true)
        XCTAssertTrue(RecordingValidation.evaluate(withAudio(flash: nil, click: nil), against: noMarker).passed)
    }

    // MARK: - Metadata (R8)

    func testMetadataRules() {
        var located = good(); located.metadataIdentifiers = ["mdta/com.apple.quicktime.location.ISO6709"]
        XCTAssertEqual(RecordingValidation.evaluate(located, against: RecordingExpectation()).codes, [.personalMetadata])
        XCTAssertEqual(RecordingValidation.evaluate(located, against: RecordingExpectation(allowsMetadata: true)).codes, [.personalMetadata])
        var titled = good(); titled.metadataIdentifiers = ["mdta/com.apple.quicktime.title"]
        XCTAssertEqual(RecordingValidation.evaluate(titled, against: RecordingExpectation()).codes, [.unexpectedMetadata])
        XCTAssertTrue(RecordingValidation.evaluate(titled, against: RecordingExpectation(allowsMetadata: true)).passed)
        for id in ["mdta/com.apple.quicktime.make", "mdta/com.apple.quicktime.model", "common/author", "udta/gps", "uiso/loci common/location", "udta/©xyz"] {
            XCTAssertTrue(RecordingValidation.isPersonal(id), id)
        }
    }

    // MARK: - Report

    func testUnreadableReportAndSummary() {
        let report = RecordingValidation.unreadable("x.mp4")
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.codes, [.unreadable])
        XCTAssertNil(report.measurement)
        let pass = RecordingValidation.evaluate(good(), against: RecordingExpectation())
        XCTAssertTrue(pass.summary.hasPrefix("PASS avc1 160x120 frames=30 duration=1000 ms audio=0"), pass.summary)
        var bad = good(); bad.codec = "jpeg"
        XCTAssertTrue(RecordingValidation.evaluate(bad, against: RecordingExpectation()).summary.contains("- codecNotAllowed"))
    }
}
