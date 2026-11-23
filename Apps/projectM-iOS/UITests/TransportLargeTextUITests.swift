// AUD-006-T41 (simulator rehearsal, QA-011 D1 rerun 2026-11-23): at the largest text size on an iPhone, imported
// audio's transport (Previous, Play/Pause, Stop, Next, Shuffle, Repeat, Queue; about 66 pt per icon at AX5) must stay
// inside the window. One row needed about 470 pt and widened the controls, and the whole screen, past a 390 pt
// iPhone; TransportBar now moves Shuffle, Repeat and Queue to a second row when one row does not fit.
// Layout only (the simulator is never device evidence); the device test is B05's testAUD006TransportAtLargestTextSize.
import XCTest

@MainActor
final class TransportLargeTextUITests: XCTestCase {
    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testTransportStaysInsideTheWindowAtAX5() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        let defaults = "{\"settings.performanceOverlay\":false,\"settings.visual\":\"linearSpectrum\"}"
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO",
                               "-uitestDefaults", defaults, "-uitestResetAudioLibrary", "-uitestSeedAudio", "ramps",
                               "-uitestImportAudio", "ramp-seek.wav", "-uitestPlayImported", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        let queue = app.buttons["transportQueue"]
        // The controls show at launch and hide 5 s later; a tap toggles them.
        XCTAssertTrue(queue.waitForExistence(timeout: 20), "imported audio's transport with Queue")
        if !controls.exists { area.tap() }
        if !controls.waitForExistence(timeout: 2) { area.tap() }
        XCTAssertTrue(controls.waitForExistence(timeout: 3), "the controls are shown")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(controls.frame.width, window.width, "the controls are no wider than the window: \(controls.frame)")
        for id in ["transportPrevious", "transportPlayPause", "transportStop", "transportNext", "transportShuffle",
                   "transportRepeat", "transportQueue"] {
            let frame = app.buttons[id].frame
            XCTAssertTrue(frame.minX >= window.minX && frame.maxX <= window.maxX, "\(id) lies across the window's width: \(frame)")
        }
        let scrubber = app.descendants(matching: .any)["transportScrubber"].firstMatch.frame
        XCTAssertTrue(scrubber.minX >= window.minX && scrubber.maxX <= window.maxX, "the scrubber fits the width: \(scrubber)")
    }
}
