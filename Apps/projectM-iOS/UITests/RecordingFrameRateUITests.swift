// RecordingFrameRateUITests.swift — REC-006-T13 on the iOS Simulator: Settings → Recording frame rate lists
// Profile default, 24, 30 and 60 fps with Profile default selected; tapping 24 fps selects it. One short test
// (owner rule 7: under 30 s); persistence and disabled rows are proven by `RecordingFrameRateAppTests`.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingFrameRateUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func row(_ raw: String) -> XCUIElement { app.buttons["recordingFrameRate." + raw] }

    func testPickerSelectsARate() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        XCTAssertTrue(app.reveal(row("60"), long: true), "the four rates are in Settings › Recording frame rate")
        for raw in ["profile", "24", "30", "60"] {
            XCTAssertTrue(row(raw).exists, raw)
        }
        XCTAssertTrue(row("profile").isSelected, "Profile default by default")
        XCTAssertEqual(row("profile").label, "Profile default (30 fps)")
        XCTAssertFalse(row("24").isSelected)
        row("24").tap()
        XCTAssertTrue(poll(5) { self.row("24").isSelected }, row("24").label)
        XCTAssertFalse(row("profile").isSelected)
    }
}
