// ShuffleStringsTests.swift — the Shuffle control's strings and icon (AUD-005-T11; AUD-005-R11, R12;
// specs/023-aud-005-shuffle-with-history/contracts/ui-strings.md). No SwiftUI: runs on Linux too.
import XCTest
@testable import CaptureUI

final class ShuffleStringsTests: XCTestCase {
    func testLabelValuesAndAnnouncement() {
        XCTAssertEqual(UIStrings.shuffleLabel, "Shuffle")
        XCTAssertEqual(UIStrings.shuffleValue(true), "On")
        XCTAssertEqual(UIStrings.shuffleValue(false), "Off")
        XCTAssertEqual(UIStrings.shuffleAnnouncement(true), "Shuffle: On")
        XCTAssertEqual(UIStrings.shuffleAnnouncement(false), "Shuffle: Off")
    }

    func testIconAndFooter() {
        XCTAssertEqual(UIStrings.shuffleIcon, "shuffle")
        XCTAssertEqual(UIStrings.shuffleFooter,
                       "Shuffle plays the queue in a random order without changing it. Previous goes back through the tracks you played.")
    }
}
