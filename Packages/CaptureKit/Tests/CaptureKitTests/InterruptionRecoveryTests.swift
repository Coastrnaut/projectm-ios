// InterruptionRecoveryTests.swift — CaptureManager and the transport through interruptions, lost
// routes and the app lifecycle, on a scripted backend (AUD-014-T06, T07, T08; AUD-014-R2 to R9,
// R11, R13, R14, R20; S4, S5). No audio is involved, so this also runs where AVFAudio does not
// exist. Every case counts the backend's resumes: a resume is the only way sound can start.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class InterruptionRecoveryTests: XCTestCase {
    private struct Rig {
        let backend: FakePlaybackBackend
        let source: InAppPlaybackSource
        let mic: FakeAudioSource
        let manager: CaptureManager
        let transport: PlaybackTransport
        /// The manager's lifecycle clock (suspension-notice window), frozen unless a test advances it.
        let clock: ManualClock
    }

    private func item(_ id: String) -> PlaybackItem {
        PlaybackItem(id: id, title: "Track \(id)", durationSeconds: 60, track: .file(URL(fileURLWithPath: "/library/assets/\(id).wav")))
    }

    private func makeRig() -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let mic = FakeAudioSource(mode: .microphone)
        let manager = CaptureManager(sources: [source, mic], runsAnalysisTimer: false)
        let clock = ManualClock()
        manager.lifecycleClock = { clock.now }
        return Rig(backend: backend, source: source, mic: mic, manager: manager,
                   transport: PlaybackTransport(manager: manager, source: source), clock: clock)
    }

    /// A rig playing track a of [a, b], 10 seconds in.
    private func playing() async -> Rig {
        let rig = makeRig()
        rig.transport.prepare(order: ListPlayOrder([item("a"), item("b")]), current: item("a"))
        await rig.manager.select(.inAppPlayback)
        rig.backend.positionSeconds = 10
        XCTAssertEqual(rig.transport.state, .playing)
        return rig
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private func send(_ rig: Rig, _ events: SourceEvent...) async {
        for event in events {
            rig.backend.onEvent?(event)
            await settle()
        }
    }

    private let began = SourceEvent.interruptionBegan
    private let endedResume = SourceEvent.interruptionEnded(shouldResume: true)
    private let endedNoResume = SourceEvent.interruptionEnded(shouldResume: false)

    private func assertOnHold(_ rig: Rig, state: AudioState = .interrupted, reason: StopReason? = .interrupted,
                              resumes: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rig.manager.state, state, file: file, line: line)
        XCTAssertEqual(rig.manager.stopReason, reason, file: file, line: line)
        XCTAssertNotEqual(rig.transport.state, .playing, file: file, line: line)
        XCTAssertEqual(rig.backend.resumeCount, resumes, "nothing may start by itself", file: file, line: line)
        XCTAssertTrue(rig.transport.isAvailable, "the session stays", file: file, line: line)
    }

    // MARK: - User Story 1: eligible playback resumes

    func testEligiblePlaybackResumesOnceWhenIOSIndicatesIt() async {
        let rig = await playing()
        await send(rig, began)
        assertOnHold(rig)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.transport.position.seconds, 10)

        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.manager.state, .waiting, "Active audio must be verified again (Constitution IV)")
        XCTAssertFalse(rig.manager.hasVerifiedActiveAudio)
        XCTAssertNil(rig.manager.stopReason)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current?.id, "a")
        XCTAssertEqual(rig.backend.seekTargets, [], "the position is the backend's held one; nothing seeks")
        XCTAssertEqual(rig.backend.replaceRequests, [])
    }

    // MARK: - User Story 2: nothing starts that the user did not ask for

    func testAUserPauseBeforeTheInterruptionIsNotResumed() async {
        let rig = await playing()
        await rig.transport.pause()
        await send(rig, began, endedResume)
        assertOnHold(rig, state: .paused, reason: nil)
        XCTAssertTrue(rig.manager.isPausedByUser)
        XCTAssertEqual(rig.transport.state, .paused)
    }

    func testStopPlaybackBeforeTheInterruptionStaysStopped() async {
        let rig = await playing()
        await rig.transport.stop()
        await send(rig, began, endedResume)
        assertOnHold(rig, state: .paused, reason: nil)
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.transport.position.seconds, 0)
    }

    func testEveryUserTransportActionDuringTheInterruptionCancelsTheResume() async {
        let actions: [(String, (Rig) async -> Void)] = [
            ("pause", { await $0.transport.pause() }),
            ("stop", { await $0.transport.stop() }),
            ("seek", { $0.transport.seek(to: 30) }),
            ("next", { await $0.transport.next() }),
            ("previous", { await $0.transport.previous() }),
        ]
        for (name, action) in actions {
            let rig = await playing()
            await send(rig, began)
            await action(rig)
            await send(rig, endedResume)
            XCTAssertEqual(rig.backend.resumeCount, 0, name)
            XCTAssertNotEqual(rig.transport.state, .playing, name)
            XCTAssertTrue(rig.transport.isAvailable, name)
            switch name {
            case "pause": XCTAssertEqual(rig.transport.state, .paused, name)
            case "stop": XCTAssertEqual(rig.transport.state, .stopped, name)
            case "seek":
                XCTAssertEqual(rig.transport.position.seconds, 30, name)
                XCTAssertEqual(rig.manager.state, .interrupted, "FR-051: still Interrupted, with Play available")
            case "next": XCTAssertEqual(rig.transport.current?.id, "b", name)
            default: XCTAssertEqual(rig.backend.seekTargets, [0], "previous after 3 s restarts the track")
            }
            await rig.transport.play()
            XCTAssertEqual(rig.backend.resumeCount, 1, "\(name): Play continues, once")
            XCTAssertEqual(rig.transport.state, .playing, name)
        }
    }

    func testWithoutAResumeIndicationItStaysInterruptedAndPlayContinues() async {
        for events in [[began, endedNoResume], [began]] {
            let rig = await playing()
            for event in events { await send(rig, event) }
            assertOnHold(rig)
            XCTAssertEqual(rig.transport.state, .paused)
            await rig.transport.play()
            XCTAssertEqual(rig.backend.resumeCount, 1)
            XCTAssertEqual(rig.manager.state, .waiting)
            XCTAssertEqual(rig.transport.current?.id, "a")
        }
    }

    func testALostOutputDuringTheInterruptionCancelsTheResume() async {
        let rig = await playing()
        await send(rig, began, .outputRouteLost)
        assertOnHold(rig)
        await send(rig, endedResume)
        assertOnHold(rig, state: .paused, reason: .audioRouteChanged)
        await rig.manager.resume()                    // the banner's Resume
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.manager.state, .waiting)
    }

    func testAnInterruptionWhilePausedByALostOutputChangesNothing() async {
        let rig = await playing()
        await send(rig, .outputRouteLost)
        assertOnHold(rig, state: .paused, reason: .audioRouteChanged)
        await send(rig, began, endedResume)
        assertOnHold(rig, state: .paused, reason: .audioRouteChanged)
    }

    func testEndedWithoutBeganChangesNothing() async {
        let rig = await playing()
        await send(rig, endedResume)
        XCTAssertEqual(rig.manager.state, .waiting)
        XCTAssertEqual(rig.backend.resumeCount + rig.backend.pauseCount, 0)

        await rig.transport.pause()
        await send(rig, endedResume)
        assertOnHold(rig, state: .paused, reason: nil)
    }

    func testEndedBeforeBeganLeavesTheInterruptionOpenUntilItsOwnEnd() async {
        let rig = await playing()
        await send(rig, endedResume, began)
        assertOnHold(rig)
        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.state, .playing)
    }

    func testADuplicateBeganIsOneInterruptionAndADuplicateEndResumesOnce() async {
        let rig = await playing()
        await send(rig, began, began)
        assertOnHold(rig)
        await send(rig, endedResume, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.manager.state, .waiting)
    }

    func testASecondInterruptionCannotResumeWhatTheFirstLeftOnHold() async {
        let rig = await playing()
        await send(rig, began, endedNoResume, began, endedResume)
        assertOnHold(rig)
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1)
    }

    func testTwoInterruptionsBackToBackEachResumeOnce() async {
        let rig = await playing()
        await send(rig, began, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        await send(rig, began)
        assertOnHold(rig, resumes: 1)
        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 2)
        XCTAssertEqual(rig.transport.state, .playing)
    }

    func testAnInterruptionRightAfterATrackChangeKeepsTheNewTrack() async {
        let rig = await playing()
        rig.source.loopsCurrentTrack = false
        rig.backend.onTrackEnded?()                   // a ended while playing: b follows
        await settle()
        XCTAssertEqual(rig.transport.current?.id, "b")
        await send(rig, began, endedResume)
        XCTAssertEqual(rig.transport.current?.id, "b", "not skipped, not repeated")
        XCTAssertEqual(rig.backend.replaceRequests.count, 1)
        XCTAssertEqual(rig.backend.resumeCount, 1)
    }

    func testNoEventResumesASessionTheUserLeft() async {
        let rig = await playing()
        await send(rig, began)
        let stale = rig.backend.onEvent
        await rig.manager.stop()                      // Stop: back to the source chooser
        stale?(endedResume)
        await settle()
        XCTAssertEqual(rig.manager.state, .stopped)
        XCTAssertEqual(rig.backend.resumeCount + rig.backend.callsAfterStop, 0)

        await rig.manager.select(.microphone)
        stale?(endedResume)
        stale?(.outputRouteLost)
        await settle()
        XCTAssertEqual(rig.manager.state, .waiting, "the old session's events do not reach Microphone")
        XCTAssertEqual(rig.mic.resumeCount + rig.mic.suspendCount, 0)
        XCTAssertEqual(rig.backend.resumeCount + rig.backend.callsAfterStop, 0)
    }

    func testANewSessionForgetsTheOldInterruption() async {
        let rig = await playing()
        await send(rig, began)
        await rig.manager.stop()
        await rig.manager.select(.inAppPlayback)
        await send(rig, endedResume)
        XCTAssertEqual(rig.manager.state, .waiting)
        XCTAssertEqual(rig.backend.resumeCount, 0, "the new session was never interrupted")
        await rig.manager.handle(.background)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1, "FR-050 applies unchanged")
    }

    func testAfterFiveStopsAndStartsOneInterruptionResumesExactlyOnce() async {
        let rig = await playing()
        for _ in 0..<5 {
            await rig.manager.stop()
            await rig.manager.select(.inAppPlayback)
        }
        await send(rig, began, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.backend.pauseCount, 0, "the manager does not suspend for an interruption; the backend holds itself")
        XCTAssertEqual(rig.manager.state, .waiting)
    }

    // MARK: - User Story 3: the app lifecycle around an interruption

    func testReturningDuringAnOpenInterruptionDoesNotResumeUntilIOSIndicatesIt() async {
        let rig = await playing()
        await send(rig, began)
        await rig.manager.handle(.background)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.manager.state, .waiting)
        XCTAssertNil(rig.manager.stopReason)
    }

    func testAResumeIndicatedInTheBackgroundWaitsForTheForeground() async {
        for (leave, back) in [(AppLifecycleEvent.background, AppLifecycleEvent.foreground), (.lock, .unlock)] {
            let rig = await playing()
            await send(rig, began)
            await rig.manager.handle(leave)
            await send(rig, endedResume)
            assertOnHold(rig, state: .paused, reason: .interrupted)
            await rig.manager.handle(back)
            XCTAssertEqual(rig.backend.resumeCount, 1, "\(leave)")
            XCTAssertEqual(rig.transport.state, .playing, "\(leave)")
        }
    }

    func testNoResumeIndicationInTheBackgroundStaysOnHoldAfterTheReturn() async {
        let rig = await playing()
        await send(rig, began)
        await rig.manager.handle(.background)
        await send(rig, endedNoResume)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1)
    }

    func testAnInterruptionThatBeginsInTheBackgroundBlocksTheForegroundResume() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.clock.advance(CaptureManager.suspensionNoticeWindow + 0.5)   // a call while away, not the suspension notice
        await send(rig, began)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1)
    }

    func testALostOutputInTheBackgroundBlocksTheForegroundResume() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        await send(rig, .outputRouteLost)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .audioRouteChanged)
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertNil(rig.manager.stopReason)
    }

    func testARefusedPlayDuringAnOpenInterruptionKeepsTheSession() async {
        let rig = await playing()
        await send(rig, began)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed)
        await rig.transport.play()
        XCTAssertEqual(rig.backend.refusedResumeCount, 1)
        assertOnHold(rig)
        XCTAssertEqual(rig.transport.current?.id, "a")
        XCTAssertEqual(rig.transport.position.seconds, 10)
        XCTAssertEqual(rig.backend.stopCount, 0)

        rig.backend.resumeError = nil
        await send(rig, endedResume)
        XCTAssertEqual(rig.backend.resumeCount, 1, "pressing Play is not a reason to stay silent")
        XCTAssertEqual(rig.transport.state, .playing)
    }

    func testARefusedPlayOfStoppedPlaybackDuringAnInterruptionStaysStopped() async {
        let rig = await playing()
        await rig.transport.stop()
        await send(rig, began)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertTrue(rig.transport.isAvailable)
        XCTAssertEqual(rig.transport.position.seconds, 0)
    }

    func testARefusedPlayWithNoOpenInterruptionEndsAsFailed() async {
        for events in [[SourceEvent](), [began, endedNoResume]] {
            let rig = await playing()
            if events.isEmpty { await rig.transport.pause() }
            for event in events { await send(rig, event) }
            rig.backend.resumeError = SourceError(.inAppPlaybackFailed)
            await rig.transport.play()
            XCTAssertEqual(rig.manager.state, .stopped)
            XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
            XCTAssertFalse(rig.transport.isAvailable)
        }
    }

    func testWithoutAnInterruptionTheLifecycleIsUnchanged() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertNil(rig.manager.stopReason)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1)

        await rig.transport.pause()
        await rig.manager.handle(.background)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1, "AUD-006-R21: a user pause is not resumed")
    }

    // MARK: - QA-011 D2 2026-11-23: the audio session while away (AUD-015-R2, R10; AUD-014-R6, R8)

    /// D2 (iPadOS 27.2.1): after background, a rotation while away and the return, playback stayed
    /// "Paused · Interrupted": the suspended app's still-active session was interrupted and iOS
    /// never ended it. Going away now releases the session, so the plain round trip resumes.
    func testGoingAwayReleasesTheAudioSessionAndThePlainReturnResumes() async {
        for (leave, back) in [(AppLifecycleEvent.background, AppLifecycleEvent.foreground), (.lock, .unlock)] {
            let rig = await playing()
            await rig.manager.handle(leave)
            XCTAssertEqual(rig.backend.pauseCount, 1, "\(leave)")
            XCTAssertEqual(rig.backend.releaseCount, 1, "\(leave): no active session while away")
            XCTAssertTrue(rig.backend.sessionReleased)
            XCTAssertEqual(rig.manager.state, .paused)
            XCTAssertNil(rig.manager.stopReason)
            await rig.manager.handle(back)
            XCTAssertEqual(rig.backend.resumeCount, 1, "\(leave): FR-050 resumes on the return")
            XCTAssertFalse(rig.backend.sessionReleased, "the resume activates it again")
            XCTAssertEqual(rig.transport.state, .playing)
            XCTAssertEqual(rig.transport.position.seconds, 10)
        }
    }

    func testAUserPauseKeepsItsSessionAndIsNotReleasedOrResumed() async {
        let rig = await playing()
        await rig.transport.pause()
        await rig.manager.handle(.background)
        XCTAssertEqual(rig.backend.releaseCount, 0, "only the lifecycle hold releases the session")
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 0, "AUD-006-R21")
    }

    /// A call that began while the app was away: its interruption never reaches the released
    /// session, and iOS refuses the activation at the return. Playback stays on hold as an open
    /// interruption ("Interrupted", track and position kept) instead of failing; Play continues.
    func testARefusedSessionAtTheReturnStaysOnHoldAsInterrupted() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed, detail: SourceError.audioSessionRefusedDetail)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.refusedResumeCount, 1)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        XCTAssertEqual(rig.backend.stopCount, 0)
        XCTAssertEqual(rig.transport.current?.id, "a")
        XCTAssertEqual(rig.transport.position.seconds, 10)

        await rig.manager.handle(.background)         // away and back again: still on hold, no retry loop
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.refusedResumeCount, 1)
        assertOnHold(rig, state: .paused, reason: .interrupted)

        rig.backend.resumeError = nil
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertNil(rig.manager.stopReason)
    }

    /// QA-011 D2 r14 (2026-11-23): with the session released, the resume at "will enter foreground" can be refused
    /// because the app is still in the background state then; it is tried again when the app becomes active.
    func testARefusedReturnIsRetriedWhenTheAppBecomesActive() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed, detail: SourceError.audioSessionRefusedDetail)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        rig.backend.resumeError = nil
        await rig.manager.noteAppBecameActive()
        XCTAssertEqual(rig.backend.resumeCount, 1, "resumed once the app is active")
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertNil(rig.manager.stopReason)
        XCTAssertEqual(rig.transport.position.seconds, 10)
        await rig.manager.noteAppBecameActive()
        XCTAssertEqual(rig.backend.resumeCount, 1, "one retry per refusal")
    }

    func testARefusalWhenActiveTooStaysOnHoldAndPlayContinues() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed, detail: SourceError.audioSessionRefusedDetail)
        await rig.manager.handle(.foreground)
        await rig.manager.noteAppBecameActive()
        XCTAssertEqual(rig.backend.refusedResumeCount, 2)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        XCTAssertEqual(rig.backend.stopCount, 0, "the session stays (AUD-014-R8)")
        rig.backend.resumeError = nil
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.state, .playing)
    }

    func testNoRetryWhenActiveAfterTheUserOrIOSTookOver() async {
        for takeOver in ["pause", "interruption", "seek", "routeLost"] {
            let rig = await playing()
            await rig.manager.handle(.background)
            rig.backend.resumeError = SourceError(.inAppPlaybackFailed, detail: SourceError.audioSessionRefusedDetail)
            await rig.manager.handle(.foreground)
            rig.backend.resumeError = nil
            switch takeOver {
            case "pause": await rig.transport.pause()
            case "interruption": await send(rig, began)
            case "seek": rig.manager.noteUserTransportChange()
            default: await send(rig, .outputRouteLost)
            }
            await rig.manager.noteAppBecameActive()
            XCTAssertEqual(rig.backend.resumeCount, 0, "\(takeOver): nothing starts by itself")
            XCTAssertNotEqual(rig.transport.state, .playing, "\(takeOver)")
        }
    }

    func testBecomingActiveWithoutARefusedReturnChangesNothing() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        await rig.manager.noteAppBecameActive()       // still away: nothing
        XCTAssertEqual(rig.backend.resumeCount, 0)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        await rig.manager.noteAppBecameActive()
        XCTAssertEqual(rig.backend.resumeCount, 1)

        await rig.transport.pause()
        await rig.manager.noteAppBecameActive()
        XCTAssertEqual(rig.backend.resumeCount, 1, "AUD-006-R21: a user pause is not resumed")
    }

    /// The trace the device tests print (`-uitestSessionLog`): lifecycle, hold, refusal, retry, in order.
    func testTheSessionTraceRecordsTheReturnDecisions() async {
        let trace = AudioSessionTrace.shared
        trace.reset()
        trace.isEnabled = true
        defer { trace.isEnabled = false; trace.reset() }
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed, detail: SourceError.audioSessionRefusedDetail)
        await rig.manager.handle(.foreground)
        rig.backend.resumeError = nil
        await rig.manager.noteAppBecameActive()
        let text = trace.entries.joined(separator: "\n")
        let expected = ["lifecycle background", "hold: suspending while away", "lifecycle foreground",
                        "resume: refused (return) detail=\(SourceError.audioSessionRefusedDetail)", "active: retry=1",
                        "resume: ok (return)"]
        var from = text.startIndex
        for step in expected {
            guard let range = text.range(of: step, range: from..<text.endIndex) else {
                XCTFail("missing or out of order: \(step)\n\(text)")
                return
            }
            from = range.upperBound
        }
        XCTAssertTrue(trace.entries.allSatisfy { $0.hasPrefix("t=") })

        trace.isEnabled = false
        let count = trace.entries.count
        await rig.manager.handle(.background)
        XCTAssertEqual(trace.entries.count, count, "nothing is recorded while off")
    }

    func testAnotherResumeFailureAtTheReturnStillEndsAsFailed() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.backend.resumeError = SourceError(.inAppPlaybackFailed)     // the engine, not the session
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.manager.state, .stopped)
        XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
        XCTAssertFalse(rig.transport.isAvailable)
    }

    // MARK: - QA-011 D2 2026-11-23: the suspension notice (AUD-014, AUD-015 Clarifications)

    /// D2 r15 trace: "session.deactivate ok" at 53.51, "notice interruption type=1 reason=0" at 53.52 (app=background),
    /// never an end; the return stayed "Interrupted". A plain "began" within the window after the away hold opens no
    /// interruption, and the return resumes.
    func testABeganJustAfterTheAwayHoldIsTheSuspensionNoticeAndTheReturnResumes() async {
        for (leave, back) in [(AppLifecycleEvent.background, AppLifecycleEvent.foreground), (.lock, .unlock)] {
            let rig = await playing()
            await rig.manager.handle(leave)
            rig.clock.advance(0.01)
            await send(rig, began)
            XCTAssertEqual(rig.manager.state, .paused, "\(leave)")
            XCTAssertNil(rig.manager.stopReason, "\(leave): not shown as Interrupted")
            await rig.manager.handle(back)
            XCTAssertEqual(rig.backend.resumeCount, 1, "\(leave): AUD-015 resumes on the return")
            XCTAssertEqual(rig.transport.state, .playing)
            XCTAssertEqual(rig.transport.position.seconds, 10)
        }
    }

    func testTheWindowEdges() async {
        for (after, resumes) in [(CaptureManager.suspensionNoticeWindow - 0.01, 1), (CaptureManager.suspensionNoticeWindow + 0.01, 0),
                                 (1.5, 0)] {
            let rig = await playing()
            await rig.manager.handle(.background)
            rig.clock.advance(after)
            await send(rig, began)
            await rig.manager.handle(.foreground)
            XCTAssertEqual(rig.backend.resumeCount, resumes, "began \(after) s after the away hold")
            if resumes == 0 { assertOnHold(rig, state: .paused, reason: .interrupted) }
        }
    }

    func testABeganWhileActiveIsAlwaysAnInterruption() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        await send(rig, began)                        // within the window of the old hold, but the app is back
        assertOnHold(rig, resumes: 1)
    }

    func testAnExternalBeganJustAfterTheAwayHoldStillOpensTheInterruption() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        await send(rig, .interruptionBeganExternal)
        await rig.manager.handle(.foreground)
        assertOnHold(rig, state: .paused, reason: .interrupted)
    }

    func testAnInterruptionThatBeginsAndEndsWhileAwayResumesAsBefore() async {
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.clock.advance(2)
        await send(rig, began, endedResume)
        assertOnHold(rig, state: .paused, reason: .interrupted)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.state, .playing)

        // The same within the window: the notice opened nothing, the end changes nothing, the return resumes.
        let quick = await playing()
        await quick.manager.handle(.background)
        await send(quick, began, endedResume)
        await quick.manager.handle(.foreground)
        XCTAssertEqual(quick.backend.resumeCount, 1)
        XCTAssertEqual(quick.transport.state, .playing)
    }

    func testTheSuspensionNoticeIsRecordedInTheTrace() async {
        let trace = AudioSessionTrace.shared
        trace.reset()
        trace.isEnabled = true
        defer { trace.isEnabled = false; trace.reset() }
        let rig = await playing()
        await rig.manager.handle(.background)
        rig.clock.advance(0.01)
        await send(rig, began)
        XCTAssertTrue(trace.entries.contains { $0.contains("suspension notice: 10 ms after the away hold, no interruption opened") },
                      trace.entries.joined(separator: "\n"))
    }

    // MARK: - Microphone is unchanged (AUD-014-R9, S5)

    func testMicrophoneKeepsItsFeature001Behavior() async {
        let rig = makeRig()
        await rig.manager.select(.microphone)
        rig.mic.emit(began)
        await settle()
        XCTAssertEqual(rig.manager.state, .interrupted)
        await rig.manager.handle(.background)
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertEqual(rig.manager.stopReason, .interrupted, "as before this feature: the classifier's last reason")
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.mic.resumeCount, 1, "FR-050 for Microphone, as before")

        rig.mic.emit(began)
        rig.mic.emit(endedNoResume)
        await settle()
        XCTAssertEqual(rig.manager.state, .interrupted)
        XCTAssertEqual(rig.mic.resumeCount, 1)
        await rig.manager.resume()                    // FR-051: one tap continues
        XCTAssertEqual(rig.manager.state, .waiting)
        XCTAssertEqual(rig.mic.resumeCount, 2)
    }
}
