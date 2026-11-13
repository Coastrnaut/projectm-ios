// AUD-016-T21: the Diagnostics section of the chooser on the iOS Simulator. Nothing plays until a
// test signal is tapped; a signal plays as In-App Playback and the indicator and the transport name
// it; a relaunch starts at the chooser with nothing playing (AUD-016-R13, R14, R16, S7; US1
// scenarios 1 to 4). Simulator results are never device evidence (AUD-016-T30 is the device check).
import XCTest

@MainActor
final class TestSignalsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }

    private func launch(resetNotice: Bool = true) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (resetNotice ? ["-uitestResetNotice"] : []) + Self.noStore
        app.launch()
        if resetNotice {
            let acknowledge = app.buttons["acknowledgeNotice"]
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
            acknowledge.tap()
        }
    }

    /// The chooser's "Test Signals" row, scrolled into view (the list is lazy).
    private func testSignalsRow(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = app.buttons["testSignals"]
        var swipes = 0
        while !row.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the Diagnostics section's Test Signals row", file: file, line: line)
        return row
    }

    private func play(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        testSignalsRow(file: file, line: line).tap()
        let signal = app.buttons["testSignal.\(id)"]
        var swipes = 0
        while !signal.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(signal.waitForExistence(timeout: 5), "row testSignal.\(id)", file: file, line: line)
        signal.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "the visualizer opened", file: file, line: line)
    }

    private func expectIndicator(_ text: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", text)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: indicator)], timeout: timeout)
        XCTAssertEqual(result, .completed, "indicator \"\(text)\"; it shows \"\(indicator.label)\"", file: file, line: line)
    }

    func testTheChooserListsDiagnosticsAndPlaysNothing() {
        launch()
        XCTAssertTrue(app.buttons["In-App Playback"].waitForExistence(timeout: 10), "the three sources are unchanged")
        let row = testSignalsRow()
        XCTAssertEqual(row.label, "Test Signals")
        XCTAssertTrue(app.staticTexts["Diagnostics"].exists, "the section header")
        XCTAssertFalse(indicator.exists, "nothing started")
        row.tap()
        XCTAssertTrue(app.navigationBars["Test Signals"].waitForExistence(timeout: 5))
        for id in ["sine-1k", "sweep-log", "pulse-120", "silence"] {
            let signal = app.buttons["testSignal.\(id)"]
            var swipes = 0
            while !signal.exists && swipes < 4 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(signal.exists, id)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "These test signals are generated on this device"))
            .firstMatch.waitForExistence(timeout: 5), "the footer explains the signals")
        XCTAssertFalse(indicator.exists, "opening the list starts nothing")
    }

    func testAToneIsNamedInTheIndicatorAndTheTransport() {
        launch()
        play("sine-1k")
        expectIndicator("In-App Playback · Test tone 1 kHz · Active audio")
        let title = app.staticTexts["transportTitle"]
        if !title.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Test tone 1 kHz")
        XCTAssertTrue(app.staticTexts["transportRemaining"].label.hasPrefix("−0:"), "a 10 s loop")
    }

    func testSilenceIsReportedAsSilent() {
        launch()
        play("silence")
        expectIndicator("In-App Playback · Test silence · Audio received — silent")
    }

    func testARelaunchStartsAtTheChooserWithNothingPlaying() {
        launch()
        play("sweep-log")
        expectIndicator("In-App Playback · Test sweep 20 Hz–20 kHz, logarithmic · Active audio")
        app.terminate()
        launch(resetNotice: false)
        XCTAssertTrue(app.buttons["In-App Playback"].waitForExistence(timeout: 10), "the chooser")
        XCTAssertFalse(indicator.exists, "no signal started by itself")
    }
}
