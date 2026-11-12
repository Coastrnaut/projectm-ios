// Task T021: FR-001, FR-007, FR-016, FR-052, FR-055, plus lifecycle (FR-050/FR-051/FR-054) and
// FR-014 identity gating, using FakeAudioSource and an injected clock. Also: a new attempt clears
// the previous session, final transitions are recorded, log stamps use the session clock, session
// time starts when the source started, and pause reasons end with the session.
import XCTest
import Foundation
import AudioCore
@testable import CaptureKit

final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    var now: Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ s: Double) { lock.lock(); value += s; lock.unlock() }
}

/// Test fixture: three fake sources and a manager with manual analysis and clock.
@MainActor
final class Fixture {
    let clock = ManualClock()
    let capture = FakeAudioSource(mode: .systemAppCapture)
    let mic = FakeAudioSource(mode: .microphone)
    let inApp = FakeAudioSource(mode: .inAppPlayback)
    let manager: CaptureManager

    init() {
        let clock = self.clock
        manager = CaptureManager(sources: [capture, mic, inApp], runsAnalysisTimer: false, clock: { clock.now })
    }

    var runningCount: Int { [capture, mic, inApp].filter { $0.isRunning }.count }
}

@MainActor
final class CaptureManagerTests: XCTestCase {
    // Lazy: XCTestCase.init is nonisolated; first access happens in a @MainActor test method.
    // XCTest creates a new instance per test, so every test gets a fresh fixture.
    private lazy var fixture = Fixture()
    private var clock: ManualClock { fixture.clock }
    private var capture: FakeAudioSource { fixture.capture }
    private var mic: FakeAudioSource { fixture.mic }
    private var inApp: FakeAudioSource { fixture.inApp }
    private var manager: CaptureManager { fixture.manager }

    private func playLoud(_ source: FakeAudioSource, seconds: Double = 0.5) {
        var t = 0.0
        while t < seconds {
            source.pushAudio(amplitude: 0.5, seconds: 0.01)
            clock.advance(0.01)
            manager.stepAnalysisForTesting()
            t += 0.01
        }
    }

