// RecordingStorageTests.swift — REC-015-T05: the disk guard's estimate, policy, error classifier and
// notices (REC-015-S4, research REC-015-D2 to D4). Plain Swift; runs in the Linux shape.
import Foundation
@testable import FrameRecording
import XCTest

final class RecordingStorageTests: XCTestCase {
    private func geometry(_ width: Int, _ height: Int) throws -> RecordingGeometry {
        try XCTUnwrap(RecordingGeometry(drawableWidth: width, drawableHeight: height, maxLongSide: 1920))
    }

    // MARK: Estimate (REC-015-R2)

    func testEstimateUsesTheHighestCodecRatePlusHeadroom() throws {
        let both = RecordingStorageEstimate(geometry: try geometry(1920, 1080), settings: .standard)
        XCTAssertEqual(both.bytesPerSecond, Int64(1_944_000), "H.264 12,441,600 b/s × 1.25 / 8")
        let policy = RecordingStoragePolicy(estimate: both)
        XCTAssertEqual(policy.bytesNeededToStart, Int64(326_355_200), "200 MiB + 60 s")

        let hevc = RecordingStorageEstimate(geometry: try geometry(1920, 1080), settings: RecordingSettings(codecPreference: [.hevc]))
        XCTAssertEqual(hevc.bytesPerSecond, Int64(1_166_400), "HEVC 7,464,960 b/s × 1.25 / 8")

        let tiny = RecordingStorageEstimate(geometry: try geometry(160, 120), settings: RecordingSettings(codecPreference: [.h264]))
        XCTAssertEqual(tiny.bytesPerSecond, Int64(156_250), "the 1 Mb/s floor × 1.25 / 8")
    }

    func testEstimateFollowsTheScaledOutputAndFrameRate() throws {
        // An iPhone 15 portrait drawable (1179 × 2556) is cropped to 1178 × 2556 and scaled to fit 1920.
        let g = try geometry(1179, 2556)
        XCTAssertEqual([g.outputWidth, g.outputHeight], [884, 1920])
        let estimate = RecordingStorageEstimate(geometry: g, settings: .standard)
        // 884 × 1920 × 30 × 0.2 = 10,183,680 b/s → × 125 / 800 = 1,591,200 B/s.
        XCTAssertEqual(estimate.bytesPerSecond, Int64(1_591_200))
        let sixty = RecordingStorageEstimate(geometry: g, settings: RecordingSettings(maxFrameRate: 60))
        XCTAssertEqual(sixty.bytesPerSecond, Int64(3_182_400))
    }

    // MARK: Policy (REC-015-R3, R5, R9)

