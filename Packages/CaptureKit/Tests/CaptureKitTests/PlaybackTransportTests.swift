// PlaybackTransportTests.swift — the transport's state, order rules, lifecycle and failures, on a
// scripted backend (AUD-006-T21, T23; AUD-006-R1 to R7, R14 to R23, R29; S4, S5). No audio is
// involved, so this also runs where AVFAudio does not exist.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class PlaybackTransportTests: XCTestCase {
    /// An order that ends: nothing follows the last item (what AUD-004's repeat "off" will do).
    private final class EndingOrder: PlayOrder {
        let items: [PlaybackItem]
        init(_ items: [PlaybackItem]) { self.items = items }
        func item(after id: PlaybackItem.ID) -> PlaybackItem? {
            guard let index = items.firstIndex(where: { $0.id == id }), index + 1 < items.count else { return nil }
            return items[index + 1]
        }
        func item(before id: PlaybackItem.ID) -> PlaybackItem? {
            guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
            return items[index - 1]
        }
    }

    private struct Rig {
        let backend: FakePlaybackBackend
        let source: InAppPlaybackSource
        let mic: FakeAudioSource
        let capture: FakeAudioSource
        let manager: CaptureManager
        let transport: PlaybackTransport
    }

    private func item(_ id: String) -> PlaybackItem {
        PlaybackItem(id: id, title: "Track \(id)", durationSeconds: 60, track: .file(URL(fileURLWithPath: "/library/assets/\(id).wav")))
    }
    private var a: PlaybackItem { item("a") }
    private var b: PlaybackItem { item("b") }
    private var c: PlaybackItem { item("c") }

    private func makeRig() -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let mic = FakeAudioSource(mode: .microphone)
        let capture = FakeAudioSource(mode: .systemAppCapture)
        let manager = CaptureManager(sources: [source, mic, capture], runsAnalysisTimer: false)
        return Rig(backend: backend, source: source, mic: mic, capture: capture, manager: manager,
                   transport: PlaybackTransport(manager: manager, source: source))
    }

    /// A rig playing `current` out of `items`.
    private func playing(_ items: [PlaybackItem], current: PlaybackItem) async -> Rig {
        let rig = makeRig()
        rig.transport.prepare(order: ListPlayOrder(items), current: current)
        await rig.manager.select(.inAppPlayback)
        return rig
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    // MARK: - Availability (AUD-006-R1, R7)

    func testUnavailableWithoutAnInAppPlaybackSessionAndThenEveryCommandIsANoOp() async {
        let rig = makeRig()
        rig.transport.prepare(order: ListPlayOrder([a, b]), current: a)
        func assertInert(_ label: String) async {
            XCTAssertFalse(rig.transport.isAvailable, label)
            XCTAssertEqual(rig.transport.state, .stopped, label)
            await rig.transport.play()
            await rig.transport.pause()
            await rig.transport.stop()
            await rig.transport.togglePlayPause()
            rig.transport.seek(to: 10)
            await rig.transport.next()
            await rig.transport.previous()
            XCTAssertEqual(rig.backend.pauseCount + rig.backend.resumeCount + rig.backend.seekTargets.count
                           + rig.backend.replaceRequests.count + rig.backend.callsAfterStop, 0, label)
            XCTAssertEqual(rig.transport.current?.id, "a", label)
        }
        await assertInert("before any session")
        XCTAssertEqual(rig.transport.position, PlaybackPosition(seconds: 0, durationSeconds: 60), "the prepared item's duration")

        await rig.manager.select(.microphone)
        await assertInert("Microphone")
        XCTAssertEqual(rig.mic.suspendCount, 0, "the transport never acts on Microphone")
        XCTAssertEqual(rig.manager.state, .waiting)

        await rig.manager.select(.systemAppCapture)
        await assertInert("System/App Capture")
        XCTAssertEqual(rig.capture.suspendCount, 0)
        XCTAssertEqual(rig.capture.stopCount, 0)
    }

    func testUnavailableAfterStopToTheChooserAndAfterAFailure() async {
        let rig = await playing([a, b], current: a)
        XCTAssertTrue(rig.transport.isAvailable)
        await rig.manager.stop()
        XCTAssertFalse(rig.transport.isAvailable)
        XCTAssertEqual(rig.transport.state, .stopped)
        await rig.transport.play()
        rig.transport.seek(to: 5)
        XCTAssertEqual(rig.backend.resumeCount + rig.backend.seekTargets.count + rig.backend.callsAfterStop, 0)

        await rig.manager.select(.inAppPlayback)
        XCTAssertTrue(rig.transport.isAvailable)
        rig.backend.onEvent?(.failed(.inAppPlaybackFailed))
        await settle()
        XCTAssertFalse(rig.transport.isAvailable)
    }

    func testASourceThatReplacedThisOneIsNotControlled() async {
        // StatusUITests replace the In-App Playback source with a scripted fake.
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let other = FakeAudioSource(mode: .inAppPlayback)
        let manager = CaptureManager(sources: [other], runsAnalysisTimer: false)
        let transport = PlaybackTransport(manager: manager, source: source)
        transport.prepare(order: ListPlayOrder([a]), current: a)
        await manager.select(.inAppPlayback)
        XCTAssertFalse(transport.isAvailable)
        await transport.pause()
        XCTAssertEqual(other.suspendCount, 0)
        XCTAssertEqual(manager.state, .waiting)
    }

    // MARK: - Play, pause, stop (AUD-006-R3 to R7, R20)

    func testANewSessionPlaysThePreparedTrackFromTheStart() async {
        let rig = await playing([a, b, c], current: b)
        XCTAssertEqual(rig.backend.startedTracks, [b.track])
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, b)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        XCTAssertEqual(rig.transport.position.durationSeconds, 60)
        XCTAssertEqual(rig.manager.activeMode, .inAppPlayback)
    }

    func testPauseAndPlay() async {
        let rig = await playing([a, b], current: a)
        rig.backend.positionSeconds = 12.5
        await rig.transport.pause()
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertNil(rig.manager.stopReason)
        XCTAssertEqual(rig.backend.pauseCount, 1)
        XCTAssertEqual(rig.transport.position.seconds, 12.5, "the position holds")
        await rig.transport.pause()
        XCTAssertEqual(rig.backend.pauseCount, 1, "Pause while paused does nothing")

        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.manager.state, .waiting, "Active only after new audio is verified")
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.backend.seekTargets, [], "Play continues where it was")
        await rig.transport.play()
        XCTAssertEqual(rig.backend.resumeCount, 1, "Play while playing does nothing")
    }

    func testStopPlaybackGoesToZeroAndKeepsTheSession() async {
        let rig = await playing([a, b], current: a)
        rig.backend.positionSeconds = 30
        await rig.transport.stop()
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertTrue(rig.transport.isAvailable, "the session stays open")
        XCTAssertEqual(rig.manager.state, .paused, "the source status reads Paused, not Stopped")
        XCTAssertEqual(rig.manager.activeMode, .inAppPlayback)
        XCTAssertEqual(rig.backend.pauseCount, 1)
        XCTAssertEqual(rig.backend.seekTargets, [0])
        XCTAssertEqual(rig.transport.position.seconds, 0)
        XCTAssertEqual(rig.backend.stopCount, 0)
        await rig.transport.stop()
        await rig.transport.pause()
        XCTAssertEqual(rig.backend.pauseCount, 1)
        XCTAssertEqual(rig.backend.seekTargets, [0], "Stop while stopped does nothing")

        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.position.seconds, 0, "Play from stopped starts at the beginning")
    }

    func testStopFromPausedAndTogglePlayPause() async {
        let rig = await playing([a], current: a)
        await rig.transport.togglePlayPause()
        XCTAssertEqual(rig.transport.state, .paused)
        rig.backend.positionSeconds = 9
        await rig.transport.stop()
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.backend.pauseCount, 1, "already paused: not suspended again")
        XCTAssertEqual(rig.backend.seekTargets, [0])
        await rig.transport.togglePlayPause()
        XCTAssertEqual(rig.transport.state, .playing)
        await rig.transport.togglePlayPause()
        XCTAssertEqual(rig.transport.state, .paused)
    }

    // MARK: - Seek (AUD-006-R8, R9)

    func testSeekIsSynchronousAndClampedInEveryState() async {
        let rig = await playing([a, b], current: a)
        rig.transport.seek(to: 20)
        XCTAssertEqual(rig.transport.position.seconds, 20)
        XCTAssertEqual(rig.transport.state, .playing)
        rig.transport.seek(to: -4)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        rig.transport.seek(to: .nan)
        XCTAssertEqual(rig.backend.seekTargets.last, 0, "NaN counts as 0")
        rig.transport.seek(to: 500)
        XCTAssertEqual(rig.transport.position.seconds, 60)

        await rig.transport.pause()
        rig.transport.seek(to: 33)
        XCTAssertEqual(rig.transport.position.seconds, 33)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0, "a paused seek does not start playback")

        await rig.transport.stop()
        rig.transport.seek(to: 7)
        XCTAssertEqual(rig.transport.state, .paused, "seeking while stopped leaves playback paused there")
        XCTAssertEqual(rig.transport.position.seconds, 7)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.position.seconds, 7)
    }

    // MARK: - Lifecycle (AUD-006-R21, R22)

    func testUserPauseAndStopSurviveBackgroundAndLock() async {
        let rig = await playing([a, b], current: a)
        await rig.transport.pause()
        for event in [AppLifecycleEvent.background, .foreground, .lock, .unlock] { await rig.manager.handle(event) }
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0)

        await rig.transport.stop()
        for event in [AppLifecycleEvent.background, .foreground, .lock, .unlock] { await rig.manager.handle(event) }
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.backend.resumeCount, 0)
        XCTAssertEqual(rig.backend.pauseCount, 1)
    }

    func testALifecyclePauseWhilePlayingShowsPausedAndResumesByItself() async {
        let rig = await playing([a, b], current: a)
        rig.backend.positionSeconds = 4
        await rig.manager.handle(.background)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertFalse(rig.manager.isPausedByUser)
        await rig.manager.handle(.foreground)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.backend.resumeCount, 1)
        XCTAssertEqual(rig.transport.position.seconds, 4)
        XCTAssertEqual(rig.backend.seekTargets, [])
    }

    func testInterruptionAndRouteLossShowPausedAndPlayContinues() async {
        let rig = await playing([a, b], current: a)
        rig.backend.onEvent?(.interruptionBegan)
        await settle()
        XCTAssertEqual(rig.manager.state, .interrupted)
        XCTAssertEqual(rig.transport.state, .paused, "the transport says what the manager says")
        await rig.transport.pause()                  // becomes a user pause
        rig.backend.onEvent?(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(rig.transport.state, .paused)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)

        rig.backend.onEvent?(.outputRouteLost)
        await settle()
        XCTAssertEqual(rig.manager.stopReason, .audioRouteChanged)
        XCTAssertEqual(rig.transport.state, .paused)
        await rig.transport.play()                   // the same as the banner's Resume
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertNil(rig.manager.stopReason)
    }

    func testRestartStartsANewSessionThatPlays() async {
        let rig = await playing([a, b], current: a)
        await rig.transport.next()
        await rig.transport.stop()
        XCTAssertEqual(rig.transport.state, .stopped)
        await rig.manager.restart()
        XCTAssertEqual(rig.transport.state, .playing, "Stop playback belongs to the session it was pressed in")
        XCTAssertEqual(rig.backend.startedTracks, [a.track, b.track], "Restart plays the current track")
        XCTAssertEqual(rig.transport.current, b)
    }

    // MARK: - Rapid sequences (AUD-006-R29)

    func testCommandsRacingAStopEndStopped() async {
        let rig = await playing([a, b, c], current: a)
        async let pause: Void = rig.transport.pause()
        async let play: Void = rig.transport.play()
        async let next: Void = rig.transport.next()
        async let stopPlayback: Void = rig.transport.stop()
        async let stop: Void = rig.manager.stop()
        rig.transport.seek(to: 10)
        _ = await (pause, play, next, stopPlayback, stop)
        await rig.transport.play()
        await rig.transport.next()
        rig.transport.seek(to: 3)
        await settle()
        XCTAssertEqual(rig.backend.stopCount, 1)
        XCTAssertEqual(rig.backend.callsAfterStop, 0, "no command reaches the backend after the stop")
        XCTAssertFalse(rig.transport.isAvailable)
        XCTAssertEqual(rig.manager.state, .stopped)
    }

    // MARK: - Order (AUD-006-R14 to R18)

    func testNextFollowsTheListAndWraps() async {
        let rig = await playing([a, b, c], current: a)
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, b)
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, c)
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, a, "after the last track comes the first")
        XCTAssertEqual(rig.backend.replacedTracks, [b.track, c.track, a.track])
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        // AUD-006-R2: one source session, one label, the session clock keeps running.
        XCTAssertEqual(rig.backend.startedTracks.count, 1)
        XCTAssertEqual(rig.source.sessionCount, 1)
        XCTAssertEqual(rig.manager.activeMode, .inAppPlayback)
        XCTAssertEqual(rig.backend.stopCount, 0)
        XCTAssertEqual(rig.source.track, a.track, "a Restart would play the current track")
    }

    func testPreviousWithinThreeSecondsGoesBackAndWraps() async {
        let rig = await playing([a, b, c], current: b)
        rig.backend.positionSeconds = 3.0                      // not more than 3 s
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, a)
        rig.backend.positionSeconds = 1
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, c, "before the first track comes the last")
        XCTAssertEqual(rig.backend.replacedTracks, [a.track, c.track])
        XCTAssertEqual(rig.backend.seekTargets, [])
    }

    func testPreviousAfterThreeSecondsRestartsTheTrack() async {
        let rig = await playing([a, b, c], current: b)
        rig.backend.positionSeconds = 3.01
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, b)
        XCTAssertEqual(rig.backend.seekTargets, [0])
        XCTAssertEqual(rig.backend.replaceRequests, [])
        XCTAssertEqual(rig.transport.position.seconds, 0)
        await rig.transport.previous()                          // now at 0: goes back
        XCTAssertEqual(rig.transport.current, a)
    }

    func testNextAndPreviousKeepPausedAndStopped() async {
        let rig = await playing([a, b, c], current: a)
        await rig.transport.pause()
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, b)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0)
        await rig.transport.stop()
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, a)
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.backend.resumeCount, 0)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, a)
    }

    func testTheEndOfATrackStartsTheNextAndKeepsPlaying() async {
        let rig = await playing([a, b], current: a)
        rig.backend.positionSeconds = 60
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, b)
        XCTAssertEqual(rig.backend.replacedTracks, [b.track])
        XCTAssertEqual(rig.transport.state, .playing)
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, a, "the last track is followed by the first")
        // A late end report while paused changes nothing.
        await rig.transport.pause()
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, a)
    }

    func testOneTrackLoopsAndSeveralDoNot() async {
        let single = await playing([a], current: a)
        XCTAssertEqual(single.backend.loopFlags, [true], "set before the session starts")
        await single.transport.next()
        XCTAssertEqual(single.backend.seekTargets, [0], "Next with one track starts it again")
        XCTAssertEqual(single.backend.replaceRequests, [])
        single.backend.positionSeconds = 1
        await single.transport.previous()
        XCTAssertEqual(single.backend.seekTargets, [0, 0])

        let reference = makeRig()
        let referenceItem = PlaybackItem.reference(title: "Reference track", durationSeconds: 60)
        reference.transport.prepare(order: ListPlayOrder([referenceItem]), current: referenceItem)
        await reference.manager.select(.inAppPlayback)
        XCTAssertEqual(reference.backend.startedTracks, [.reference])
        XCTAssertEqual(reference.backend.loopFlags, [true])

        let several = await playing([a, b], current: a)
        XCTAssertEqual(several.backend.loopFlags, [false])
        await several.transport.next()
        XCTAssertEqual(several.backend.loopFlags, [false, false])
    }

    func testSeekToTheEndWhilePausedAdvancesOnPlay() async {
        let rig = await playing([a, b], current: a)
        await rig.transport.pause()
        rig.transport.seek(to: 60)
        XCTAssertEqual(rig.transport.position.seconds, 60, "the position shows the end")
        XCTAssertEqual(rig.transport.current, a)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.current, b, "Play at the end continues with the next track")
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.position.seconds, 0)
    }

    // MARK: - Failure (AUD-006-R19)

    func testATrackThatCannotBeLoadedEndsTheSessionWithoutASubstitute() async {
        let rig = await playing([a, b, c], current: a)
        rig.backend.unplayable = [b.track]
        await rig.transport.next()
        await settle()
        XCTAssertEqual(rig.manager.state, .stopped)
        XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
        XCTAssertEqual(rig.backend.replaceRequests, [b.track], "no other track was asked for")
        XCTAssertEqual(rig.backend.stopCount, 1)
        XCTAssertFalse(rig.transport.isAvailable)
        XCTAssertEqual(rig.transport.current, a)
    }

    func testAnUnplayableNextTrackAtTheEndOfATrackAlsoFails() async {
        let rig = await playing([a, b], current: a)
        rig.backend.unplayable = [b.track]
        rig.backend.onTrackEnded?()
        await settle()
        XCTAssertEqual(rig.manager.stopReason, .inAppPlaybackFailed)
        XCTAssertEqual(rig.backend.replaceRequests, [b.track])
    }

    // MARK: - An order that ends (reserved for AUD-004)

    func testWhenNothingFollowsPlaybackStaysStoppedAtTheEnd() async {
        let rig = makeRig()
        rig.transport.prepare(order: EndingOrder([a, b]), current: b)
        await rig.manager.select(.inAppPlayback)
        XCTAssertEqual(rig.backend.loopFlags, [false])
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, b, "Next at the end of an ending order does nothing")
        XCTAssertEqual(rig.backend.replaceRequests, [])
        rig.backend.positionSeconds = 60
        rig.backend.onTrackEnded?()
        await settle()
        XCTAssertEqual(rig.transport.state, .stopped)
        XCTAssertEqual(rig.manager.state, .paused)
        XCTAssertEqual(rig.transport.position.seconds, 60)
        await rig.transport.play()
        await settle()
        XCTAssertEqual(rig.transport.state, .stopped, "nothing follows: Play at the end does not start")
        XCTAssertEqual(rig.backend.resumeCount, 0)
        rig.transport.seek(to: 10)                              // moving away from the end
        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
    }
}
