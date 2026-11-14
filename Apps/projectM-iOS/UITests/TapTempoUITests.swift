// TapTempoUITests.swift — SHOW-011-T16 on the iOS Simulator: four taps establish a manual tempo
// and Reset tempo returns to the estimated state (the roadmap row's acceptance; SHOW-011-R12, R13).
// `-uitestTapInterval 500` (Debug) spaces the taps exactly 500 ms apart on a synthetic clock, since
// UI taps are not precisely timed. After the reset the readout shows the analysis's state (ANL-006:
// "Searching for tempo", "About … BPM, uncertain" or "… BPM, stable"), depending on what the
// analysis of the reference track has reached; either way it is no longer manual. Simulator
// results are never device evidence (Constitution X). Waits poll every 0.1 s (UITestWaits.swift,
// owner rule 7).
import XCTest

@MainActor
final class TapTempoUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var readout: XCUIElement { app.descendants(matching: .any)["tempoReadout"].firstMatch }
    private var tapButton: XCUIElement { app.buttons["tapTempo"] }
    private var resetButton: XCUIElement { app.buttons["resetTempo"] }
    private var readoutValue: String { (readout.value as? String) ?? "" }

    private func showControls() {
        if !tapButton.appears(within: 0.5) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(tapButton.appears(within: 5))
    }

    func testFourTapsSetTheTempoAndResetClearsIt() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestTapInterval", "500"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        XCTAssertEqual(tapButton.label, "Tap tempo")
        XCTAssertEqual(readout.label, "Tempo")
        XCTAssertFalse(resetButton.exists, "no Reset tempo without a manual tempo")

        tapButton.tap()
        tapButton.tap()
        XCTAssertEqual(tapButton.value as? String, "Tap 2 of 4")
        tapButton.tap()
        XCTAssertFalse(readoutValue.hasSuffix("manual"), "three taps set nothing")
        tapButton.tap()
        XCTAssertTrue(poll(5) { self.readoutValue == "120 BPM, manual" }, readoutValue)
        XCTAssertEqual(tapButton.value as? String, "120 BPM, manual")

        XCTAssertTrue(resetButton.appears(within: 5))
        XCTAssertEqual(resetButton.label, "Reset tempo")
        resetButton.tap()
        XCTAssertTrue(resetButton.disappears(within: 5))
        // ANL-006: the readout shows the analysis's state (searching, uncertain or stable).
        let after: String = readoutValue
        let analysisState: Bool = after == "Searching for tempo" || after.hasSuffix("BPM, uncertain")
            || after.hasSuffix("BPM, stable")
        XCTAssertTrue(analysisState, after)
    }
}
