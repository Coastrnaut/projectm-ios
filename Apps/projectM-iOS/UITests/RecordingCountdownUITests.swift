// RecordingCountdownUITests.swift — REC-007-T11 on the iOS Simulator: the countdown set to 3 s (its stored key,
// given as a launch argument: scrolling Settings to the section alone took 25 s of the 30 s budget), Record on
// the Photo visual, the countdown is shown with Cancel, Cancel, and no recording indicator and no
// file (the DEBUG probe stays "none"). One short test (owner rule 7: under 30 s); the timing rules are proven
// by `RecordingCountdownAppTests` on a manual clock. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingCountdownUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testCountdownShowsAndCancelRecordsNothing() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestRecordingDirectory", "RecordingCountdownUITests",
                               "-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                               "-settings.recording.countdown", "3"] + Self.noStore   // the stored key (argument domain)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))

        showControls()
        app.buttons["record"].tap()
        let countdown = app.descendants(matching: .any)["recordingCountdown"].firstMatch
        XCTAssertTrue(countdown.appears(within: 3), "the countdown is shown")
        XCTAssertTrue(countdown.label.hasPrefix("Recording in "), countdown.label)
        let cancel = app.buttons["recordingCountdownCancel"]
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        XCTAssertTrue(poll(3) { !countdown.exists }, "the countdown is gone")
        XCTAssertFalse(app.descendants(matching: .any)["recordingIndicator"].firstMatch.exists, "no recording")
        XCTAssertEqual(app.staticTexts["videoRecordingProbe"].value as? String, "none", "nothing was written")
    }
}
