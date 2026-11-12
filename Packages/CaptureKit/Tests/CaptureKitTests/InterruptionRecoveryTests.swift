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
    }

    private func item(_ id: String) -> PlaybackItem {
        PlaybackItem(id: id, title: "Track \(id)", durationSeconds: 60, track: .file(URL(fileURLWithPath: "/library/assets/\(id).wav")))
    }

    private func makeRig() -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let mic = FakeAudioSource(mode: .microphone)
        let manager = CaptureManager(sources: [source, mic], runsAnalysisTimer: false)
        return Rig(backend: backend, source: source, mic: mic, manager: manager,
                   transport: PlaybackTransport(manager: manager, source: source))
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
