// PlayQueueTests.swift — the queue's rules (AUD-003-T03; AUD-003-R1 to R9, R13 to R15;
// data-model.md, contracts/play-queue.md). No audio: runs on Linux too.
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class PlayQueueTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud003-queue-\(UUID().uuidString)",
                                                                                   isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Item `n` has a fixed UUID so that it can be stored.
    private func item(_ n: Int) -> PlaybackItem {
        let id = String(format: "00000000-0000-0000-0000-%012d", n)
        return PlaybackItem(id: id, title: "Track \(n)", durationSeconds: 60,
                            track: .file(URL(fileURLWithPath: "/library/assets/\(n).wav")))
    }

    private func ids(_ numbers: Int...) -> [String] { numbers.map { item($0).id } }

    private func queued(_ queue: PlayQueue) -> [String] { queue.items.map(\.id) }

    private func makeQueue(library: [Int] = [1, 2, 3]) -> PlayQueue {
        let queue = PlayQueue(store: PlayQueueStore(directory: directory))
        queue.setLibrary(library.map(item))
        return queue
    }

    private func storedRecord() -> PlayQueueRecord? {
        if case .record(let record) = PlayQueueStore(directory: directory).load() { return record }
        return nil
    }

    // MARK: - Seeding and the library (AUD-003-R2, R3, R6)

    func testWithoutARecordTheQueueIsTheLibraryOrderAndNothingIsStoredYet() {
        let queue = makeQueue()
        XCTAssertEqual(queued(queue), ids(1, 2, 3))
        XCTAssertEqual(queue.notQueued, [])
        XCTAssertNil(storedRecord(), "stored at the first edit or move")
        XCTAssertTrue(queue.isPersistent)
    }

    func testNewImportsJoinAtTheTopLastFirstAndKnownOnesAreIgnored() {
        let queue = makeQueue()
        queue.setLibrary([5, 4, 1, 2, 3].map(item))           // the list shows newest first
        queue.didImport(ids(4, 5, 1))                         // imported in this order; 1 is known
        XCTAssertEqual(queued(queue), ids(5, 4, 1, 2, 3))
        XCTAssertEqual(storedRecord()?.trackIDs, ids(5, 4, 1, 2, 3))
    }

    func testTracksDeletedFromTheLibraryLeaveTheQueue() {
        let queue = makeQueue()
        var changes = 0
        queue.onOrderChange = { changes += 1 }
        queue.setLibrary([1, 3].map(item))
        XCTAssertEqual(queued(queue), ids(1, 3))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(storedRecord()?.trackIDs, ids(1, 3))
        queue.setLibrary([1, 3].map(item))
        XCTAssertEqual(changes, 1, "an unchanged library changes nothing")
    }

    func testTracksRemovedFromTheQueueStayOutWhenTheLibraryRefreshes() {
        let queue = makeQueue()
        queue.remove(item(2).id)
        queue.setLibrary([1, 2, 3].map(item))
        XCTAssertEqual(queued(queue), ids(1, 3))
        XCTAssertEqual(queue.notQueued.map(\.id), ids(2))
    }

    // MARK: - Edits (AUD-003-R5)

    func testAddToEndAndPlayNextPlaceATrackOnceAndMoveItWhenQueued() {
        let queue = makeQueue(library: [1, 2, 3, 4])
        queue.clear()
        queue.addToEnd(item(1).id)
        queue.addToEnd(item(2).id)
        queue.playNext(item(3).id)                            // no current track: at the top
        XCTAssertEqual(queued(queue), ids(3, 1, 2))
        queue.playbackDidMove(to: item(1).id)
        queue.playNext(item(4).id)                            // right after the current track
        XCTAssertEqual(queued(queue), ids(3, 1, 4, 2))
        queue.playNext(item(2).id)                            // already queued: moves
        XCTAssertEqual(queued(queue), ids(3, 1, 2, 4))
        queue.addToEnd(item(3).id)
        XCTAssertEqual(queued(queue), ids(1, 2, 4, 3))
        queue.playNext(item(1).id)                            // the current track itself: no change
        XCTAssertEqual(queued(queue), ids(1, 2, 4, 3))
        queue.addToEnd("00000000-0000-0000-0000-999999999999")   // not in the library: ignored
        XCTAssertEqual(queued(queue), ids(1, 2, 4, 3))
    }

    func testMoveFollowsListSemantics() {
        let queue = makeQueue(library: [1, 2, 3, 4])
        queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)      // 1 to before 4
        XCTAssertEqual(queued(queue), ids(2, 3, 1, 4))
        queue.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)      // 4 to the top
        XCTAssertEqual(queued(queue), ids(4, 2, 3, 1))
        queue.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)          // 4 and 3 to the end
        XCTAssertEqual(queued(queue), ids(2, 1, 4, 3))
        queue.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)      // in place
        XCTAssertEqual(queued(queue), ids(2, 1, 4, 3))
        queue.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)      // out of range: ignored
        XCTAssertEqual(queued(queue), ids(2, 1, 4, 3))
    }

    func testMoveUpAndDownStopAtTheEnds() {
        let queue = makeQueue()
        queue.moveUp(item(1).id)
        XCTAssertEqual(queued(queue), ids(1, 2, 3))
        queue.moveDown(item(1).id)
        XCTAssertEqual(queued(queue), ids(2, 1, 3))
        queue.moveDown(item(3).id)
        XCTAssertEqual(queued(queue), ids(2, 1, 3))
        queue.moveUp(item(3).id)
        XCTAssertEqual(queued(queue), ids(2, 3, 1))
    }

    func testEveryEditIsStoredAndAnnouncedToTheTransport() {
        let queue = makeQueue()
        var changes = 0
        queue.onOrderChange = { changes += 1 }
        queue.moveDown(item(1).id)
        XCTAssertEqual(storedRecord()?.trackIDs, ids(2, 1, 3))
        queue.remove(item(3).id)
        XCTAssertEqual(storedRecord()?.trackIDs, ids(2, 1))
        queue.addToEnd(item(3).id)
        queue.playNext(item(3).id)
        queue.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        queue.clear()
        XCTAssertEqual(storedRecord()?.trackIDs, [])
        XCTAssertEqual(changes, 6)
        queue.moveUp(item(1).id)                              // not queued: nothing to do
        XCTAssertEqual(changes, 6)
    }

    // MARK: - The order (AUD-003-R1)

    func testNextAndPreviousWrapAndFollowTheQueueAsItIsNow() {
        let queue = makeQueue()
        XCTAssertEqual(queue.item(after: item(1).id)?.id, item(2).id)
        XCTAssertEqual(queue.item(after: item(3).id)?.id, item(1).id)
        XCTAssertEqual(queue.item(before: item(1).id)?.id, item(3).id)
        queue.moveUp(item(3).id)                              // 1, 3, 2
        XCTAssertEqual(queue.item(after: item(1).id)?.id, item(3).id)
        XCTAssertEqual(queue.item(before: item(2).id)?.id, item(3).id)
        XCTAssertEqual(queue.item(after: "unknown")?.id, item(1).id, "an unknown id starts at the top")
    }

    func testOneTrackFollowsItselfAndAnEmptyQueueHasNothing() {
        let queue = makeQueue(library: [1])
        XCTAssertEqual(queue.item(after: item(1).id)?.id, item(1).id)
        queue.clear()
        XCTAssertNil(queue.item(after: item(1).id))
        XCTAssertNil(queue.item(before: item(1).id))
    }

    // MARK: - Removing the playing track (AUD-003-R9)

    func testTheRemovedCurrentTrackContinuesWithTheTrackAtItsFormerPlace() {
        let queue = makeQueue(library: [1, 2, 3, 4])
        queue.playbackDidMove(to: item(2).id)
        queue.remove(item(2).id)                              // 1, 3, 4
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(3).id)
        XCTAssertEqual(queue.item(before: item(2).id)?.id, item(1).id)
        queue.remove(item(1).id)                              // 3, 4: the place shifts with it
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(3).id)
        XCTAssertEqual(queue.item(before: item(2).id)?.id, item(4).id)
        queue.playbackDidMove(to: item(3).id)                 // playback moved on: no longer detached
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(3).id, "an id that is not queued starts at the top")
        XCTAssertEqual(queue.item(after: item(3).id)?.id, item(4).id)
    }

    func testTheRemovedLastTrackWrapsAndAnEmptyQueueEnds() {
        let queue = makeQueue()
        queue.playbackDidMove(to: item(3).id)
        queue.remove(item(3).id)
        XCTAssertEqual(queue.item(after: item(3).id)?.id, item(1).id)
        XCTAssertEqual(queue.item(before: item(3).id)?.id, item(2).id)
        queue.clear()
        XCTAssertNil(queue.item(after: item(3).id))
    }

    func testPlayNextWhileTheCurrentTrackIsDetachedComesNext() {
        let queue = makeQueue(library: [1, 2, 3, 4])
        queue.playbackDidMove(to: item(2).id)
        queue.remove(item(2).id)                              // 1, 3, 4
        queue.playNext(item(4).id)                            // 1, 4, 3
        XCTAssertEqual(queued(queue), ids(1, 4, 3))
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(4).id)
        queue.playNext(item(2).id)                            // the current track queued again, in its place
        XCTAssertEqual(queued(queue), ids(1, 2, 4, 3))
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(4).id)
    }

    func testClearingWhilePlayingDetachesTheCurrentTrack() {
        let queue = makeQueue()
        queue.playbackDidMove(to: item(2).id)
        queue.clear()
        XCTAssertEqual(queue.items, [])
        XCTAssertNil(queue.item(after: item(2).id))
        queue.addToEnd(item(3).id)
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(3).id)
    }

    func testDeletingTheCurrentTrackFromTheLibraryDetachesIt() {
        let queue = makeQueue()
        queue.playbackDidMove(to: item(2).id)
        queue.setLibrary([1, 3].map(item))
        XCTAssertEqual(queue.item(after: item(2).id)?.id, item(3).id)
    }

    // MARK: - Persistence (AUD-003-R13 to R15)

    func testAReorderAndTheCurrentTrackSurviveANewQueueOverTheSameFolder() {
        let queue = makeQueue()
        queue.playbackDidMove(to: item(1).id)
        queue.moveUp(item(3).id)                              // 1, 3, 2
        let relaunched = PlayQueue(store: PlayQueueStore(directory: directory))
        relaunched.setLibrary([1, 2, 3].map(item))
        XCTAssertEqual(queued(relaunched), ids(1, 3, 2))
        XCTAssertEqual(relaunched.currentID, item(1).id)
        XCTAssertEqual(relaunched.startItem?.id, item(1).id)
        XCTAssertEqual(relaunched.item(after: item(1).id)?.id, item(3).id)
    }

    func testAMoveOfPlaybackIsStored() {
        let queue = makeQueue()
        queue.playbackDidMove(to: item(3).id)
        XCTAssertEqual(storedRecord(), PlayQueueRecord(trackIDs: ids(1, 2, 3), currentTrackID: item(3).id))
    }

    func testStartItemIsTheCurrentTrackWhenQueuedOtherwiseTheFirst() {
        let queue = makeQueue()
        XCTAssertEqual(queue.startItem?.id, item(1).id)
        queue.playbackDidMove(to: item(2).id)
        XCTAssertEqual(queue.startItem?.id, item(2).id)
        queue.remove(item(2).id)
        XCTAssertEqual(queue.startItem?.id, item(1).id)
        queue.clear()
        XCTAssertNil(queue.startItem)
    }

    func testStoredTracksThatLeftTheLibraryAreDroppedOnLoad() throws {
        try PlayQueueStore(directory: directory).save(PlayQueueRecord(trackIDs: ids(3, 9, 1), currentTrackID: item(9).id))
        let queue = makeQueue()
        XCTAssertEqual(queued(queue), ids(3, 1))
        XCTAssertNil(queue.currentID)
        XCTAssertEqual(queue.notQueued.map(\.id), ids(2))
    }

    func testADamagedRecordStartsFromTheLibraryOrder() throws {
        try Data("garbage".utf8).write(to: directory.appendingPathComponent("queue.json"))
        let queue = makeQueue()
        XCTAssertEqual(queued(queue), ids(1, 2, 3))
        XCTAssertTrue(queue.isPersistent)
        queue.moveDown(item(1).id)
        XCTAssertEqual(storedRecord()?.trackIDs, ids(2, 1, 3))
    }

    func testANewerRecordIsNeverOverwritten() throws {
        let newer = Data(#"{"schemaVersion":2}"#.utf8)
        let file = directory.appendingPathComponent("queue.json")
        try newer.write(to: file)
        let queue = makeQueue()
        XCTAssertFalse(queue.isPersistent)
        XCTAssertEqual(queued(queue), ids(1, 2, 3))
        queue.moveDown(item(1).id)
        queue.playbackDidMove(to: item(1).id)
        XCTAssertEqual(queued(queue), ids(2, 1, 3), "edits work for this launch")
        XCTAssertEqual(try Data(contentsOf: file), newer)
    }

    func testAQueueWithoutAStoreWorksInMemory() {
        let queue = PlayQueue(store: nil)
        queue.setLibrary([1, 2].map(item))
        queue.moveDown(item(1).id)
        XCTAssertEqual(queued(queue), ids(2, 1))
        XCTAssertFalse(queue.isPersistent)
    }
}
