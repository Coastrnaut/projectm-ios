// RepeatStringsTests.swift — the repeat control's strings and icons (AUD-004-T11; AUD-004-R12,
// R13; specs/017-aud-004-loop-track-and-queue/contracts/ui-strings.md). No SwiftUI: runs on Linux too.
import CaptureKit
import XCTest
@testable import CaptureUI

final class RepeatStringsTests: XCTestCase {
    func testLabelAndValues() {
        XCTAssertEqual(UIStrings.repeatLabel, "Repeat")
        XCTAssertEqual(UIStrings.repeatValue(.off), "Off")
        XCTAssertEqual(UIStrings.repeatValue(.one), "One Track")
        XCTAssertEqual(UIStrings.repeatValue(.all), "All Tracks")
    }

    func testAnnouncement() {
        XCTAssertEqual(UIStrings.repeatAnnouncement(.off), "Repeat: Off")
        XCTAssertEqual(UIStrings.repeatAnnouncement(.one), "Repeat: One Track")
        XCTAssertEqual(UIStrings.repeatAnnouncement(.all), "Repeat: All Tracks")
    }

    func testFooter() {
        XCTAssertEqual(UIStrings.repeatFooter,
                       "Off stops after the last track. One Track repeats the current track. All Tracks starts the queue again after the last track.")
    }

    func testIconsTellOneTrackApart() {
        XCTAssertEqual(UIStrings.repeatIcon(.off), "repeat")
        XCTAssertEqual(UIStrings.repeatIcon(.all), "repeat")
        XCTAssertEqual(UIStrings.repeatIcon(.one), "repeat.1")
    }

    func testTheQueueScreenListsTheModesInOrder() {
        XCTAssertEqual(UIStrings.repeatChoices, [.off, .one, .all])
    }
}
