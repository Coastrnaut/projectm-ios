// RecordingStatusSummaryTests.swift — REC-009-T02: the status overlay's dropped-frame warning, storage
// texts and levels, and the warning announcement throttle (REC-009-S2 to S4, research REC-009-D2 to D4).
// Plain Swift; runs in the Linux shape.
import Foundation
@testable import FrameRecording
import XCTest

final class RecordingStatusSummaryTests: XCTestCase {
    /// 1,000,000 B/s estimate: reserve 200 MiB, stop threshold reserve + 10 s × rate.
    private let policy = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: 1_000_000))

    private func summary(dropped: Int, written: Int) -> RecordingStatusSummary {
        RecordingStatusSummary(droppedSlots: dropped, writtenFrames: written, availableBytes: nil, secondsLeft: nil)
    }

    // MARK: Dropped frames (REC-009-R2, D2)

    func testDroppedWarningNeedsTenDropsAndTwoPercent() {
        XCTAssertFalse(summary(dropped: 9, written: 10).droppedWarning, "9 drops: below the minimum even at 47%")
        XCTAssertTrue(summary(dropped: 10, written: 490).droppedWarning, "10 of 500 slots = 2.0%")
        XCTAssertFalse(summary(dropped: 10, written: 491).droppedWarning, "10 of 501 slots < 2%")
        XCTAssertFalse(summary(dropped: 0, written: 0).droppedWarning)
    }

    func testDroppedTexts() {
        XCTAssertEqual(summary(dropped: 3, written: 300).droppedText, "Dropped frames: 3")
        XCTAssertEqual(summary(dropped: 12, written: 388).droppedText, "Dropping frames: 12 (3%)")
        XCTAssertEqual(summary(dropped: 0, written: 0).droppedText, "Dropped frames: 0")
    }

    func testStatisticsInitializerTakesTheDroppedSlots() {
        var statistics = RecordingStatistics()
        statistics.written = 100
        statistics.droppedSlots = 4
        statistics.droppedBusy = 99   // not a slot count: the overlay shows slots (REC-006)
        let s = RecordingStatusSummary(statistics: statistics, policy: nil, availableBytes: 5_000_000_000, fileBytes: nil,
                                       recordedSeconds: 3)
        XCTAssertEqual(s.droppedSlots, 4)
        XCTAssertEqual(s.writtenFrames, 100)
        XCTAssertNil(s.secondsLeft, "no policy: no time left")
        XCTAssertNil(s.storageLevel)
    }

    // MARK: Storage (REC-009-R3, R8, D3)

    func testBytesText() {
        XCTAssertEqual(RecordingStatusSummary.bytesText(2_190_000_000), "2.1 GB")
        XCTAssertEqual(RecordingStatusSummary.bytesText(1_000_000_000), "1.0 GB")
        XCTAssertEqual(RecordingStatusSummary.bytesText(999_999_999), "999 MB")
        XCTAssertEqual(RecordingStatusSummary.bytesText(850_400_000), "850 MB")
        XCTAssertEqual(RecordingStatusSummary.bytesText(-5), "0 MB")
    }

    func testSecondsLeftUsesTheGuardsThresholdAndTheLargerRate() {
        let threshold: Int64 = RecordingStoragePolicy.reserveBytes + 10 * 1_000_000
        let free: Int64 = threshold + 840_000_000
        // Before one second: the estimate (1 MB/s) → 840 s.
        XCTAssertEqual(RecordingStatusSummary.secondsLeft(policy: policy, availableBytes: free, fileBytes: 999_999_999,
                                                          recordedSeconds: 0.5), 840)
        // Measured 2 MB/s after 2 s: the threshold grows to reserve + 10 s × 2 MB/s and the rate doubles.
        let measured = RecordingStatusSummary.secondsLeft(policy: policy, availableBytes: free, fileBytes: 4_000_000, recordedSeconds: 2)
        XCTAssertEqual(measured, (free - (RecordingStoragePolicy.reserveBytes + 20_000_000)) / 2_000_000)
        // A measured rate below the estimate never adds time.
        XCTAssertEqual(RecordingStatusSummary.secondsLeft(policy: policy, availableBytes: free, fileBytes: 1_000, recordedSeconds: 10), 840)
        // Below the threshold: zero, not negative; unknown: nil.
        XCTAssertEqual(RecordingStatusSummary.secondsLeft(policy: policy, availableBytes: threshold - 1, fileBytes: nil, recordedSeconds: 0), 0)
        XCTAssertNil(RecordingStatusSummary.secondsLeft(policy: policy, availableBytes: nil, fileBytes: nil, recordedSeconds: 0))
    }

    func testStorageLevelsSwitchAtFiveAndOneMinutes() {
        func level(_ seconds: Int64?) -> RecordingStorageLevel? {
            RecordingStatusSummary(droppedSlots: 0, writtenFrames: 0, availableBytes: 1, secondsLeft: seconds).storageLevel
        }
        XCTAssertEqual(level(300), .ok)
        XCTAssertEqual(level(299), .low)
        XCTAssertEqual(level(60), .low)
        XCTAssertEqual(level(59), .critical)
        XCTAssertEqual(level(0), .critical)
        XCTAssertNil(level(nil), "unknown free storage never warns")
    }

    func testStorageTexts() {
        let threshold: Int64 = RecordingStoragePolicy.reserveBytes + 10 * 1_000_000
        let ample = RecordingStatusSummary(statistics: RecordingStatistics(), policy: policy, availableBytes: threshold + 840_000_000,
                                           fileBytes: nil, recordedSeconds: 0)
        XCTAssertEqual(ample.storageText, "1.0 GB free, about 14 min left")
        XCTAssertEqual(ample.storageLevel, .ok)
        let low = RecordingStatusSummary(droppedSlots: 0, writtenFrames: 0, availableBytes: 850_400_000, secondsLeft: 45)
        XCTAssertEqual(low.storageText, "850 MB free, under 1 min left")
        let unknown = RecordingStatusSummary(statistics: RecordingStatistics(), policy: policy, availableBytes: nil, fileBytes: nil,
                                             recordedSeconds: 0)
        XCTAssertEqual(unknown.storageText, "Free storage unknown")
    }

    // MARK: Throttle (REC-009-R4, S4, D4)

    func testThrottleAnnouncesRisingLevelsAtMostOncePerThirtySeconds() {
        var t = RecordingWarningThrottle()
        XCTAssertFalse(t.submit(.storage, level: 0, at: 0))
        XCTAssertTrue(t.submit(.storage, level: 1, at: 1), "first low")
        XCTAssertFalse(t.submit(.storage, level: 1, at: 2), "same level")
        XCTAssertFalse(t.submit(.storage, level: 2, at: 10), "critical within 30 s of the last announcement")
        XCTAssertTrue(t.submit(.storage, level: 2, at: 31), "critical, 30 s later")
        XCTAssertFalse(t.submit(.storage, level: 2, at: 90), "never the same level twice")
        XCTAssertFalse(t.submit(.storage, level: 1, at: 95), "falling is silent")
        XCTAssertTrue(t.submit(.droppedFrames, level: 1, at: 95), "kinds are independent")
    }

    func testThrottleReArmsAfterTheWarningClears() {
        var t = RecordingWarningThrottle()
        XCTAssertTrue(t.submit(.droppedFrames, level: 1, at: 0))
        XCTAssertFalse(t.submit(.droppedFrames, level: 0, at: 5))
        XCTAssertFalse(t.submit(.droppedFrames, level: 1, at: 10), "re-armed, but within 30 s")
        XCTAssertTrue(t.submit(.droppedFrames, level: 1, at: 30))
    }

    func testABurstOfReadingsAnnouncesAtMostOncePerKindPerThirtySeconds() {
        var t = RecordingWarningThrottle()
        var announced: [Double] = []
        for step in 0..<240 {   // 60 s of readings every 0.25 s, the level flapping 0/1/2
            let time = Double(step) * 0.25
            if t.submit(.storage, level: step % 3, at: time) { announced.append(time) }
        }
        XCTAssertLessThanOrEqual(announced.count, 3, "\(announced)")
        for (a, b) in zip(announced, announced.dropFirst()) { XCTAssertGreaterThanOrEqual(b - a, 30) }
    }
}
