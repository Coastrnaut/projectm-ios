// RadialWaveformUITests.swift — VIS-005-T10 on the iOS Simulator: choosing Radial Waveform in Settings, Ring and
// Amplitude offered with Medium selected, Bars not offered, choosing Large, the visual shown with "Large ring" in
// its value and the source started once (VIS-005 User Story 1; VIS-005-R9, R11; S6). One short test (owner rule
// 7: under 30 s); the keys' persistence across a relaunch is RadialWaveformAppTests' unit test.
// Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class RadialWaveformUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var radial: XCUIElement { app.descendants(matching: .any)["radialWaveform"].firstMatch }
    private var value: String { radial.value as? String ?? "" }

    func testChoosingRadialWaveformAndLargeRing() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.radialWaveform"]
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let ring = app.segmentedControls["radialWaveformRingPicker"]
        XCTAssertTrue(ring.appears(within: 5), "Ring offered for the radial waveform")
        XCTAssertTrue(ring.buttons["Medium"].isSelected, "Medium ring by default")
        XCTAssertTrue(app.segmentedControls["radialWaveformAmplitudePicker"].buttons["Medium"].isSelected, "Medium amplitude by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply to the radial waveform")
        ring.buttons["Large"].tap()
        XCTAssertTrue(ring.buttons["Large"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(radial.appears(within: 10), "the radial waveform is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("Large ring, Medium amplitude") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