    func testSelectStartsAndShowsWaiting() async {
        await manager.select(.microphone)
        XCTAssertEqual(manager.activeMode, .microphone)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.startCount, 1)
    }

    func testOnlyOneActiveSourceAndSwitchStopsOldFirst() async {
        await manager.select(.microphone)
        await manager.select(.inAppPlayback)
        XCTAssertFalse(mic.isRunning)
        XCTAssertTrue(inApp.isRunning)
        XCTAssertEqual(mic.stopCount, 1)
        XCTAssertEqual(manager.state, .waiting, "new source shows Waiting until classified (FR-016)")
        XCTAssertEqual(manager.activeMode, .inAppPlayback)
    }

    func testActiveOnlyAfterVerifiedAudio() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        XCTAssertEqual(manager.state, .active)
        XCTAssertTrue(manager.hasVerifiedActiveAudio)
    }

    func testStopIsIdempotentAndFast() async {
        await manager.select(.microphone)
        let start = Date()
        await manager.stop()
        await manager.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(mic.stopCount, 1, "second stop is a no-op")
    }

    func testFiftyRapidCyclesEndInLastActionWithoutDuplicates() async {
        let modes: [AudioSourceMode] = [.microphone, .inAppPlayback, .systemAppCapture]
        for i in 0..<50 {
            if i % 3 == 2 { await manager.stop() } else { await manager.select(modes[i % modes.count]) }
        }
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.activeMode, .inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(fixture.runningCount, 1)
        XCTAssertTrue(inApp.isRunning)
    }

    func testConcurrentCommandsAreSerialized() async {
        let m = manager   // capture the main-actor manager, not the non-Sendable test case
        async let a: Void = m.select(.microphone)
        async let b: Void = m.select(.inAppPlayback)
        async let c: Void = m.stop()
        _ = await (a, b, c)
        XCTAssertLessThanOrEqual(fixture.runningCount, 1)
    }

    func testStartFailureShowsReason() async {
        mic.startError = SourceError(.permissionDenied)
        await manager.select(.microphone)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
    }

    func testUnavailableModeReportsUnsupportedOS() async {
        capture.availability = .unavailable(.unsupportedOS)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .unsupportedOS)
        XCTAssertEqual(capture.startCount, 0, "never starts an unavailable source")
    }

    func testRestartAfterEndedBySystem() async {
        await manager.select(.systemAppCapture)
        capture.emit(.endedBySystem("stopped sharing"))
        await settle()
        XCTAssertEqual(manager.state, .endedBySystem)
        await manager.restart()
        XCTAssertEqual(capture.startCount, 2, "restart re-runs start, which re-presents the picker")
        XCTAssertEqual(manager.state, .waiting)
    }

    /// Owner ruling 2026-11-08: the detail of a system stop (with its SCStreamError code) is kept
    /// for the export, and a new attempt clears it.
    func testStopDetailIsKeptForTheExportAndClearedOnNewAttempt() async {
        await manager.select(.systemAppCapture)
        capture.emit(.endedBySystem("The stream was stopped (SCStreamError -3824)"))
        await settle()
        XCTAssertEqual(manager.state, .endedBySystem)
        XCTAssertEqual(manager.stopDetail, "The stream was stopped (SCStreamError -3824)")

        await manager.select(.microphone)
        XCTAssertNil(manager.stopDetail, "a new start attempt clears the previous detail")

        mic.startError = SourceError(.error("engine failed (code 42)"))
        await manager.restart()
        XCTAssertEqual(manager.stopDetail, "engine failed (code 42)", "start failures keep their detail")
    }

    /// A declined screen-recording prompt keeps its SCStreamError code in the stop detail, and a start
    /// blocked by availability says so, so the two exports differ (review 2026-11-08).
    func testScreenRecordingNotAllowedKeepsItsDetail() async {
        capture.startError = SourceError(.screenRecordingNotAllowed, detail: "Declined (SCStreamError -3801) [picker]")
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.stopReason, .screenRecordingNotAllowed)
        XCTAssertEqual(manager.stopDetail, "Declined (SCStreamError -3801) [picker]")

        capture.startError = nil
        capture.availability = .unavailable(.screenRecordingNotAllowed)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.stopReason, .screenRecordingNotAllowed)
        XCTAssertEqual(manager.stopDetail, "Not started: the source was unavailable (screenRecordingNotAllowed) before start")
    }

    func testRuntimeAndResumeFailuresKeepTheirDetail() async {
        await manager.select(.microphone)
        mic.emit(.failed(.error("Audio services were reset")))
        await settle()
        XCTAssertEqual(manager.stopReason, .error("Audio services were reset"))
        XCTAssertEqual(manager.stopDetail, "Audio services were reset", "the failed(.error) path keeps its detail")

        await manager.select(.microphone)
        await manager.handle(.background)
        mic.resumeError = SourceError(.permissionDenied, detail: "permission revoked in Settings")
        await manager.handle(.foreground)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
        XCTAssertEqual(manager.stopDetail, "permission revoked in Settings", "a resume failure keeps its detail")
    }

    func testFailedNewAttemptWithoutDetailClearsTheOldDetail() async {
        await manager.select(.systemAppCapture)
        capture.emit(.endedBySystem("stopped (SCStreamError -3821)"))
        await settle()
        XCTAssertEqual(manager.stopDetail, "stopped (SCStreamError -3821)")
        capture.startError = SourceError(.cancelled)
        await manager.restart()
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertNil(manager.stopDetail, "a cancelled attempt must not inherit the previous session's detail")
    }

    func testInterruptionIgnoredForSystemCaptureButNotForMicrophone() async {
        await manager.select(.systemAppCapture)
        capture.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .waiting, "FR-051: no change while the stream delivers")

        await manager.select(.microphone)
        mic.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .interrupted)
        mic.emit(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.resumeCount, 1)
    }

    func testInterruptionWithoutResumeNeedsOneTapRestart() async {
        await manager.select(.microphone)
        mic.emit(.interruptionBegan)
        mic.emit(.interruptionEnded(shouldResume: false))
        await settle()
        XCTAssertEqual(manager.state, .interrupted)
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testBackgroundPausesMicAndForegroundResumes() async {
        await manager.select(.microphone)
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(mic.suspendCount, 1)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.resumeCount, 1)
    }

    func testLockIsHandledLikeBackground() async {
        await manager.select(.inAppPlayback)
        await manager.handle(.lock)
        XCTAssertEqual(manager.state, .paused)
        await manager.handle(.unlock)
        XCTAssertEqual(manager.state, .waiting)
    }

    func testBackgroundDoesNotTouchSystemCapture() async {
        await manager.select(.systemAppCapture)
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(capture.suspendCount, 0)
    }

    func testPermissionRevokedWhileBackgrounded() async {
        await manager.select(.microphone)
        await manager.handle(.background)
        mic.resumeError = SourceError(.permissionDenied)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
    }

    func testOutputRouteLostPausesUntilResume() async {
        await manager.select(.inAppPlayback)
        inApp.emit(.outputRouteLost)
        await settle()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .paused, "route-change pause needs the user's Resume")
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testMicrophoneLostStopsWithReason() async {
        await manager.select(.microphone)
        mic.emit(.failed(.microphoneUnavailable))
        await settle()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .microphoneUnavailable)
        XCTAssertFalse(mic.isRunning)
    }

    func testContentIdentityOnlyAfterVerifiedActiveAudio() async {
        capture.contentIdentity = "Some App"
        await manager.select(.systemAppCapture)
        XCTAssertNil(manager.displayedContentIdentity)
        playLoud(capture)
        XCTAssertEqual(manager.state, .active)
        XCTAssertEqual(manager.displayedContentIdentity, "Some App")
    }

    // MARK: - A new attempt starts from a clean slate (review F2)

    private func assertCleanSlate(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(manager.hasVerifiedActiveAudio, "verified flag: \(message)", file: file, line: line)
        XCTAssertEqual(manager.statistics, PCMSinkStatistics(), "statistics: \(message)", file: file, line: line)
        XCTAssertEqual(manager.levels, .silent, "levels: \(message)", file: file, line: line)
        XCTAssertEqual(manager.sessionSeconds, 0, "sessionSeconds: \(message)", file: file, line: line)
        XCTAssertFalse(manager.prolongedSilenceHint, "hint: \(message)", file: file, line: line)
        XCTAssertTrue(manager.formatsSeen.isEmpty, "formats: \(message)", file: file, line: line)
    }

    func testDeniedStartAfterVerifiedSessionClearsPreviousSession() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        XCTAssertTrue(manager.hasVerifiedActiveAudio)
        mic.startError = SourceError(.permissionDenied)
        await manager.select(.microphone)
        XCTAssertEqual(manager.activeMode, .microphone)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
        assertCleanSlate("after a denied start")
        XCTAssertEqual(manager.transitions, [StateTransition(atSeconds: 0, state: .notStarted, reason: "permissionDenied")])
    }

    func testCancelledPickerAfterVerifiedSessionClearsPreviousSession() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        XCTAssertGreaterThan(manager.statistics.sampleCount, 0)
        // An update the analyzer published during the old session, delivered late.
        let stale = manager.analyzer.step()
        XCTAssertTrue(stale.hasVerifiedActiveAudio)
        capture.startError = SourceError(.cancelled)
        let m = manager
        var duringPicker: (AudioState, StopReason?, Bool, Int, LevelMeter.Levels)?
        capture.onStart = {
            m.receiveForTesting(stale)   // published before the attempt: must be ignored
            duringPicker = (m.state, m.stopReason, m.hasVerifiedActiveAudio, m.statistics.sampleCount, m.levels)
        }
        await manager.select(.systemAppCapture)
        XCTAssertEqual(duringPicker?.0, .notStarted, "the old state is not shown while the picker is up")
        XCTAssertNil(duringPicker?.1)
        XCTAssertEqual(duringPicker?.2, false)
        XCTAssertEqual(duringPicker?.3, 0)
        XCTAssertEqual(duringPicker?.4, .silent)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        assertCleanSlate("after a cancelled picker")
        manager.receiveForTesting(stale)
        XCTAssertFalse(manager.hasVerifiedActiveAudio, "a stale update never restores the old session")
        await settle()   // any update the old session published is delivered by now
        assertCleanSlate("after late updates")
        XCTAssertEqual(manager.state, .notStarted)
    }

    func testUnavailableModeAfterVerifiedSessionClearsPreviousSession() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        capture.availability = .unavailable(.unsupportedOS)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.stopReason, .unsupportedOS)
        assertCleanSlate("after an unavailable mode")
    }

    // MARK: - Final transitions reach `transitions` (review F6)

    func testStopRecordsFinalTransition() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        clock.advance(1)
        await manager.stop()
        XCTAssertEqual(manager.transitions.map(\.state), [.waiting, .active, .stopped])
        XCTAssertEqual(manager.transitions.last?.atSeconds ?? 0, clock.now, accuracy: 1e-9)
        XCTAssertEqual(manager.sessionSeconds, clock.now, accuracy: 1e-9, "duration runs to the stop")
        await settle()
        XCTAssertEqual(manager.transitions.map(\.state), [.waiting, .active, .stopped], "no duplicates")
    }

    func testEndedBySystemRecordsFinalTransition() async {
        await manager.select(.systemAppCapture)
        playLoud(capture)
        capture.emit(.endedBySystem("stopped sharing"))
        await settle()
        XCTAssertEqual(manager.transitions.last?.state, .endedBySystem)
        XCTAssertEqual(manager.transitions.last?.reason, "endedBySystem")
        XCTAssertEqual(manager.transitions.map(\.state), [.waiting, .active, .endedBySystem])
    }

    func testFailureRecordsFinalTransitionWithReason() async {
        await manager.select(.microphone)
        mic.emit(.failed(.microphoneUnavailable))
        await settle()
        XCTAssertEqual(manager.transitions.map(\.state), [.waiting, .stopped])
        XCTAssertEqual(manager.transitions.last?.reason, "microphoneUnavailable")
    }

    func testFailedStartRecordsTransition() async {
        capture.startError = SourceError(.cancelled)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.transitions, [StateTransition(atSeconds: 0, state: .notStarted, reason: "cancelled")])
    }

    func testTransitionsStayInOrderWithLateUpdates() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)   // each step also publishes an update that arrives later
        await manager.stop()
        await settle()
        XCTAssertEqual(manager.transitions.map(\.state), [.waiting, .active, .stopped])
        XCTAssertEqual(manager.state, .stopped, "a late update never overwrites the final state")
    }

    // MARK: - Log entries use the session clock at handling time (review F7)

    func testLifecycleEntriesAreStampedWhenHandled() async {
        await manager.select(.microphone)
        clock.advance(1)
        await manager.handle(.background)
        clock.advance(2)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.lifecycleLog.map(\.event), ["background", "foreground"])
        XCTAssertEqual(manager.lifecycleLog[0].atSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(manager.lifecycleLog[1].atSeconds, 3, accuracy: 1e-9)
        // No entry is stamped before a transition it caused or that preceded it.
        let paused = manager.transitions.first { $0.state == .paused }
        XCTAssertEqual(paused?.atSeconds ?? -1, 1, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(manager.lifecycleLog[1].atSeconds, paused?.atSeconds ?? .infinity)
    }

    func testLifecycleStampsKeepAdvancingAfterStop() async {
        await manager.select(.inAppPlayback)
        clock.advance(2)
        await manager.stop()
        clock.advance(60)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.lifecycleLog.last?.event, "foreground")
        XCTAssertEqual(manager.lifecycleLog.last?.atSeconds ?? 0, 62, accuracy: 1e-9, "not frozen at the stop")
        XCTAssertEqual(manager.sessionSeconds, 2, accuracy: 1e-9, "duration is still the session's")
    }

    func testSourceEventsAreStampedWhenHandled() async {
        await manager.select(.microphone)
        clock.advance(1.25)
        mic.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.lifecycleLog.last?.event, "interruptionBegan")
        XCTAssertEqual(manager.lifecycleLog.last?.atSeconds ?? 0, 1.25, accuracy: 1e-9)
    }

    func testSessionClockResetsForEachAttempt() async {
        await manager.select(.microphone)
        clock.advance(10)
        await manager.handle(.background)
        let clock = self.clock
        inApp.onStart = { clock.advance(4) }   // the time a prompt would be on screen
        await manager.select(.inAppPlayback)
        XCTAssertTrue(manager.lifecycleLog.isEmpty, "the previous session's log is cleared")
        XCTAssertEqual(manager.transitions.first, StateTransition(atSeconds: 0, state: .waiting))
        clock.advance(0.5)
        await manager.handle(.lock)
        XCTAssertEqual(manager.lifecycleLog.last?.atSeconds ?? -1, 0.5, accuracy: 1e-9)
    }

    func testEventsHandledWhileStartIsPendingAreStampedZero() async {
        let m = manager
        let clock = self.clock
        clock.advance(7)
        capture.onStart = {
            clock.advance(3)
            // `handle` logs at once, then waits for the pending start before acting.
            Task { await m.handle(.background) }
            for _ in 0..<10 { await Task.yield() }
        }
        await manager.select(.systemAppCapture)
        await settle()
        XCTAssertEqual(manager.lifecycleLog.map(\.event), ["background"])
        XCTAssertEqual(manager.lifecycleLog.first?.atSeconds, 0)
        XCTAssertEqual(manager.transitions.first?.atSeconds, 0)
    }

    // MARK: - Session time starts when the source has started (review F8)

    func testStartToFirstAudioExcludesPickerTime() async {
        capture.onStart = { try? await Task.sleep(nanoseconds: 300_000_000) }   // picker on screen
        await manager.select(.systemAppCapture)
        capture.pushAudio(amplitude: 0.5, seconds: 0.01)
        manager.stepAnalysisForTesting()
        XCTAssertNotNil(manager.statistics.startToFirstAudioMs)
        XCTAssertLessThan(manager.statistics.startToFirstAudioMs ?? .infinity, 150,
                          "the 300 ms in the picker is not start-to-first-audio")
        XCTAssertLessThan(manager.statistics.firstSampleSeconds ?? .infinity, 0.15)
    }

    // MARK: - Commands cancel a start in flight (owner review 2026-11-08, ADR-0001 ruling 7)

    func testIsStartingOnlyWhileStartIsInFlight() async {
        XCTAssertFalse(manager.isStarting)
        let m = manager
        var during: Bool?
        capture.onStart = { during = m.isStarting }
        await manager.select(.systemAppCapture)
        XCTAssertEqual(during, true)
        XCTAssertFalse(manager.isStarting)
    }

    func testStopCancelsAStartThatNeverAnswers() async {
        capture.holdsStart = true
        let m = manager
        let select = Task { @MainActor in await m.select(.systemAppCapture) }
        await waitUntil { self.capture.isHoldingStart }
        let begin = Date()
        await manager.stop()
        await select.value
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1.0, "FR-007: stop within 1 s")
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertEqual(manager.stopDetail, "Start cancelled from the app before the source started")
        XCTAssertFalse(manager.isStarting)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(manager.transitions.last?.state, .notStarted)
    }

    func testChoosingAnotherSourceCancelsAWaitingStart() async {
        capture.holdsStart = true
        let m = manager
        let select = Task { @MainActor in await m.select(.systemAppCapture) }
        await waitUntil { self.capture.isHoldingStart }
        await manager.select(.microphone)
        await select.value
        XCTAssertEqual(manager.activeMode, .microphone)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertNil(manager.stopReason, "the cancelled attempt does not leak into the new session")
        XCTAssertNil(manager.stopDetail)
        XCTAssertTrue(mic.isRunning)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(fixture.runningCount, 1)
    }

    func testRestartCancelsAWaitingStartAndStartsAgain() async {
        capture.holdsStart = true
        let m = manager
        let select = Task { @MainActor in await m.select(.systemAppCapture) }
        await waitUntil { self.capture.isHoldingStart }
        capture.holdsStart = false   // the re-presented picker answers this time
        await manager.restart()
        await select.value
        XCTAssertEqual(capture.startCount, 2, "restart re-runs start, which re-presents the picker")
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertTrue(capture.isRunning)
        XCTAssertEqual(fixture.runningCount, 1)
    }

    func testSourceThatStartsDespiteTheCancelIsStoppedAgain() async {
        capture.holdsStart = true
        capture.startsAnywayAfterStop = true
        let m = manager
        let select = Task { @MainActor in await m.select(.systemAppCapture) }
        await waitUntil { self.capture.isHoldingStart }
        await manager.stop()
        await select.value
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertFalse(capture.isRunning, "a start that slipped past the cancel is stopped again")
        XCTAssertEqual(capture.stopCount, 2)
        XCTAssertEqual(fixture.runningCount, 0)
    }

    /// Review finding: Stop while Restart is still stopping the old source must cancel the
    /// restart before it presents the picker again.
    func testStopDuringRestartsStopCancelsTheRestart() async {
        await manager.select(.systemAppCapture)
        capture.stopDelayNanoseconds = 200_000_000
        let m = manager
        let restart = Task { @MainActor in await m.restart() }
        await waitUntil { self.capture.stopCount == 1 }
        let begin = Date()
        await manager.stop()
        await restart.value
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1.0, "FR-007: stop within 1 s")
        XCTAssertEqual(capture.startCount, 1, "the restart never presents the picker")
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertFalse(manager.isStarting)
        XCTAssertEqual(fixture.runningCount, 0)
    }

    /// Review finding: Restart then Stop, back to back, while a start waits on the picker.
    func testRestartThenStopWhileWaitingEndsCancelled() async {
        capture.holdsStart = true
        let m = manager
        let select = Task { @MainActor in await m.select(.systemAppCapture) }
        await waitUntil { self.capture.isHoldingStart }
        let restart = Task { @MainActor in await m.restart() }
        let stop = Task { @MainActor in await m.stop() }
        await select.value; await restart.value; await stop.value
        XCTAssertEqual(capture.startCount, 1, "the queued restart never presents the picker")
        XCTAssertFalse(capture.isHoldingStart)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertFalse(manager.isStarting)
        XCTAssertEqual(fixture.runningCount, 0)
    }

    // MARK: - Pause reasons end with the session (review F10)

    func testRouteLostThenStopHasNoStopReason() async {
        await manager.select(.inAppPlayback)
        inApp.emit(.outputRouteLost)
        await settle()
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
        await manager.stop()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertNil(manager.stopReason, "a user stop has no reason")
    }

    func testRouteLostThenFailingResumeReportsPlaybackFailure() async {
        await manager.select(.inAppPlayback)
        inApp.emit(.outputRouteLost)
        await settle()
        inApp.resumeError = SourceError(.inAppPlaybackFailed)
        await manager.resume()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .inAppPlaybackFailed)
        XCTAssertFalse(inApp.isRunning)
    }

    func testRouteLostThenEndedBySystemReportsEndedBySystem() async {
        await manager.select(.inAppPlayback)
        inApp.emit(.outputRouteLost)
        await settle()
        inApp.emit(.endedBySystem(nil))
        await settle()
        XCTAssertEqual(manager.state, .endedBySystem)
        XCTAssertEqual(manager.stopReason, .endedBySystem)
    }

    /// Lets queued event-handling tasks run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: - User pause (AUD-006-T10; AUD-006-R20 to R22)

    func testUserPauseShowsPausedWithoutAReasonAndSuspendsOnce() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        XCTAssertFalse(manager.isPausedByUser)
        await manager.pause()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertNil(manager.stopReason, "a user pause shows no banner")
        XCTAssertTrue(manager.isPausedByUser)
        XCTAssertEqual(inApp.suspendCount, 1)
        await manager.pause()
        XCTAssertEqual(inApp.suspendCount, 1, "pausing twice suspends once")
        // Audio arriving late does not make the state Active again (AUD-006-R20).
        playLoud(inApp)
        XCTAssertEqual(manager.state, .paused)
    }

    func testUserPauseSurvivesBackgroundForegroundLockAndUnlock() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        await manager.pause()
        for event in [AppLifecycleEvent.background, .foreground, .lock, .unlock, .background, .unlock, .foreground] {
            await manager.handle(event)
            XCTAssertEqual(manager.state, .paused, "\(event)")
        }
        XCTAssertEqual(inApp.resumeCount, 0, "only the user resumes a user pause (AUD-006-R21)")
        XCTAssertEqual(inApp.suspendCount, 1)
        XCTAssertTrue(manager.isPausedByUser)
    }

    func testResumeEndsAUserPause() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        await manager.pause()
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting, "Active has to be verified again after Play")
        XCTAssertFalse(manager.isPausedByUser)
        XCTAssertEqual(inApp.resumeCount, 1)
        playLoud(inApp)
        XCTAssertEqual(manager.state, .active)
        // A lifecycle pause afterwards resumes by itself again (unchanged, AUD-006-R22).
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .paused)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(inApp.resumeCount, 2)
    }

    func testUserPauseAppliesToInAppPlaybackOnly() async {
        await manager.select(.microphone)
        playLoud(mic)
        await manager.pause()
        XCTAssertEqual(manager.state, .active)
        XCTAssertEqual(mic.suspendCount, 0)
        XCTAssertFalse(manager.isPausedByUser)
        await manager.select(.systemAppCapture)
        playLoud(capture)
        await manager.pause()
        XCTAssertEqual(manager.state, .active)
        XCTAssertEqual(capture.suspendCount, 0)
        XCTAssertFalse(manager.isPausedByUser)
        // And with no session at all.
        await manager.stop()
        await manager.pause()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertFalse(manager.isPausedByUser)
    }

    func testUserPauseDuringAnInterruptionIsNotResumedWhenItEnds() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        inApp.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .interrupted)
        await manager.pause()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertNil(manager.stopReason)
        inApp.emit(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(inApp.resumeCount, 0)
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testUserPauseAfterARouteLossClearsTheReasonAndStaysPaused() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        inApp.emit(.outputRouteLost)
        await settle()
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
        await manager.pause()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertNil(manager.stopReason)
        XCTAssertTrue(manager.isPausedByUser)
        await manager.handle(.background)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(inApp.resumeCount, 0)
    }

    func testStopFailureEndBySystemAndANewSessionClearTheUserPause() async {
        await manager.select(.inAppPlayback)
        await manager.pause()
        await manager.stop()
        XCTAssertFalse(manager.isPausedByUser)

        await manager.select(.inAppPlayback)
        await manager.pause()
        inApp.emit(.failed(.inAppPlaybackFailed))
        await settle()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertFalse(manager.isPausedByUser)

        await manager.select(.inAppPlayback)
        await manager.pause()
        inApp.emit(.endedBySystem(nil))
        await settle()
        XCTAssertFalse(manager.isPausedByUser)

        await manager.select(.inAppPlayback)
        await manager.pause()
        await manager.select(.inAppPlayback)
        XCTAssertFalse(manager.isPausedByUser)
        XCTAssertEqual(manager.state, .waiting)
        await manager.pause()
        await manager.restart()
        XCTAssertFalse(manager.isPausedByUser)
        XCTAssertEqual(manager.state, .waiting)
    }
}
