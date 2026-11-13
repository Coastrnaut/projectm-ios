// RepeatTransportTests.swift — the transport with the queue's repeat modes, on the scripted backend
// (AUD-004-T04; AUD-004-R4 to R10, R16; contracts/repeat-mode.md "Transport rules"). No audio: runs
// on Linux too. Waits poll a condition under a 30 s ceiling; nothing depends on elapsed time.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class RepeatTransportTests: XCTestCase {
    private struct Rig {
        let backend: FakePlaybackBackend
        let manager: CaptureManager
        let transport: PlaybackTransport
        let queue: PlayQueue
    }

    private func item(_ n: Int) -> PlaybackItem {
        PlaybackItem(id: String(format: "00000000-0000-0000-0000-%012d", n), title: "Track \(n)", durationSeconds: 60,
                     track: .file(URL(fileURLWithPath: "/library/assets/\(n).wav")))
    }

    /// Playing `current` with an in-memory queue of `library` in `mode`.
    private func playing(_ library: [Int], current: Int, mode: RepeatMode) async -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let manager = CaptureManager(sources: [source, FakeAudioSource(mode: .microphone)], runsAnalysisTimer: false)
        let transport = PlaybackTransport(manager: manager, source: source)
        let queue = PlayQueue(store: nil)
        queue.setLibrary(library.map(item))
        queue.setRepeatMode(mode)
        transport.prepare(order: queue, current: item(current))
        await manager.select(.inAppPlayback)
        XCTAssertEqual(transport.state, .playing)
        return Rig(backend: backend, manager: manager, transport: transport, queue: queue)
    }

    /// Waits until `condition` holds, for at most 30 s (a ceiling, not a budget).
    private func waitUntil(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(30)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    private func commands(_ rig: Rig) -> Int {
        rig.backend.pauseCount + rig.backend.resumeCount + rig.backend.seekTargets.count + rig.backend.replaceRequests.count
    }

    // MARK: - Whether the current track repeats

    func testTheLoopFlagFollowsTheMode() async {
        let one = await playing([1, 2, 3], current: 1, mode: .one)
        XCTAssertTrue(one.backend.loopsCurrentTrack, "One Track repeats with others queued")
        let all = await playing([1, 2, 3], current: 1, mode: .all)
        XCTAssertFalse(all.backend.loopsCurrentTrack)
        let off = await playing([1, 2, 3], current: 3, mode: .off)
        XCTAssertFalse(off.backend.loopsCurrentTrack)
        let aloneAll = await playing([1], current: 1, mode: .all)
        XCTAssertTrue(aloneAll.backend.loopsCurrentTrack)
        let aloneOff = await playing([1], current: 1, mode: .off)
        XCTAssertFalse(aloneOff.backend.loopsCurrentTrack, "Off plays a lone track once")
    }

    func testAModeChangeWhilePlayingOnlyChangesTheLoopFlag() async {
        let rig = await playing([1, 2, 3], current: 1, mode: .all)
        rig.backend.positionSeconds = 12
        rig.queue.setRepeatMode(.one)
        XCTAssertTrue(rig.backend.loopsCurrentTrack)
        rig.queue.setRepeatMode(.off)
        XCTAssertFalse(rig.backend.loopsCurrentTrack)
        rig.queue.setRepeatMode(.all)
        XCTAssertFalse(rig.backend.loopsCurrentTrack)
        XCTAssertEqual(commands(rig), 0, "a mode change is not a transport command")
        XCTAssertEqual(rig.transport.position.seconds, 12)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, item(1))
    }

    func testAModeChangeWhilePausedKeepsItPaused() async {
        let rig = await playing([1, 2], current: 1, mode: .all)
        await rig.transport.pause()
        rig.queue.setRepeatMode(.one)
        XCTAssertTrue(rig.backend.loopsCurrentTrack)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0)
    }

    func testAModeChangeDuringAnInterruptionDoesNotCancelTheResume() async {
        let rig = await playing([1, 2, 3], current: 1, mode: .all)
        rig.backend.onEvent?(.interruptionBegan)
        await waitUntil("interrupted") { rig.manager.state == .interrupted }
        rig.queue.setRepeatMode(.off)
        rig.backend.onEvent?(.interruptionEnded(shouldResume: true))
        await waitUntil("resumed once (AUD-014-R2 unaffected)") { rig.backend.resumeCount == 1 }
    }

    // MARK: - All Tracks (AUD-004-R3)

    func testAllTracksWrapsFromTheLastToTheFirst() async {
        let rig = await playing([1, 2, 3], current: 3, mode: .all)
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertEqual(rig.transport.state, .playing)
    }

    // MARK: - One Track (AUD-004-R4, R7)

    func testOneTrackRepeatsAndNextMovesOnToATrackThatRepeats() async {
        let rig = await playing([1, 2, 3], current: 1, mode: .one)
        rig.backend.positionSeconds = 59.9
        rig.backend.onTrackEnded?()                     // a looping backend never reports it; the order still answers
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertEqual(rig.backend.replaceRequests, [], "the same track: no reload")
        XCTAssertEqual(rig.backend.seekTargets, [0])
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, item(2))
        XCTAssertTrue(rig.backend.loopsCurrentTrack, "the new track repeats")
        XCTAssertEqual(rig.queue.repeatMode, .one)
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(1))
    }

    // MARK: - Off (AUD-004-R5, R6, R16)

    func testOffStopsAfterTheLastTrackAtTheFirstTracksStart() async {
        let rig = await playing([1, 2, 3], current: 2, mode: .off)
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, item(3), "not the last: the next track follows")
        XCTAssertEqual(rig.transport.state, .playing)
        rig.backend.positionSeconds = 60
        rig.backend.onTrackEnded?()
        await waitUntil("stopped at the end of the queue") { rig.transport.state == .stopped }
        XCTAssertEqual(rig.transport.current, item(1), "the first queued track is cued")
        XCTAssertEqual(rig.backend.replacedTracks.last, item(1).track)
        XCTAssertEqual(rig.transport.position.seconds, 0)
        XCTAssertTrue(rig.transport.isAvailable, "the session and the visualizer stay")
        XCTAssertTrue(rig.manager.isPausedByUser)
        XCTAssertEqual(rig.queue.currentID, item(1).id, "the cue is reported to the queue")

        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertEqual(rig.backend.resumeCount, 1)
    }

    func testOffWithOneTrackStopsAtItsOwnStart() async {
        let rig = await playing([1], current: 1, mode: .off)
        rig.backend.positionSeconds = 60
        rig.backend.onTrackEnded?()
        await waitUntil("stopped") { rig.transport.state == .stopped }
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertEqual(rig.backend.seekTargets, [0])
        XCTAssertEqual(rig.backend.replaceRequests, [])
    }

    func testPlayAtTheVeryEndOfTheLastTrackStartsTheQueueAgain() async {
        let rig = await playing([1, 2, 3], current: 3, mode: .off)
        await rig.transport.pause()
        rig.transport.seek(to: 60)
        XCTAssertEqual(rig.transport.state, .paused)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.backend.replacedTracks.last, item(1).track)
    }

    func testAnEmptyQueueStillStopsAtTheEndOfTheTrack() async {
        for mode in RepeatMode.allCases {
            let rig = await playing([1, 2], current: 1, mode: mode)
            rig.queue.clear()
            XCTAssertFalse(rig.backend.loopsCurrentTrack, "\(mode)")
            rig.backend.onTrackEnded?()
            await waitUntil("\(mode): stopped") { rig.transport.state == .stopped }
            XCTAssertEqual(rig.transport.current, item(1), "\(mode): nothing cued")
            XCTAssertEqual(rig.backend.replaceRequests, [])
        }
    }

    // MARK: - The playing track removed from the queue (AUD-004-R10)

    func testOneTrackDoesNotRepeatARemovedTrack() async {
        let rig = await playing([1, 2, 3], current: 2, mode: .one)
        XCTAssertTrue(rig.backend.loopsCurrentTrack)
        rig.queue.remove(item(2).id)
        XCTAssertFalse(rig.backend.loopsCurrentTrack, "removed: plays to its end")
        XCTAssertEqual(commands(rig), 0)
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, item(3), "the track in its place follows")
        XCTAssertTrue(rig.backend.loopsCurrentTrack, "and repeats")
    }

    func testOffStopsWhenTheRemovedTrackWasLast() async {
        let rig = await playing([1, 2, 3], current: 3, mode: .off)
        rig.queue.remove(item(3).id)
        rig.backend.onTrackEnded?()
        await waitUntil("stopped") { rig.transport.state == .stopped }
        XCTAssertEqual(rig.transport.current, item(1))
    }
}
