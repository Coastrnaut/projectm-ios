// ShuffleQueueTests.swift — the queue's shuffled order and play history (AUD-005-T04; AUD-005-R2 to
// R10, R13; the roadmap acceptance AUD-005-S1 to S4; data-model.md). No audio: Linux too.
//
// The literal sequences for seed 42 were computed by an independent Python model of research
// AUD-005-D1/D4/D5 (`.build/scratch/oracle.py` during AUD-005), not by the code under test. Each test
// drives the queue as the transport does: it asks `item(after:)` or `item(before:)` for the current
// track, then reports the move with its reason.
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class ShuffleQueueTests: XCTestCase {
    // nonisolated(unsafe): Linux's XCTest calls setUpWithError and tearDownWithError outside the
    // main actor (see PlayQueueTests). XCTest never runs them concurrently with the test.
    nonisolated(unsafe) private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aud005-shuffle-\(UUID().uuidString)",
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

    private func number(_ id: PlaybackItem.ID?) -> Int? { id.flatMap { Int($0.suffix(12)) } }

    /// `library` queued in order, `current` playing, then Shuffle on with `seed`.
    private func shuffled(_ library: [Int] = [1, 2, 3, 4, 5], current: Int? = 1, seed: UInt64 = 42,
                          mode: RepeatMode = .all, stored: Bool = false) -> PlayQueue {
        let queue = PlayQueue(store: stored ? PlayQueueStore(directory: directory) : nil, seedSource: { seed })
        queue.setLibrary(library.map(item))
        queue.setRepeatMode(mode)
        if let current { queue.playbackDidMove(to: item(current).id, by: .start) }
        queue.setShuffle(true)
        return queue
    }

    private enum Step { case next, previous }

    /// Moves as the transport's Next or Previous (within 3 s) does; returns the new current track.
    @discardableResult
    private func press(_ step: Step, on queue: PlayQueue) -> Int? {
        guard let current = queue.currentID else { return nil }
        let target = step == .next ? queue.item(after: current) : queue.item(before: current)
        guard let target else { return nil }
        queue.playbackDidMove(to: target.id, by: step == .next ? .next : .previous)
        return number(target.id)
    }

    private func nexts(_ count: Int, on queue: PlayQueue) -> [Int] {
        (0..<count).compactMap { _ in press(.next, on: queue) }
    }

    private func assertPermutation(_ queue: PlayQueue, file: StaticString = #filePath, line: UInt = #line) {
        let order = queue.shuffledItems.map(\.id)
        XCTAssertEqual(order.count, Set(order).count, "no duplicates", file: file, line: line)
        XCTAssertEqual(Set(order), Set(queue.ids), "the shuffled order is a permutation of the queue", file: file, line: line)
    }

    // MARK: - The acceptance: a reproducible seeded sequence (AUD-005-S1)

    func testNextFollowsTheSeededSequenceAcrossTwoCycles() {
        let queue = shuffled()
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.shuffleSeed, 42)
        XCTAssertEqual(queue.ids, [1, 2, 3, 4, 5].map { item($0).id }, "the stored queue order does not change")
        XCTAssertEqual([1] + nexts(9, on: queue), [1, 5, 3, 2, 4, 1, 4, 3, 5, 2])
    }

    func testPreviousWalksBackThroughTheHistoryAndNextForwardAgain() {
        let queue = shuffled()
        let walk = [Step.next, .next, .next, .previous, .previous, .next, .next, .next].compactMap { press($0, on: queue) }
        XCTAssertEqual(walk, [5, 3, 2, 3, 5, 3, 2, 4])
    }

    func testTheSameSeedGivesTheSameSequenceAndOtherSeedsTheirOwn() {
        XCTAssertEqual(nexts(9, on: shuffled()), nexts(9, on: shuffled()))
        XCTAssertEqual([1] + nexts(9, on: shuffled(seed: 1)), [1, 5, 2, 3, 4, 1, 4, 3, 2, 5])
        XCTAssertEqual([1] + nexts(9, on: shuffled(seed: 9_999)), [1, 2, 5, 4, 3, 5, 3, 2, 1, 4])
    }

    // MARK: - No immediate repeat, each track once per cycle (AUD-005-R3, R4; S2)

    func testTwentyCyclesNeverRepeatATrackImmediately() {
        for seed: UInt64 in [1, 42, 9_999] {
            let queue = shuffled(seed: seed)
            let sequence = [1] + nexts(99, on: queue)
            for (a, b) in zip(sequence, sequence.dropFirst()) { XCTAssertNotEqual(a, b, "seed \(seed)") }
            for cycle in 0..<20 {
                XCTAssertEqual(Set(sequence[cycle * 5..<cycle * 5 + 5]), [1, 2, 3, 4, 5], "seed \(seed), cycle \(cycle)")
            }
        }
    }

    func testTwoTracksAlternateAndOneTrackRestarts() {
        XCTAssertEqual(nexts(6, on: shuffled([1, 2], current: 1)), [2, 1, 2, 1, 2, 1])
        let alone = shuffled([1], current: 1)
        XCTAssertEqual(alone.item(after: item(1).id), item(1), "Next starts the only track again")
    }

    // MARK: - History (AUD-005-R5, R8)

    func testPreviousAtTheStartOfTheHistoryRestartsTheCurrentTrack() {
        let queue = shuffled()
        XCTAssertEqual(queue.item(before: item(1).id), item(1))
        press(.next, on: queue)
        press(.previous, on: queue)
        XCTAssertEqual(queue.item(before: item(1).id), item(1))
    }

    func testPickingATrackCountsItAsPlayedAndDropsForwardHistory() {
        let queue = shuffled()
        XCTAssertEqual(nexts(2, on: queue), [5, 3])
        press(.previous, on: queue)                                 // back at 5; 3 is ahead in the history
        queue.playbackDidMove(to: item(4).id, by: .start)            // the user picks 4
        XCTAssertEqual(queue.item(before: item(4).id), item(5), "the history goes back from the pick")
        XCTAssertEqual(number(queue.item(after: item(4).id)?.id), 2, "the one unplayed track; 3 was played")
        assertPermutation(queue)
    }

    func testTheHistoryIsBoundedAt100() {
        let queue = shuffled()
        _ = nexts(150, on: queue)
        var back = 0
        while let current = queue.currentID, queue.item(before: current)?.id != current, back < 200 {
            press(.previous, on: queue)
            back += 1
        }
        XCTAssertEqual(back, ShuffleState.historyLimit - 1)
    }

    // MARK: - Repeat modes (AUD-005-R6; S3)

    func testAtTheEndOfACycleEachRepeatModeAnswersAsSpecified() {
        for mode in RepeatMode.allCases {
            let queue = shuffled(mode: mode)
            _ = nexts(4, on: queue)                                 // 1, 5, 3, 2, 4: the cycle is complete
            XCTAssertEqual(queue.currentID, item(4).id)
            switch mode {
            case .all: XCTAssertEqual(queue.endOfTrack(after: item(4).id), .play(item(1)), "the next cycle's first")
            case .off: XCTAssertEqual(queue.endOfTrack(after: item(4).id), .stop(cue: item(1)))
            case .one: XCTAssertEqual(queue.endOfTrack(after: item(4).id), .play(item(4)), "the current track repeats")
            }
            XCTAssertEqual(queue.item(after: item(4).id), item(1), "Next starts a new cycle in every mode")
        }
    }

    func testWithinACycleTheEndOfATrackFollowsTheShuffle() {
        let off = shuffled(mode: .off)
        XCTAssertEqual(off.endOfTrack(after: item(1).id), .play(item(5)))
        let one = shuffled(mode: .one)
        XCTAssertEqual(one.endOfTrack(after: item(1).id), .play(item(1)))
        XCTAssertEqual(one.item(after: item(1).id), item(5))
    }

    // MARK: - Edits (AUD-005-R7; S4)

    func testPlayNextPlaysRightAfterTheCurrentTrack() {
        let queue = shuffled([1, 2, 3, 4, 5, 6])
        queue.playNext(item(6).id)
        XCTAssertEqual(queue.item(after: item(1).id), item(6))
        queue.playNext(item(2).id)                                  // already queued: moves in the shuffle too
        XCTAssertEqual(queue.item(after: item(1).id), item(2))
        assertPermutation(queue)
    }

    func testAddToQueueAppendsANewTrackAndIgnoresReorders() {
        let queue = shuffled([1, 2, 3, 4, 5])
        queue.setLibrary([1, 2, 3, 4, 5, 6].map(item))
        let before = queue.shuffledItems
        queue.addToEnd(item(6).id)
        XCTAssertEqual(queue.shuffledItems, before + [item(6)], "a track new to the queue ends the cycle")
        queue.addToEnd(item(3).id)                                  // a queued track: a reorder
        queue.moveUp(item(5).id)
        queue.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(queue.shuffledItems, before + [item(6)], "reordering never changes the shuffle")
        assertPermutation(queue)
    }

    func testAnImportJoinsTheUnplayedPartAtAReproduciblePlace() {
        func place() -> Int? {
            let queue = shuffled()
            queue.setLibrary([1, 2, 3, 4, 5, 7].map(item))
            queue.didImport([item(7).id])
            assertPermutation(queue)
            return queue.shuffledItems.firstIndex(of: item(7))
        }
        let index = place()
        XCTAssertNotNil(index)
        XCTAssertGreaterThanOrEqual(index ?? 0, 1, "never before the played part")
        XCTAssertEqual(place(), index)
    }

    func testRemovingTracksKeepsTheOrderConsistent() {
        let queue = shuffled()
        XCTAssertEqual(nexts(2, on: queue), [5, 3])                 // played 1, 5, 3; then 2, 4
        queue.remove(item(2).id)                                    // unplayed
        XCTAssertEqual(queue.item(after: item(3).id), item(4))
        queue.remove(item(5).id)                                    // played, in the history
        XCTAssertEqual(queue.item(before: item(3).id), item(1), "removed tracks leave the history")
        queue.remove(item(3).id)                                    // the current track: detached
        XCTAssertEqual(queue.item(after: item(3).id), item(4), "the next unplayed track follows")
        XCTAssertEqual(queue.endOfTrack(after: item(3).id), .play(item(4)))
        assertPermutation(queue)
        queue.clear()
        XCTAssertNil(queue.item(after: item(3).id))
        XCTAssertEqual(queue.endOfTrack(after: item(3).id), .stop(cue: nil))
        XCTAssertTrue(queue.shuffledItems.isEmpty)
    }

    func testRequeuingTheDetachedCurrentTrackDoesNotPlayItAgainNext() {
        let queue = shuffled()
        queue.remove(item(1).id)
        queue.playNext(item(1).id)
        XCTAssertEqual(queue.item(after: item(1).id), item(5))
        assertPermutation(queue)
    }

    // MARK: - Toggling, storage, Play Queue (AUD-005-R9, R10, R13)

    func testTogglingStoresNotifiesAndOffRestoresQueueOrder() {
        let queue = PlayQueue(store: PlayQueueStore(directory: directory), seedSource: { 42 })
        queue.setLibrary([1, 2, 3].map(item))
        queue.playbackDidMove(to: item(2).id)
        var notified = 0
        queue.onOrderChange = { notified += 1 }
        queue.toggleShuffle()
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(notified, 1)
        guard case .record(let record) = PlayQueueStore(directory: directory).load() else { return XCTFail() }
        XCTAssertEqual(record.shuffle?.seed, 42)
        XCTAssertEqual(record.shuffle?.order.first, item(2).id, "the current track starts the cycle")
        queue.setShuffle(true)
        XCTAssertEqual(notified, 1, "the same value again changes nothing")
        queue.toggleShuffle()
        XCTAssertFalse(queue.isShuffled)
        XCTAssertNil(queue.shuffleSeed)
        XCTAssertEqual(queue.item(after: item(2).id), item(3), "queue order again")
        XCTAssertEqual(queue.item(before: item(2).id), item(1))
        guard case .record(let off) = PlayQueueStore(directory: directory).load() else { return XCTFail() }
        XCTAssertNil(off.shuffle)
    }

    func testARelaunchContinuesTheCycleAndItsHistory() {
        let queue = shuffled(stored: true)
        XCTAssertEqual(nexts(2, on: queue), [5, 3])
        let relaunched = PlayQueue(store: PlayQueueStore(directory: directory), seedSource: { 7 })
        relaunched.setLibrary([1, 2, 3, 4, 5].map(item))
        XCTAssertTrue(relaunched.isShuffled)
        XCTAssertEqual(relaunched.shuffleSeed, 42)
        XCTAssertEqual(relaunched.startItem, item(3))
        relaunched.playbackDidMove(to: item(3).id, by: .start)     // Play Queue
        XCTAssertEqual(relaunched.item(before: item(3).id), item(5), "the history within the cycle survives")
        XCTAssertEqual(nexts(7, on: relaunched), [2, 4, 1, 4, 3, 5, 2], "the same sequence as without a relaunch")
    }

    func testAMismatchedStoredOrderIsRepaired() throws {
        let one = item(1).id, two = item(2).id, three = item(3).id
        let record = PlayQueueRecord(trackIDs: [one, two, three], currentTrackID: two,
                                     shuffle: .init(seed: 5, cycle: 0, order: [two, "00000000-0000-0000-0000-000000000009"], played: 9))
        try PlayQueueStore(directory: directory).save(record)
        let queue = PlayQueue(store: PlayQueueStore(directory: directory))
        queue.setLibrary([1, 2, 3].map(item))
        XCTAssertEqual(queue.shuffledItems, [item(2), item(1), item(3)], "unknown dropped, missing appended in queue order")
        assertPermutation(queue)
        XCTAssertNotNil(queue.item(after: two))
        XCTAssertNotEqual(queue.item(after: two), item(2), "never the current track again")
    }

    func testANewerRecordKeepsShuffleChangeableButUnstored() throws {
        let newer = Data(#"{"schemaVersion":9}"#.utf8)
        try newer.write(to: directory.appendingPathComponent("queue.json"))
        let queue = PlayQueue(store: PlayQueueStore(directory: directory), seedSource: { 1 })
        queue.setLibrary([1, 2].map(item))
        queue.setShuffle(true)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("queue.json")), newer)
    }

    func testPlayQueueWithoutACurrentTrackStartsTheShuffledOrder() {
        let queue = shuffled(current: nil)
        XCTAssertEqual(queue.startItem, queue.shuffledItems.first)
        XCTAssertNotNil(queue.startItem)
    }

    func testShuffleOffAnswersExactlyAsBefore() {
        let queue = PlayQueue(store: nil, seedSource: { 42 })
        queue.setLibrary([1, 2, 3].map(item))
        XCTAssertFalse(queue.isShuffled)
        XCTAssertEqual(queue.item(after: item(3).id), item(1))
        XCTAssertEqual(queue.item(before: item(1).id), item(3))
        XCTAssertEqual(queue.endOfTrack(after: item(1).id), .play(item(2)))
        XCTAssertTrue(queue.shuffledItems.isEmpty)
    }
}
