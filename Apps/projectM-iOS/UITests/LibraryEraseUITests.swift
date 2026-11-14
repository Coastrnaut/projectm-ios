// LibraryEraseUITests.swift — FILE-011-T11 (FILE-011-S5): Settings › Storage › Erase on the simulator.
// Launch 1 seeds a show (`-uitestShowSeed`: five scenes) and reads FILE-005's DEBUG records probe; Erase
// Data… → "Scenes and show" → Erase…: the confirmation names the category; Cancel records nothing; then
// Erase at Next Launch shows the pending erase. Launch 2 (no reset, no seed): the erase runs before
// anything loads, the result is shown once and the show's records are gone. `-uitestStorageSheet` opens
// Storage at launch (no audio, no scrolling through Settings). Fixed fake entitlement. Simulator only;
// never device evidence.
import XCTest

@MainActor
final class LibraryEraseUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        app.launchArguments = ["-uitestStorageSheet"] + Self.noStore + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 20), "Storage opens at launch")
    }

    private func probe() -> String {
        let element = app.staticTexts["libraryRecordsProbe"]
        XCTAssertTrue(app.reveal(element))
        XCTAssertTrue(poll(10) { element.label.contains("port") }, element.label)
        return element.label
    }

    private func chooseScenesAndContinue() {
        let button = app.buttons["libraryEraseButton"]
        XCTAssertTrue(app.reveal(button))
        button.tap()
        let row = app.buttons["libraryEraseRow.scenes"]
        XCTAssertTrue(row.appears(within: 10), "the sheet lists the categories")
        XCTAssertTrue(poll(10) { row.value as? String != "Calculating…" }, "counts and sizes arrive")
        row.tap()
        XCTAssertTrue(poll(5) { row.isSelected }, "the row is selected")
        app.buttons["libraryEraseContinue"].tap()
    }

    func testTheConfirmationNamesTheCategoryCancelErasesNothingAndEraseWorksAcrossARelaunch() {
        XCUIDevice.shared.orientation = .portrait
        launch(["-uitestResetNotice", "-uitestShowSeed"])
        let original = probe()
        XCTAssertTrue(original.hasPrefix("6 "), "the show and its five scenes: \(original)")

        chooseScenesAndContinue()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.appears(within: 5), "a confirmation opens")
        XCTAssertTrue(alert.staticTexts["Erase 1 category?"].exists)
        let named = alert.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Scenes and show (")).firstMatch
        XCTAssertTrue(named.exists, "the message names the category with its count")
        alert.buttons["Cancel"].tap()
        app.buttons["libraryEraseDismiss"].tap()
        XCTAssertFalse(app.staticTexts["libraryErasePending"].exists, "Cancel records nothing")
        XCTAssertEqual(probe(), original, "nothing was erased")

        chooseScenesAndContinue()
        XCTAssertTrue(alert.appears(within: 5))
        alert.buttons["Erase at Next Launch"].tap()
        let pending = app.staticTexts["libraryErasePending"]
        XCTAssertTrue(app.reveal(pending))
        XCTAssertTrue(pending.label.contains("Scenes and show will be erased."), pending.label)

        app.terminate()
        launch([])
        let message = app.staticTexts["libraryEraseMessage"]
        XCTAssertTrue(app.reveal(message))
        XCTAssertEqual(message.label, "Erased: scenes and show.")
        XCTAssertFalse(app.staticTexts["libraryErasePending"].exists)
        let after = probe()
        XCTAssertFalse(after.hasPrefix("6 "), "the show's records are gone: \(after)")
        XCTAssertNotEqual(after, original)
    }
}
