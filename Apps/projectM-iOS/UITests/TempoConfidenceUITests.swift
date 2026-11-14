// TempoConfidenceUITests.swift — ANL-006-T08 on the iOS Simulator: the tempo readout shows the
// indicator's state and changes it (ANL-006-R8, S5). `-uitestTempoEstimate 120:0.9:40:0.3` (Debug)
// makes the analysis poll report 120 BPM at confidence 0.9 for 40 polls (10 s), then 0.3: the
// readout becomes "120 BPM, stable" after the 2 s dwell, then "About 120 BPM, uncertain" 1 s after
// the drop. The real coordinator, indicator and view are in the loop; only the estimate is fake.
// Simulator results are never device evidence (Constitution X). Waits poll every 0.1 s.
import XCTest

@MainActor
final class TempoConfidenceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var readout: XCUIElement { app.descendants(matching: .any)["tempoReadout"].firstMatch }
    private var tapButton: XCUIElement { app.buttons["tapTempo"] }

    /// The readout's value (`-uitestKeepControls` keeps the controls up, ACC-004).
    private func readoutValue() -> String { (readout.value as? String) ?? "" }

    func testTheReadoutShowsStableThenUncertain() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestKeepControls", "-uitestTempoEstimate", "120:0.9:40:0.3"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !tapButton.appears(within: 0.5) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(readout.appears(within: 5))
        var stable = ""
        XCTAssertTrue(poll(12) { stable = self.readoutValue(); return stable == "120 BPM, stable" }, stable)
        XCTAssertEqual(readout.label, "Tempo")
        var later = ""
        XCTAssertTrue(poll(14) { later = self.readoutValue(); return later == "About 120 BPM, uncertain" }, later)
    }
}
