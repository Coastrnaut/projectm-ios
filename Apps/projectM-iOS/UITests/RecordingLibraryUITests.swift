// RecordingLibraryUITests.swift — REC-010-T10 (REC-010-S6): Settings › Storage › Recordings with three recordings
// generated at launch (DEBUG `-uitestRecordingLibrarySeed 3`); Delete on one row, confirm, and the summary drops to
// two. Under 30 s. Simulator results are never device evidence.
import XCTest

@MainActor
final class RecordingLibraryUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testDeleteWithConfirmationShrinksTheList() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestRecordingLibrarySeed", "3", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "storage"] + Self.noStore   // Settings opens at Storage (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        // Open Settings (see SettingsUITests.openSettings).
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let storage = app.buttons["storageLink"]
        XCTAssertTrue(app.reveal(storage))
        storage.tap()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 5))
        let link = app.buttons["storage.savedRecordings"]
        XCTAssertTrue(link.appears(within: 5), "the Saved recordings row opens Recordings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Recordings"].appears(within: 5))

        let summary = app.staticTexts["recordingLibrarySummary"]
        XCTAssertTrue(summary.appears(within: 5))
        XCTAssertTrue(summary.label.hasPrefix("3 recordings"), summary.label)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "recordingLibraryRow").count, 3)

        app.buttons.matching(identifier: "recordingLibraryDelete").element(boundBy: 1).tap()
        let confirm = app.buttons["recordingLibraryConfirmDelete"].firstMatch
        XCTAssertTrue(confirm.appears(within: 5), "Delete asks first")
        confirm.tap()
        XCTAssertTrue(poll(5) { summary.label.hasPrefix("2 recordings") }, summary.label)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "recordingLibraryRow").count, 2)
    }
}
