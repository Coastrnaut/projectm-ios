// Task T018: every transition in data-model.md §Transitions, plus SC-002's 20 scripted
// playing/paused/absent timelines. Times are injected; no real clock or device.
import XCTest
@testable import AudioCore

final class AudioStateClassifierTests: XCTestCase {
    private let loud: Float = -20      // above −50 dBFS active threshold
    private let quiet: Float = -80     // below −60 dBFS silence threshold
    private let mid: Float = -55       // hysteresis band
    private let chunk = 0.01           // 10 ms analysis chunks

    private func started() -> AudioStateClassifier {
        var c = AudioStateClassifier()
        c.lifecycle(.started, at: 0)
        return c
    }

    /// Feeds chunks of `peak` from `from` to `to` seconds.
    private func feed(_ c: inout AudioStateClassifier, _ peak: Float, from: Double, to: Double) {
        var t = from + chunk
        while t <= to + 1e-9 {
            c.dataArrived(at: t, peakDBFS: peak, duration: chunk)
            t += chunk
        }
    }

    private func idle(_ c: inout AudioStateClassifier, from: Double, to: Double) {
        var t = from + chunk
        while t <= to + 1e-9 { c.tick(at: t); t += chunk }
    }

    func testStartsNotStartedThenWaiting() {
        var c = AudioStateClassifier()
        XCTAssertEqual(c.state, .notStarted)
        c.lifecycle(.started, at: 0)
        XCTAssertEqual(c.state, .waiting)
    }

    func testStartFailedReturnsToNotStartedWithReason() {
        var c = AudioStateClassifier()
        c.lifecycle(.startFailed(.cancelled), at: 0)
        XCTAssertEqual(c.state, .notStarted)
        XCTAssertEqual(c.lastReason, .cancelled)
    }

    func testNoDataForFiveSecondsIsNoAudioReceived() {
        var c = started()
        idle(&c, from: 0, to: 4.9)
        XCTAssertEqual(c.state, .waiting)
        idle(&c, from: 4.9, to: 5.0)
        XCTAssertEqual(c.state, .noAudioReceived)
    }

    func testActiveRequires250msAboveMinus50() {
        var c = started()
        feed(&c, loud, from: 0, to: 0.24)
        XCTAssertEqual(c.state, .waiting, "not yet 250 ms")
        feed(&c, loud, from: 0.24, to: 0.25)
        XCTAssertEqual(c.state, .active)
        XCTAssertTrue(c.hasVerifiedActiveAudio)
    }

    func testInterruptedLoudAudioDoesNotAccumulate() {
        var c = started()
        feed(&c, loud, from: 0, to: 0.2)
        feed(&c, mid, from: 0.2, to: 0.21)     // resets the 250 ms window
        feed(&c, loud, from: 0.21, to: 0.40)
        XCTAssertNotEqual(c.state, .active)
        feed(&c, loud, from: 0.40, to: 0.47)
        XCTAssertEqual(c.state, .active)
    }

    func testQuietDataWhileWaitingIsSilent() {
        var c = started()
        feed(&c, quiet, from: 0, to: 0.01)
        XCTAssertEqual(c.state, .silent)
    }

    func testHysteresisBandWhileWaitingIsSilent() {
        var c = started()
        feed(&c, mid, from: 0, to: 0.01)
        XCTAssertEqual(c.state, .silent)
    }

