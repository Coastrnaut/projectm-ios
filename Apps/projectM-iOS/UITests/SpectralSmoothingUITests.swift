// SpectralSmoothingUITests.swift — ANL-003-T07 on the iOS Simulator: the Attack and Release rows
// (ANL-003 User Story 1; ANL-003-R6, R9; S5): Instant by default, offered for the circular spectrum
// and not for the oscilloscope, labeled for VoiceOver, the source started once (persistence across a
// relaunch: SpectralSmoothingAppTests). One short test (owner rule 7: under 30 s).
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class SpectralSmoothingUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    /// The Smoothing section sits below the Visual section; swipe until the row is on screen.
    private func reveal(_ element: XCUIElement) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) on screen")
    }

    private var attack: XCUIElement { app.segmentedControls["smoothingAttackPicker"] }
    private var release: XCUIElement { app.segmentedControls["smoothingReleasePicker"] }

    func testAttackAndReleaseAreOfferedForSpectraOnly() {
        launch(reset: true)
        openSettings()
        app.buttons["visual.oscilloscope"].tap()
        XCTAssertTrue(app.segmentedControls["oscilloscopeLinePicker"].appears(within: 5))
        app.swipeUp()
        XCTAssertFalse(attack.exists, "no Attack row for the oscilloscope")
        XCTAssertFalse(release.exists, "no Release row for the oscilloscope")
        app.swipeDown()
        app.buttons["visual.circularSpectrum"].tap()
        reveal(release)
        XCTAssertTrue(attack.exists, "Attack offered for the circular spectrum")
        XCTAssertEqual(attack.label, "Attack")
        XCTAssertEqual(release.label, "Release")
        XCTAssertTrue(attack.buttons["Instant"].isSelected, "Instant by default")
        XCTAssertTrue(release.buttons["Instant"].isSelected, "Instant by default")
        attack.buttons["50 ms"].tap()
        release.buttons["500 ms"].tap()
        XCTAssertTrue(attack.buttons["50 ms"].isSelected)
        XCTAssertTrue(release.buttons["500 ms"].isSelected)
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
        // Persistence across a relaunch is SpectralSmoothingAppTests' (a relaunch and a second Settings
        // scroll pushed this test to 47 s, past its 30 s budget).
    }
}
