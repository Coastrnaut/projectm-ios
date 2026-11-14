// StorageUsageUITests.swift — FILE-009-T09 (FILE-009-S4): Settings › Storage on the simulator with the
// DEBUG fixture container (`-uitestStorageFixture`: known sizes, the real stores untouched). The seeded
// sizes appear; after "Add Test Recording" and Refresh, Recordings and the total grow and Photos does
// not change; FILE-008: the shared-copies note shows the fixture's saving. Simulator results are never device evidence.
import XCTest

@MainActor
final class StorageUsageUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func row(_ id: String) -> XCUIElement { app.descendants(matching: .any)["storage.\(id)"].firstMatch }

    private func value(_ id: String) -> String { (row(id).value as? String) ?? "" }

    func testStorageShowsSeededSizesAndRefreshAddsToRecordings() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestStorageFixture", "-uitestDiagnostics", "-autostart", "inAppPlayback",
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

        let link = app.buttons["storageLink"]
        XCTAssertTrue(app.reveal(link), "Storage is in the last Settings section (built once scrolled near)")
        link.tap()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 5))

        XCTAssertTrue(poll(10) { self.value("recordings") == "1 MB" }, "seeded recording: \(value("recordings"))")
        XCTAssertEqual(value("photos"), "2 MB")
        XCTAssertEqual(value("videos"), "5 MB")
        XCTAssertEqual(value("importedAudio"), "3 MB")
        XCTAssertEqual(row("photos").label, "Photos")
        let totalBefore = value("total")
        XCTAssertFalse(totalBefore.isEmpty)

        let add = app.buttons["storageAddFixture"]
        XCTAssertTrue(app.reveal(add))
        add.tap()
        app.buttons["storageRefresh"].tap()
        // Back up to the category rows: the list is lazy and the FILE-008 note adds a section above the button.
        XCTAssertTrue(app.reveal(row("recordings"), down: true))
        XCTAssertTrue(poll(10) { self.value("recordings") == "3 MB" }, "after adding 2 MB: \(value("recordings"))")
        XCTAssertTrue(app.reveal(row("total"), down: true))
        XCTAssertNotEqual(value("total"), totalBefore, "the total grows")
        XCTAssertTrue(app.reveal(row("photos"), down: true))
        XCTAssertEqual(value("photos"), "2 MB", "other categories do not change")
        XCTAssertFalse(app.staticTexts["storageIncomplete"].exists)
        // FILE-008-S6: the fixture's photo payload is shared by two references; Photos counts it once
        // ("2 MB" above) and the note below Clear Caches shows the saving.
        let shared = app.staticTexts["storageSharedSavings"]
        XCTAssertTrue(app.reveal(shared), "the shared-copies note")
        XCTAssertEqual(shared.label, "Shared copies of identical photos and videos save 4 KB.")
    }
}
