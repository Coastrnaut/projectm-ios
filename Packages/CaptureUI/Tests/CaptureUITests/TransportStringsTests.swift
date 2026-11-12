// TransportStringsTests.swift — the transport's strings and time formats (AUD-006-T26;
// AUD-006-R24, R26, R27; specs/007-aud-006-seekable-transport/contracts/ui-strings.md).
import XCTest
@testable import CaptureUI

final class TransportStringsTests: XCTestCase {
    func testControlLabels() {
        XCTAssertEqual(UIStrings.transportPlay, "Play")
        XCTAssertEqual(UIStrings.transportPause, "Pause playback")
        XCTAssertEqual(UIStrings.transportStop, "Stop playback")
        XCTAssertEqual(UIStrings.previousTrack, "Previous track")
        XCTAssertEqual(UIStrings.nextTrack, "Next track")
        XCTAssertEqual(UIStrings.transportScrubber, "Playback position")
        XCTAssertEqual(UIStrings.referenceTrackTitle, "Reference track")
        XCTAssertEqual(UIStrings.scrubStepSeconds, 10)
    }

    func testPlayPauseLabelSaysWhatATapDoes() {
        XCTAssertEqual(UIStrings.transportPlayPause(isPlaying: true), "Pause playback")
        XCTAssertEqual(UIStrings.transportPlayPause(isPlaying: false), "Play")
    }

    func testTransportLabelsDifferFromTheExistingControls() {
        // The existing Stop leaves the visualizer, Pause freezes the picture, Previous and Next
        // change the preset (AUD-006-R23): no transport label may be mistaken for one of them.
        let existing: Set<String> = [UIStrings.stop, "Pause", "Resume", "Previous", "Next", "Random", "Presets", "Settings"]
        for label in [UIStrings.transportPlay, UIStrings.transportPause, UIStrings.transportStop, UIStrings.previousTrack,
                      UIStrings.nextTrack, UIStrings.transportScrubber] {
            XCTAssertFalse(existing.contains(label), label)
        }
    }

    func testElapsedAndRemainingTimes() {
        XCTAssertEqual(UIStrings.elapsedTime(0), "0:00")
        XCTAssertEqual(UIStrings.elapsedTime(65.9), "1:05")
        XCTAssertEqual(UIStrings.elapsedTime(3_725), "1:02:05")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 115, duration: 180), "−1:05")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 180, duration: 180), "−0:00")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 0.9, duration: 2), "−0:02", "whole seconds: elapsed 0:00 plus remaining 0:02")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 1.2, duration: 2), "−0:01")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 200, duration: 180), "−0:00")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: 100, duration: 7_300), "−2:00:00")
        XCTAssertEqual(UIStrings.remainingTime(elapsed: .nan, duration: .infinity), "−0:00")
        XCTAssertTrue(UIStrings.remainingTime(elapsed: 1, duration: 5).hasPrefix("\u{2212}"), "a real minus sign")
    }

    func testScrubberValueForVoiceOver() {
        XCTAssertEqual(UIStrings.scrubberValue(elapsed: 65, duration: 180), "1 minute 5 seconds of 3 minutes")
        XCTAssertEqual(UIStrings.scrubberValue(elapsed: 0, duration: 60), "0 seconds of 1 minute")
        XCTAssertEqual(UIStrings.scrubberValue(elapsed: 3_661, duration: 7_200), "1 hour 1 minute 1 second of 2 hours")
    }
}
