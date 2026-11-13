// ShuffleTransportTests.swift — the transport with a shuffled queue, on the scripted backend
// (AUD-005-T05; AUD-005-R4 to R6, R9). Seed 42 over tracks 1-5 with 1 current shuffles as
// 1, 5, 3, 2, 4 (ShuffleQueueTests). No audio: Linux too. Waits poll under a 30 s ceiling.
import AudioCore
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class ShuffleTransportTests: XCTestCase {
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

    private func playing(shuffled: Bool = true, mode: RepeatMode = .all) async -> Rig {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let manager = CaptureManager(sources: [source, FakeAudioSource(mode: .microphone)], runsAnalysisTimer: false)
        let transport = PlaybackTransport(manager: manager, source: source)
        let queue = PlayQueue(store: nil, seedSource: { 42 })
        queue.setLibrary([1, 2, 3, 4, 5].map(item))
        queue.setRepeatMode(mode)
        transport.prepare(order: queue, current: item(1))
        if shuffled { queue.setShuffle(true) }
        await manager.select(.inAppPlayback)
        XCTAssertEqual(transport.state, .playing)
        return Rig(backend: backend, manager: manager, transport: transport, queue: queue)
    }

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

    func testTogglingShuffleWhilePlayingMovesNothing() async {
        let rig = await playing(shuffled: false)
        rig.backend.positionSeconds = 12
        rig.queue.toggleShuffle()
        rig.queue.toggleShuffle()
        rig.queue.toggleShuffle()
        XCTAssertTrue(rig.queue.isShuffled)
        XCTAssertEqual(commands(rig), 0, "a Shuffle change is not a transport command")
        XCTAssertEqual(rig.transport.position.seconds, 12)
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.transport.current, item(1))
    }

    func testTogglingShuffleWhilePausedStaysPaused() async {
        let rig = await playing(shuffled: false)
        await rig.transport.pause()
        rig.queue.toggleShuffle()
        XCTAssertEqual(rig.transport.state, .paused)
        XCTAssertEqual(rig.backend.resumeCount, 0)
    }

    func testNextPreviousAndTheEndOfATrackFollowTheShuffleAndTheHistory() async {
        let rig = await playing()
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, item(5))
        rig.backend.onTrackEnded?()
        XCTAssertEqual(rig.transport.current, item(3), "the end of a track continues the shuffle")
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(5), "back through the history")
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(1))
        await rig.transport.next()
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, item(3), "forward through the history again")
        await rig.transport.next()
        XCTAssertEqual(rig.transport.current, item(2), "then the next shuffled track")
    }

    func testPreviousAfterThreeSecondsRestartsWithoutMovingTheHistory() async {
        let rig = await playing()
        await rig.transport.next()                                  // 5
        rig.backend.positionSeconds = 30
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(5))
        XCTAssertEqual(rig.backend.seekTargets.last, 0)
        rig.backend.positionSeconds = 1
        await rig.transport.previous()
        XCTAssertEqual(rig.transport.current, item(1))
    }

    func testOffStopsAfterTheCycleAndCuesTheNextCyclesFirst() async {
        let rig = await playing(mode: .off)
        for _ in 0..<4 { await rig.transport.next() }               // 5, 3, 2, 4
        XCTAssertEqual(rig.transport.current, item(4))
        rig.backend.positionSeconds = 60
        rig.backend.onTrackEnded?()
        await waitUntil("stopped after the cycle") { rig.transport.state == .stopped }
        XCTAssertEqual(rig.transport.current, item(1), "the next cycle's first track is cued")
        XCTAssertEqual(rig.queue.currentID, item(1).id)
        await rig.transport.play()
        XCTAssertEqual(rig.transport.state, .playing)
        XCTAssertEqual(rig.queue.item(after: item(1).id), item(4), "the new cycle (seed 42: 1, 4, 3, 5, 2)")
    }
}
