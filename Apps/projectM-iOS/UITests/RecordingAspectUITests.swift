// RecordingAspectUITests.swift — REC-014-T13 on the iOS Simulator: Settings opens at Recording aspect (Match screen,
// Portrait, Square, Landscape, Custom) with Match screen selected; tapping Square selects it and its row names
// the size it records. One short test (owner rule 7: under 30 s); persistence, validation and sizes are proven by
// `RecordingAspectAppTests` and the FrameRecording tests. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RecordingAspectUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func row(_ raw: String) -> XCUIElement { app.buttons["recordingAspect." + raw] }

    func testPickerSelectsSquare() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "recordingAspect"] + Self.noStore   // Settings opens at the section (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        XCTAssertTrue(app.reveal(row("screen")), "Settings › Recording aspect")
        XCTAssertTrue(app.reveal(row("square")))
        XCTAssertTrue(row("screen").isSelected, "Match screen by default")
        XCTAssertFalse(row("square").isSelected)
        row("square").tap()
        XCTAssertTrue(poll(5) { self.row("square").isSelected }, row("square").label)
        XCTAssertFalse(row("screen").isSelected)
        XCTAssertTrue(row("square").label.hasPrefix("Square 1:1, "), row("square").label)
    }
}
