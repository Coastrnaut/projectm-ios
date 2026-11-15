// ShowBeatGridUITests.swift — SHOW-010-T09 on the iOS Simulator (SHOW-010-S4): with the SHOW-001 DEBUG seed and
// `-uitestShowTimelineSeed` (a 2:30 timeline) and ANL-006's `-uitestTempoEstimate 120:0.9` (an estimate of 120 BPM at
// confidence 0.9, no beat time: the grid starts at 0:00), the timeline row shows the beat grid readout and draws ticks
// (the DEBUG probe `-uitestBeatGridProbe` reports them; the ticks themselves are hidden from VoiceOver). The real tempo
// coordinator, transport and row are in the loop; only the estimate is fake. Simulator results are never device
// evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ShowBeatGridUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    func testTheTimelineShowsA120BPMGrid() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestShowSeed", "-uitestShowTimelineSeed", "-autostart", "inAppPlayback",
                               "-uitestKeepControls", "-uitestTempoEstimate", "120:0.9", "-uitestBeatGridProbe"] + Self.noStore
        app.launch()
        if !controls.appears(within: 10) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")

        let readout: XCUIElement = app.staticTexts["showBeatGridReadout"]
        XCTAssertTrue(readout.appears(within: 5), "the grid readout is in the timeline row")
        XCTAssertEqual(readout.label, "Beat grid")
        var value = ""
        XCTAssertTrue(poll(10) { value = (readout.value as? String) ?? ""; return value.hasPrefix("120 BPM, detected, bar ") },
                      "the readout speaks the tempo and position: \(value)")

        let probe: XCUIElement = app.staticTexts["showBeatGridProbe"]
        XCTAssertTrue(probe.appears(within: 3))
        var summary = ""
        XCTAssertTrue(poll(3) {
            summary = probe.label
            let parts: [Substring] = summary.split(separator: " ")
            return parts.count == 4 && (Int(parts[1]) ?? 0) > 0
        }, "ticks are drawn on the scrub track: \(summary)")
    }
}
