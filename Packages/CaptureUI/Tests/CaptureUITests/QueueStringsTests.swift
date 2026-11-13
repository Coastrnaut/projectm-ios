// QueueStringsTests.swift — the queue's strings (AUD-003-T14; AUD-003-R11, R17;
// specs/015-aud-003-audio-library-queue/contracts/ui-strings.md). No SwiftUI: runs on Linux too.
import XCTest
@testable import CaptureUI

final class QueueStringsTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(UIStrings.queue, "Queue")
        XCTAssertEqual(UIStrings.queueHint, "Shows and edits the order of imported tracks.")
        XCTAssertEqual(UIStrings.upNext, "Up Next")
        XCTAssertEqual(UIStrings.notInQueue, "Not in Queue")
        XCTAssertEqual(UIStrings.queueEmpty, "Nothing is queued. Add tracks below.")
        XCTAssertEqual(UIStrings.queueFooter,
                       "Next track and the end of a track follow this order. Removing a track from the queue keeps it in Your Audio.")
        XCTAssertEqual(UIStrings.nowPlaying, "Now Playing")
        XCTAssertEqual(UIStrings.currentTrack, "Current")
        XCTAssertEqual(UIStrings.playQueue, "Play Queue")
        XCTAssertEqual(UIStrings.playNext, "Play Next")
        XCTAssertEqual(UIStrings.addToQueue, "Add to Queue")
        XCTAssertEqual(UIStrings.removeFromQueue, "Remove from Queue")
        XCTAssertEqual(UIStrings.moveUp, "Move Up")
        XCTAssertEqual(UIStrings.moveDown, "Move Down")
        XCTAssertEqual(UIStrings.clearQueue, "Clear Queue")
        XCTAssertEqual(UIStrings.clearQueueConfirm, "Clear the queue? Tracks stay in Your Audio.")
        XCTAssertEqual(UIStrings.done, "Done")
    }

    func testQueueRowCountsTracks() {
        XCTAssertEqual(UIStrings.queueRowLabel(count: 0), "Queue, empty")
        XCTAssertEqual(UIStrings.queueRowLabel(count: 1), "Queue, 1 track")
        XCTAssertEqual(UIStrings.queueRowLabel(count: 3), "Queue, 3 tracks")
    }

    func testPositionAndRowLabel() {
        XCTAssertEqual(UIStrings.queuePosition(2, of: 3), "2 of 3")
        XCTAssertEqual(UIStrings.queueRowAccessibilityLabel(title: "Song", durationSeconds: 65, position: 2, count: 3, marker: nil),
                       "Song, 1 minute 5 seconds, 2 of 3")
        XCTAssertEqual(UIStrings.queueRowAccessibilityLabel(title: "Song", durationSeconds: 60, position: 1, count: 1,
                                                            marker: UIStrings.nowPlaying),
                       "Song, 1 minute, 1 of 1, Now Playing")
    }

    func testAnnouncements() {
        XCTAssertEqual(UIStrings.queueMovedAnnouncement(title: "Song", position: 2, count: 3), "Song, now 2 of 3")
        XCTAssertEqual(UIStrings.queueAddedAnnouncement(title: "Song"), "Song added to the queue")
        XCTAssertEqual(UIStrings.playNextAnnouncement(title: "Song"), "Song plays next")
        XCTAssertEqual(UIStrings.queueRemovedAnnouncement(title: "Song"), "Song removed from the queue")
    }
}
