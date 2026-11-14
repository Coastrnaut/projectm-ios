// CAM-013-T05: the camera's stop reasons and retry rules (CAM-013-R3, R4, R6, R7, R10, R14; S3, S4).
// Plain Swift on a fake clock: runs on every platform, including the Linux shape
// (`-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`).
import CameraLayer
import XCTest

final class CameraRecoveryTests: XCTestCase {
    private struct Row {
        let reason: CameraStopReason
        let state: CameraFeedState
        let resumes: Bool
        let automatic: Bool
        let notice: String
    }

    /// The reason table of data-model.md; every case must appear exactly once.
    private let table: [Row] = [
        Row(reason: .anotherApp, state: .interrupted, resumes: true, automatic: false,
            notice: "Another app is using the camera. It comes back when the camera is free, or tap Retry."),
        Row(reason: .multitasking, state: .interrupted, resumes: true, automatic: false,
            notice: "The camera pauses while apps share the screen. It comes back in full screen, or tap Retry."),
        Row(reason: .systemPressure, state: .interrupted, resumes: true, automatic: false,
            notice: "The camera paused because the device is too warm or busy. It comes back when the device recovers, or tap Retry."),
        Row(reason: .background, state: .interrupted, resumes: true, automatic: false,
            notice: "The camera paused while the app was in the background. It comes back on its own, or tap Retry."),
        Row(reason: .otherInterruption, state: .interrupted, resumes: true, automatic: false,
            notice: "The camera is paused by the system. It comes back when the camera is free, or tap Retry."),
        Row(reason: .mediaServicesReset, state: .failed, resumes: false, automatic: true,
            notice: "The camera stopped after a system reset. Tap Retry to start it again."),
        Row(reason: .runtimeError, state: .failed, resumes: false, automatic: false,
            notice: "The camera stopped because of an error. Tap Retry to start it again."),
    ]

    func testEveryReasonHasItsStateTextAndRules() {
        let covered: [CameraStopReason] = table.map { (row: Row) -> CameraStopReason in row.reason }
        XCTAssertEqual(covered, CameraStopReason.allCases, "every reason, once, in order")
        for row in table {
            XCTAssertEqual(row.reason.feedState, row.state, "\(row.reason)")
            XCTAssertEqual(row.reason.resumesWhenEnded, row.resumes, "\(row.reason)")
            XCTAssertEqual(row.reason.retriesAutomatically, row.automatic, "\(row.reason)")
            XCTAssertEqual(row.reason.notice, row.notice, "\(row.reason)")
            XCTAssertTrue(row.state.offersRetry, "\(row.reason): Retry offered")
            XCTAssertEqual(row.state.notice(position: .back, reason: row.reason), row.notice)
            XCTAssertEqual(row.state.notice(position: .front, reason: row.reason), row.notice, "the reason does not depend on the camera")
            XCTAssertEqual(CameraStopReason(rawValue: row.reason.rawValue), row.reason)
        }
    }

    func testOnlyInterruptedAndFailedOfferRetry() {
        let all: [CameraFeedState] = [.idle, .requestingAccess, .starting, .running, .denied, .restricted, .unavailable, .interrupted, .failed]
        let offering: [CameraFeedState] = all.filter { (state: CameraFeedState) -> Bool in state.offersRetry }
        XCTAssertEqual(offering, [.interrupted, .failed])
        XCTAssertEqual(CameraFeedState.denied.notice(position: .back, reason: .anotherApp), CameraFeedState.denied.notice,
                       "a reason never replaces the permission notice")
        XCTAssertEqual(CameraFeedState.interrupted.notice(position: .back, reason: nil), CameraStopReason.otherInterruption.notice)
        XCTAssertEqual(CameraFeedState.failed.notice(position: .back, reason: nil), CameraStopReason.runtimeError.notice,
                       "a failure without a reason does not promise a return")
    }

    /// S4: attempts in a row are spaced 0, 2, 4, 8, 16, 30, 30 s.
    func testBackoffSpacingOnAFakeClock() {
        var recovery = CameraRecovery()
        var now: Double = 100
        var starts: [Double] = []
        for _ in 0..<7 {
            let wait: Double = recovery.delayBeforeNextAttempt(now: now)
            now += wait
            starts.append(now)
            recovery.recordAttempt(now: now)
            recovery.noteStop(.runtimeError, now: now)   // each attempt fails at once
        }
        var gaps: [Double] = []
        for index in 1..<starts.count { gaps.append(starts[index] - starts[index - 1]) }
        XCTAssertEqual(starts[0], 100, "the first attempt runs at once")
        XCTAssertEqual(gaps, [2, 4, 8, 16, 30, 30])
        XCTAssertEqual(recovery.retries, 7)
    }

    /// S4: ten requests within one second give one attempt; the rest only see a wait.
    func testRequestsInsideTheWaitDoNotStartAgain() {
        var recovery = CameraRecovery()
        var attempts = 0
        for step in 0..<10 {
            let now: Double = 50 + Double(step) * 0.1
            if recovery.delayBeforeNextAttempt(now: now) == 0 {
                recovery.recordAttempt(now: now)
                attempts += 1
            }
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(recovery.delayBeforeNextAttempt(now: 50.9), 1.1, accuracy: 1e-9)
    }

    func testTenSecondsOfRunningStartANewRun() {
        var recovery = CameraRecovery()
        recovery.recordAttempt(now: 0)
        recovery.recordAttempt(now: 2)
        recovery.noteRunning(now: 3)
        recovery.noteStop(.anotherApp, now: 12)   // ran 9 s: still the same run
        XCTAssertEqual(recovery.attempts, 2)
        XCTAssertEqual(recovery.delayBeforeNextAttempt(now: 12), 0, "2 + 4 s already passed")
        recovery.noteRunning(now: 20)
        recovery.noteStop(.anotherApp, now: 30)   // ran 10 s: a new run
        XCTAssertEqual(recovery.attempts, 0)
        XCTAssertNil(recovery.lastAttemptAt)
        XCTAssertEqual(recovery.counts[.anotherApp], 2, "counts survive a new run")
    }

    func testOneAutomaticRetryPerRunOfFailures() {
        var recovery = CameraRecovery()
        XCTAssertFalse(recovery.claimAutomaticRetry(for: .runtimeError), "only a media reset retries by itself")
        XCTAssertFalse(recovery.claimAutomaticRetry(for: .anotherApp))
        XCTAssertTrue(recovery.claimAutomaticRetry(for: .mediaServicesReset))
        XCTAssertFalse(recovery.claimAutomaticRetry(for: .mediaServicesReset), "once")
        recovery.reset()
        XCTAssertTrue(recovery.claimAutomaticRetry(for: .mediaServicesReset), "a stop starts a new run")
    }

    /// R10: numbers only.
    func testCountsAreNumbersOnly() {
        var recovery = CameraRecovery()
        recovery.noteStop(.anotherApp, now: 1)
        recovery.noteStop(.anotherApp, now: 2)
        recovery.noteStop(.mediaServicesReset, now: 3)
        recovery.recordAttempt(now: 3)
        XCTAssertEqual(recovery.countsSummary, "anotherApp:2,mediaServicesReset:1,retries:1")
        recovery.reset()
        XCTAssertEqual(recovery.countsSummary, "anotherApp:2,mediaServicesReset:1,retries:1", "reset keeps the counts")
        XCTAssertEqual(CameraRecovery().countsSummary, "retries:0")
    }
}