    func testStartNeedsTheReservePlusOneMinute() {
        let policy = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: 1_000_000))
        let needed: Int64 = 209_715_200 + 60_000_000
        XCTAssertEqual(policy.bytesNeededToStart, needed)
        XCTAssertTrue(policy.allowsStart(availableBytes: needed))
        XCTAssertFalse(policy.allowsStart(availableBytes: needed - 1))
        XCTAssertFalse(policy.allowsStart(availableBytes: 0))
        XCTAssertTrue(policy.allowsStart(availableBytes: nil), "an unknown value never refuses")
    }

    func testStopLeavesTwoIntervalsAboveTheReserve() {
        let policy = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: 1_000_000))
        let threshold: Int64 = 209_715_200 + 10_000_000
        XCTAssertEqual(policy.stopThreshold(fileBytes: nil, recordedSeconds: 0), threshold)
        XCTAssertFalse(policy.shouldStop(availableBytes: threshold, fileBytes: nil, recordedSeconds: 0))
        XCTAssertTrue(policy.shouldStop(availableBytes: threshold - 1, fileBytes: nil, recordedSeconds: 0))
        XCTAssertFalse(policy.shouldStop(availableBytes: nil, fileBytes: 5_000_000, recordedSeconds: 3), "unknown: no stop")
    }

    func testMeasuredRateWinsWhenLarger() {
        let policy = RecordingStoragePolicy(estimate: RecordingStorageEstimate(bytesPerSecond: 1_000_000))
        XCTAssertNil(policy.measuredBytesPerSecond(fileBytes: 9_000_000, recordedSeconds: 0.5), "under one second: not measured")
        XCTAssertEqual(policy.measuredBytesPerSecond(fileBytes: 9_000_000, recordedSeconds: 3), Int64(3_000_000))
        let fast: Int64 = 209_715_200 + 30_000_000
        XCTAssertEqual(policy.stopThreshold(fileBytes: 9_000_000, recordedSeconds: 3), fast)
        let slow: Int64 = 209_715_200 + 10_000_000
        XCTAssertEqual(policy.stopThreshold(fileBytes: 1_000, recordedSeconds: 3), slow, "the estimate is the floor")
    }

    // MARK: Out-of-space errors (REC-015-R7, R8)

    func testOutOfSpaceErrorsAreRecognizedDirectlyAndWrapped() {
        let cocoa = NSError(domain: "NSCocoaErrorDomain", code: 640)
        let av = NSError(domain: "AVFoundationErrorDomain", code: -11807)
        let posix = NSError(domain: "NSPOSIXErrorDomain", code: 28)
        for error in [cocoa, av, posix] {
            XCTAssertTrue(RecordingFailure.isOutOfSpace(error), "\(error.domain) \(error.code)")
            XCTAssertEqual(RecordingFailure.fromWriterError(error, fallback: "x"), .storageFull)
        }
        let unknown = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: posix])
        XCTAssertTrue(RecordingFailure.isOutOfSpace(unknown), "a wrapped POSIX ENOSPC")
        let deep = NSError(domain: "A", code: 1, userInfo: [NSUnderlyingErrorKey:
            NSError(domain: "B", code: 2, userInfo: ["NSMultipleUnderlyingErrorsKey": [NSError(domain: "C", code: 3), cocoa]])])
        XCTAssertTrue(RecordingFailure.isOutOfSpace(deep), "nested and multiple underlying errors")
        XCTAssertTrue(RecordingFailure.isOutOfSpace(RecordingWriterFault.diskFull(afterFrames: 1).error))
    }

    func testOtherErrorsKeepTheWriterFailure() {
        let other = NSError(domain: "NSPOSIXErrorDomain", code: 5)   // EIO
        XCTAssertFalse(RecordingFailure.isOutOfSpace(other))
        XCTAssertFalse(RecordingFailure.isOutOfSpace(NSError(domain: "NSCocoaErrorDomain", code: 642)))
        guard case .writerFailed = RecordingFailure.fromWriterError(other, fallback: "x") else { return XCTFail() }
        XCTAssertEqual(RecordingFailure.fromWriterError(nil, fallback: "finish failed"), .writerFailed("finish failed"))
        XCTAssertEqual(RecordingFailure.fromWriterError(other, fallback: "x").notice, "The recording couldn't be finished.")
    }

    func testNotices() {
        XCTAssertEqual(RecordingFailure.storageFull.notice, "Storage is full; the recording couldn't be saved.")
        XCTAssertEqual(RecordingStopReason.lowStorage.notice, "Recording stopped because storage is almost full.")
        XCTAssertEqual(RecordingRefusal.lowStorage.notice, "There isn't enough free storage to record. Free up space and try again.")
    }

    func testFileBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-015-size-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(RecordingStorage.fileBytes(at: url))
        try Data(repeating: 7, count: 1234).write(to: url)
        XCTAssertEqual(RecordingStorage.fileBytes(at: url), Int64(1234))
    }

    #if canImport(Darwin)
    func testVolumeProbeReadsTheTemporaryVolume() throws {
        let available = VolumeStorageProbe().availableBytes(at: FileManager.default.temporaryDirectory)
        XCTAssertGreaterThan(try XCTUnwrap(available), Int64(0))
    }
    #endif
}