    func testActiveToSilentAfterTwoSecondsBelowMinus60() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        feed(&c, quiet, from: 1, to: 2.99)
        XCTAssertEqual(c.state, .active, "under 2 s of quiet")
        feed(&c, quiet, from: 2.99, to: 3.0)
        XCTAssertEqual(c.state, .silent)
    }

    func testHysteresisBandKeepsActive() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        feed(&c, mid, from: 1, to: 10)
        XCTAssertEqual(c.state, .active)
    }

    func testSilentToActive() {
        var c = started()
        feed(&c, quiet, from: 0, to: 1)
        XCTAssertEqual(c.state, .silent)
        feed(&c, loud, from: 1, to: 1.25)
        XCTAssertEqual(c.state, .active)
    }

    func testNoAudioReceivedToActive() {
        var c = started()
        idle(&c, from: 0, to: 5)
        XCTAssertEqual(c.state, .noAudioReceived)
        feed(&c, loud, from: 5, to: 5.25)
        XCTAssertEqual(c.state, .active)
    }

    func testDataStoppingMidSessionIsNoAudioReceived() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        idle(&c, from: 1, to: 6)
        XCTAssertEqual(c.state, .noAudioReceived)
    }

    func testProlongedSilenceHintAfter60sWithoutStateChange() {
        var c = started()
        feed(&c, quiet, from: 0, to: 59.9)
        XCTAssertEqual(c.state, .silent)
        XCTAssertFalse(c.prolongedSilenceHint)
        feed(&c, quiet, from: 59.9, to: 60.1)
        XCTAssertEqual(c.state, .silent)
        XCTAssertTrue(c.prolongedSilenceHint)
        feed(&c, loud, from: 60.1, to: 60.4)
        XCTAssertEqual(c.state, .active)
        XCTAssertFalse(c.prolongedSilenceHint)
    }

    func testSuspendResume() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        c.lifecycle(.suspended, at: 1)
        XCTAssertEqual(c.state, .paused)
        // No timeouts while paused.
        idle(&c, from: 1, to: 20)
        XCTAssertEqual(c.state, .paused)
        c.lifecycle(.resumed, at: 20)
        XCTAssertEqual(c.state, .waiting)
    }

    func testInterruptionAutoResumeAndNoResume() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        c.lifecycle(.interruptionBegan, at: 1)
        XCTAssertEqual(c.state, .interrupted)
        c.lifecycle(.interruptionEnded(shouldResume: false), at: 2)
        XCTAssertEqual(c.state, .interrupted, "stays interrupted until one-tap restart")
        c.lifecycle(.interruptionEnded(shouldResume: true), at: 3)
        XCTAssertEqual(c.state, .waiting)
    }

    func testUserStopFailedAndEndedBySystem() {
        var c = started()
        c.lifecycle(.userStopped, at: 1)
        XCTAssertEqual(c.state, .stopped)
        XCTAssertNil(c.lastReason)

        c = started()
        c.lifecycle(.failed(.microphoneUnavailable), at: 1)
        XCTAssertEqual(c.state, .stopped)
        XCTAssertEqual(c.lastReason, .microphoneUnavailable)

        c = started()
        c.lifecycle(.endedBySystem, at: 1)
        XCTAssertEqual(c.state, .endedBySystem)
        XCTAssertEqual(c.lastReason, .endedBySystem)
    }

    func testDataIgnoredWhenNotRunning() {
        var c = AudioStateClassifier()
        c.dataArrived(at: 1, peakDBFS: loud, duration: 1)
        XCTAssertEqual(c.state, .notStarted)
    }

    func testRestartClearsVerification() {
        var c = started()
        feed(&c, loud, from: 0, to: 1)
        XCTAssertTrue(c.hasVerifiedActiveAudio)
        c.lifecycle(.userStopped, at: 1)
        c.lifecycle(.started, at: 2)
        XCTAssertFalse(c.hasVerifiedActiveAudio)
    }

    /// SC-002: 20 scripted trials per scenario (playing, paused, absent) classify correctly.
    func testSC002ScriptedTimelines() {
        for trial in 0..<20 {
            let offset = Double(trial) * 0.013   // vary chunk alignment per trial

            var playing = started()
            feed(&playing, loud, from: offset, to: offset + 3)
            XCTAssertEqual(playing.state, .active, "playing trial \(trial)")

            var paused = started()
            feed(&paused, loud, from: offset, to: offset + 3)
            feed(&paused, quiet, from: offset + 3, to: offset + 5.1)
            XCTAssertEqual(paused.state, .silent, "paused trial \(trial)")

            var absent = started()
            idle(&absent, from: offset, to: offset + 5.1)
            XCTAssertEqual(absent.state, .noAudioReceived, "absent trial \(trial)")
        }
    }

    /// SC-003: silent→active and active→silent changes are classified within 2 s of the change.
    func testSC003TransitionLatency() {
        var c = started()
        feed(&c, quiet, from: 0, to: 1)
        feed(&c, loud, from: 1, to: 1.3)
        XCTAssertEqual(c.state, .active)            // 0.25 s after the change
        feed(&c, quiet, from: 1.3, to: 3.3)
        XCTAssertEqual(c.state, .silent)            // 2.0 s after the change
    }
}
