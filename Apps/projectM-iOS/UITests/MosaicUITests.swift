// MosaicUITests.swift — FX-012-T15 on the iOS Simulator: Settings → Mosaic is off by default with no controls;
// turning it on shows Block size at "8 px" and the shape choice; moving the slider to the end reads "64 px" and Hexagon
// can be chosen (FX-012-R8, S6). One short test (owner rule 7: under 30 s); persistence across a relaunch is proven by
// `MosaicSettingTests.testMosaicOffByDefaultPersistedAndClamped`. Simulator results are never device evidence.
import XCTest

@MainActor
final class MosaicUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchMosaic() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "mosaic"] + Self.noStore   // Settings opens at Mosaic (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var mosaicToggle: XCUIElement { app.switches["mosaicToggle"] }
    private var mosaicSize: XCUIElement { app.slider("mosaicSizeSlider") }
    private func mosaicIsOn() -> Bool { (mosaicToggle.value as? String) == "1" }

    func testMosaicControls() {
        launchMosaic()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(mosaicToggle), "Mosaic is in Settings")
        XCTAssertFalse(mosaicIsOn(), "off by default")
        XCTAssertFalse(mosaicSize.exists, "no controls while off")
        mosaicToggle.switches.firstMatch.exists ? mosaicToggle.switches.firstMatch.tap() : mosaicToggle.tap()
        XCTAssertTrue(poll(5) { self.mosaicIsOn() })
        XCTAssertTrue(mosaicSize.appears(within: 3) || app.reveal(mosaicSize), "Block size appears once on")
        XCTAssertEqual(app.staticTexts["mosaicSizeSliderValue"].label, "8 px", "the default block size")
        // Drag from the thumb's current place (read from the readout) to the end; a drag that lands off the thumb while
        // the row settles is retried (at most three drags).
        for _ in 0..<3 where app.staticTexts["mosaicSizeSliderValue"].label != "64 px" {
            let shown: Int = Int(app.staticTexts["mosaicSizeSliderValue"].label.split(separator: " ").first ?? "8") ?? 8
            mosaicSize.dragSlider(from: CGFloat(shown - 1) / 63, to: 1)
            _ = poll(3) { self.app.staticTexts["mosaicSizeSliderValue"].label == "64 px" }
        }
        XCTAssertEqual(app.staticTexts["mosaicSizeSliderValue"].label, "64 px", "capped at 64 px")
        let hexagon: XCUIElement = app.segmentedControls["mosaicShapePicker"].buttons["Hexagon"]
        XCTAssertTrue(hexagon.exists || app.reveal(hexagon), "the shape choice")
        hexagon.tap()
        XCTAssertTrue(poll(3) { hexagon.isSelected }, "Hexagon chosen")
    }
}
