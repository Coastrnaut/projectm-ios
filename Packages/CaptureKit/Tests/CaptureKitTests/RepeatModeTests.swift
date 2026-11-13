// RepeatModeTests.swift — the queue's answers per repeat mode (AUD-004-T03; AUD-004-R1 to R7, R10,
// R11, R14; specs/017-aud-004-loop-track-and-queue/data-model.md). No audio: runs on Linux too.
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class RepeatModeTests: XCTestCase {
    // nonisolated(unsafe): Linux's XCTest calls setUpWithError and tearDownWithError outside the
    // main actor (see PlayQueueTests). XCTest never runs them concurrently with the test.
    nonisolated(unsafe) private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud004-repeat-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func item(_ n: Int) -> PlaybackItem {
        PlaybackItem(id: String(format: "00000000-0000-0000-0000-%012d", n), title: "Track \(n)", durationSeconds: 60,
                     track: .file(URL(fileURLWithPath: "/library/assets/\(n).wav")))
    }

    /// A queue of `library` in `mode`, stored in the test's folder; `stored: false` keeps it in memory
    /// (loops over the modes, so that one iteration's record never seeds the next).
    private func makeQueue(_ library: [Int] = [1, 2, 3], mode: RepeatMode = .all, stored: Bool = true) -> PlayQueue {
        let queue = PlayQueue(store: stored ? PlayQueueStore(directory: directory) : nil)
        queue.setLibrary(library.map(item))
        queue.setRepeatMode(mode)
        return queue
    }

    private func storedRecord() -> PlayQueueRecord? {
        if case .record(let record) = PlayQueueStore(directory: directory).load() { return record }
        return nil
    }

    // MARK: - The mode

    func testTheCycleIsOffAllOneOff() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
        XCTAssertEqual(RepeatMode.allCases.map(\.rawValue), ["off", "one", "all"])
    }

    func testTheDefaultIsAllTracks() {
        XCTAssertEqual(PlayQueue(store: nil).repeatMode, .all)
        XCTAssertEqual(PlayQueue(store: PlayQueueStore(directory: directory)).repeatMode, .all)
    }

    // MARK: - End of a track (data-model.md table)

    func testAllTracksWraps() {
        let queue = makeQueue(mode: .all)
        XCTAssertEqual(queue.endOfTrack(after: item(1).id), .play(item(2)))
        XCTAssertEqual(queue.endOfTrack(after: item(3).id), .play(item(1)))
    }

    func testOneTrackRepeatsTheQueuedTrack() {
        let queue = makeQueue(mode: .one)
        XCTAssertEqual(queue.endOfTrack(after: item(1).id), .play(item(1)))
        XCTAssertEqual(queue.endOfTrack(after: item(3).id), .play(item(3)))
    }

    func testOffStopsAfterTheLastTrackAndCuesTheFirst() {
        let queue = makeQueue(mode: .off)
        XCTAssertEqual(queue.endOfTrack(after: item(1).id), .play(item(2)))
        XCTAssertEqual(queue.endOfTrack(after: item(2).id), .play(item(3)))
        XCTAssertEqual(queue.endOfTrack(after: item(3).id), .stop(cue: item(1)))
    }

    func testASingleQueuedTrack() {
        XCTAssertEqual(makeQueue([1], mode: .all).endOfTrack(after: item(1).id), .play(item(1)))
        XCTAssertEqual(makeQueue([1], mode: .one).endOfTrack(after: item(1).id), .play(item(1)))
        XCTAssertEqual(makeQueue([1], mode: .off).endOfTrack(after: item(1).id), .stop(cue: item(1)))
    }

    func testAnEmptyQueueStopsWithoutACueInEveryMode() {
        for mode in RepeatMode.allCases {
            let queue = makeQueue(mode: mode, stored: false)
            queue.playbackDidMove(to: item(2).id)
            queue.clear()
            XCTAssertEqual(queue.endOfTrack(after: item(2).id), .stop(cue: nil), "\(mode)")
        }
    }

    func testAnUnknownTrackIsFollowedByTheFirst() {
        for mode in RepeatMode.allCases {
            XCTAssertEqual(makeQueue(mode: mode, stored: false).endOfTrack(after: "nope"), .play(item(1)), "\(mode)")
        }
    }

    // MARK: - The playing track removed from the queue (AUD-004-R10)

    func testARemovedMiddleTrackIsFollowedByTheTrackInItsPlaceInEveryMode() {
        for mode in RepeatMode.allCases {
            let queue = makeQueue(mode: mode, stored: false)
            queue.playbackDidMove(to: item(2).id)
            queue.remove(item(2).id)                                  // 1, 3; 2 detached at index 1
            XCTAssertEqual(queue.endOfTrack(after: item(2).id), .play(item(3)), "\(mode): no longer repeated")
        }
    }

    func testARemovedLastTrackWrapsExceptInOff() {
        for (mode, expected) in [(RepeatMode.all, EndOfTrackStep.play(item(1))), (.one, .play(item(1))),
                                 (.off, .stop(cue: item(1)))] {
            let queue = makeQueue(mode: mode, stored: false)
            queue.playbackDidMove(to: item(3).id)
            queue.remove(item(3).id)                                  // 1, 2; 3 detached past the end
            XCTAssertEqual(queue.endOfTrack(after: item(3).id), expected, "\(mode)")
        }
    }

    // MARK: - Next and Previous wrap in every mode (AUD-004-R7)

    func testNextAndPreviousIgnoreTheMode() {
        for mode in RepeatMode.allCases {
            let queue = makeQueue(mode: mode, stored: false)
            XCTAssertEqual(queue.item(after: item(3).id), item(1), "\(mode)")
            XCTAssertEqual(queue.item(after: item(1).id), item(2), "\(mode)")
            XCTAssertEqual(queue.item(before: item(1).id), item(3), "\(mode)")
        }
    }

    // MARK: - Changes and storage (AUD-004-R9, R14)

    func testSettingTheModeStoresItAndNotifies() {
        let queue = makeQueue()
        var notified = 0
        queue.onOrderChange = { notified += 1 }
        queue.setRepeatMode(.one)
        XCTAssertEqual(queue.repeatMode, .one)
        XCTAssertEqual(notified, 1)
        XCTAssertEqual(storedRecord()?.repeatMode, .one)
        XCTAssertEqual(storedRecord()?.trackIDs, [1, 2, 3].map { item($0).id }, "the order is stored with it")
        queue.setRepeatMode(.one)
        XCTAssertEqual(notified, 1, "the same mode again changes nothing")
        queue.cycleRepeatMode()
        XCTAssertEqual(queue.repeatMode, .off)
        XCTAssertEqual(notified, 2)
        XCTAssertEqual(storedRecord()?.repeatMode, .off)
    }

    func testTheModeSurvivesARelaunch() {
        let queue = makeQueue(mode: .off)
        queue.playbackDidMove(to: item(2).id)
        let relaunched = PlayQueue(store: PlayQueueStore(directory: directory))
        XCTAssertEqual(relaunched.repeatMode, .off)
        relaunched.setLibrary([1, 2, 3].map(item))
        XCTAssertEqual(relaunched.repeatMode, .off)
        XCTAssertEqual(relaunched.currentID, item(2).id)
    }

    func testEditsKeepTheStoredMode() {
        let queue = makeQueue(mode: .one)
        queue.moveUp(item(3).id)
        XCTAssertEqual(storedRecord()?.repeatMode, .one)
    }

    func testANewerRecordLeavesTheModeChangeableForThisLaunchOnly() throws {
        let newer = Data(#"{"schemaVersion":9,"repeatMode":"off"}"#.utf8)
        try newer.write(to: directory.appendingPathComponent("queue.json"))
        let queue = PlayQueue(store: PlayQueueStore(directory: directory))
        queue.setLibrary([1, 2].map(item))
        XCTAssertEqual(queue.repeatMode, .all, "nothing of a newer record is read")
        queue.setRepeatMode(.one)
        XCTAssertEqual(queue.repeatMode, .one)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("queue.json")), newer)
    }

    func testAQueueInMemoryOnly() {
        let queue = PlayQueue(store: nil)
        queue.setLibrary([1, 2].map(item))
        queue.setRepeatMode(.off)
        XCTAssertEqual(queue.endOfTrack(after: item(2).id), .stop(cue: item(1)))
    }

    // MARK: - Other orders keep their behavior (AUD-004-R11)

    func testAListOrderRepeatsAloneAndWrapsByDefault() {
        let reference = PlaybackItem.reference(title: "Reference", durationSeconds: 0)
        XCTAssertEqual(ListPlayOrder([reference]).endOfTrack(after: reference.id), .play(reference))
        XCTAssertEqual(ListPlayOrder([item(1), item(2)]).endOfTrack(after: item(2).id), .play(item(1)))
        XCTAssertEqual(ListPlayOrder([]).endOfTrack(after: item(1).id), .stop(cue: nil))
    }
}
