// QuantizedCueStepsUITests.swift — SHOW-003-T11 (US2, US3; R1, R5) on the iOS Simulator: with the DEBUG five-cue
// seed and "Quantize cue steps" set to Beat through the launch arguments' defaults domain
// (`-settings.show.quantizeCues beat`) but no tempo (nobody tapped, no analysis beat yet), Next still moves the show
// at once (the explicit fallback) and nothing shows as queued; Settings offers the Quantize cue steps row with Beat
// chosen. The beat timing itself is proven by ShowCueQuantizerAcceptanceTests on an injected clock. Under 30 s (owner
// rule 7). Simulator results are UI evidence only.
import XCTest

@MainActor
final class QuantizedCueStepsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var status: XCUIElement { app.staticTexts["showCueStatus"] }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    func testNoTempoFallbackMovesAtOnceAndSettingsOffersTheMode() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-settings.show.quantizeCues", "beat",
                               "-autostart", "inAppPlayback", "-uitestSettingsSection", "quantizeCues"] + Self.noStore   // owner rule 7
        app.launch()
        if !controls.appears(within: 10) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        XCTAssertEqual(status.value as? String, "Cue 1 of 5, Opening")
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(poll(3) { (self.status.value as? String) == "Cue 2 of 5, Build" },
                      "no tempo: Next moves at once: \(status.value as? String ?? "nil")")
        XCTAssertFalse(app.descendants(matching: .any)["showCueQueued"].exists, "nothing is queued")

        if !app.buttons["settings"].exists { area.tap() }
        app.buttons["settings"].tap()
        let picker = app.descendants(matching: .any).matching(identifier: "quantizeCues.mode").firstMatch
        XCTAssertTrue(picker.appears(within: 5) || app.reveal(picker), "the Quantize cue steps row is shown")
        XCTAssertTrue(picker.label.contains("Quantize cue steps") || (picker.value as? String) == "Beat",
                      "the row: \(picker.label) \(picker.value as? String ?? "")")
        XCTAssertTrue(picker.label.contains("Beat") || (picker.value as? String) == "Beat", "Beat chosen")
    }
}
