// QueueTransportTests.swift — the transport with the queue as its play order, on a scripted backend
// (AUD-003-T04; AUD-003-R1, R7 to R9, R12). No audio: runs on Linux too.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class QueueTransportTests: XCTestCase {
    private struct Rig {
        let backend: FakePlaybackBackend
        let source: InAppPlaybackSource
        let manager: CaptureManager
        let transport: PlaybackTransport
        let queue: PlayQueue
    }

    private func item(_ n: Int) -> PlaybackItem {
        PlaybackItem(id: String(format: "00000000-0000-0000-0000-%012d", n), title: "Track \(n)", durationSeconds: 60,
                     track: .file(URL(fileURLWithPath: "/library/assets/\(n).wav")))
    }

    /// Playing `current` with a queue of `library` (in memory).
    private func playing(_ library: [Int], current: Int) async -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let manager = CaptureManager(sources: [source, FakeAudioSource(mode: .microphone)], runsAnalysisTimer: false)
        let transport = PlaybackTransport(manager: manager, source: source)
        let queue = PlayQueue(store: nil)
        queue.setLibrary(library.map(item))
        transport.prepare(order: queue, current: item(current))
        await manager.select(.inAppPlayback)
        XCTAssertEqual(transport.state, .playing)
        return Rig(backend: backend, source: source, manager: manager, transport: transport, queue: queue)
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    /// The number of commands the backend received that move or stop playback.
    private func commands(_ rig: Rig) -> Int {
        rig.backend.pauseCount + rig.backend.resumeCount + rig.backend.seekTargets.count + rig.backend.replaceRequests.count
    }

    func testPrepareReportsTheCurrentTrackToTheQueue() async {
        let rig = await playing([1, 2, 3], current: 2)
        XCTAssertEqual(rig.queue.currentID, item(2).id)
    }

    func testNextAndTheEndOfATrackFollowAReorderMadeWhilePlaying() async {
        let rig = await playing([1, 2, 3], current: 1)
        rig.backend.positionSeconds = 12
        rig.queue.moveUp(item(3).id)                          // 1, 3, 2
        XCTAssertEqual(commands(rig), 0, "an edit sends no command")
        XCTAssertEqual(rig.transport.position.seconds, 12)
        XCTAssertEqual(rig.transport.state, .playing)

        rig.backend.onTrackEnded?()                           // 1 ended
        XCTAssertEqual(rig.transport.current, item(3))
        XCTAssertEqual(rig.backend.replacedTracks, [item(3).track])
        XCTAssertEqual(rig.queue.currentID, item(3).id, "a track change is reported")
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, item(2))
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(3))
    }

    func testALoneTrackStopsLoopingWhenASecondIsQueuedAndLoopsAgainWhenAloneOnceMore() async {
        let rig = await playing([1, 2], current: 1)
        rig.queue.remove(item(2).id)
        XCTAssertTrue(rig.backend.loopsCurrentTrack, "alone: repeats")
        rig.queue.addToEnd(item(2).id)
        XCTAssertFalse(rig.backend.loopsCurrentTrack, "no longer alone: ends")
        rig.queue.remove(item(2).id)
        XCTAssertTrue(rig.backend.loopsCurrentTrack)
        XCTAssertEqual(commands(rig), 0, "looping changes are not commands")
        XCTAssertEqual(rig.transport.state, .playing)
    }

    func testThePlayingTrackRemovedFromTheQueuePlaysToItsEndThenTheTrackInItsPlace() async {
        let rig = await playing([1, 2, 3], current: 2)
        rig.queue.remove(item(2).id)                          // 1, 3
        XCTAssertFalse(rig.backend.loopsCurrentTrack)
        XCTAssertEqual(rig.transport.current, item(2), "it keeps playing")
        XCTAssertEqual(commands(rig), 0)
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, item(3))
    }

    func testClearingWhilePlayingStopsAtTheEndOfTheTrack() async {
        let rig = await playing([1, 2], current: 1)
        rig.queue.clear()
        XCTAssertFalse(rig.backend.loopsCurrentTrack, "nothing follows, so it does not repeat either")
        rig.backend.onTrackEnded?()
        await settle()
        XCTAssertEqual(rig.transport.state, .stopped, "stopped at the end (AUD-006-R17)")
        XCTAssertEqual(rig.transport.current, item(1))
        XCTAssertTrue(rig.transport.isAvailable, "the session stays")
    }

    func testAnEditDuringAnInterruptionDoesNotCancelTheResume() async {
        let rig = await playing([1, 2, 3], current: 1)
        rig.backend.onEvent?(.interruptionBegan)
        await settle()
        XCTAssertEqual(rig.manager.state, .interrupted)
        rig.queue.moveUp(item(3).id)
        rig.queue.remove(item(2).id)
        rig.backend.onEvent?(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(rig.backend.resumeCount, 1, "the edit is not a transport change (AUD-003-R12)")
    }

    func testAReorderWhilePausedKeepsItPaused() async {
        let rig = await playing([1, 2, 3], current: 1)
        await rig.transport.pause()
        rig.queue.moveDown(item(1).id)
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0)
    }

    func testAnotherOrderReplacesTheQueueAndTheQueueNoLongerDrivesTheTransport() async {
        let rig = await playing([1, 2], current: 1)
        let reference = PlaybackItem.reference(title: "Reference", durationSeconds: 0)
        rig.transport.prepare(order: ListPlayOrder([reference]), current: reference)
        XCTAssertNil(rig.queue.onOrderChange, "the transport unhooked the queue")
        XCTAssertEqual(rig.queue.currentID, item(1).id, "the reference track is not reported to the queue")
    }
}
