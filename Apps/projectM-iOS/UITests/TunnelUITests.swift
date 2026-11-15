// TunnelUITests.swift — VIS-015-T10 on the iOS Simulator: choosing Tunnel in Settings, Pace offered at "1 ring" (per
// beat), Bars not offered, choosing "2 rings", the visual shown with that pace in its value and the source
// started once (VIS-015 User Story 4; VIS-015-R9, R12; S6). One short test (owner rule 7: under 30 s); persistence across
// a relaunch is TunnelAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class TunnelUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var tunnel: XCUIElement { app.descendants(matching: .any)["tunnel"].firstMatch }
    private var value: String { tunnel.value as? String ?? "" }

    func testChoosingTunnelAndADoublePace() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.tunnel"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let pace = app.segmentedControls["tunnelPacePicker"]
        if !pace.appears(within: 2) { app.reveal(pace) }
        XCTAssertTrue(pace.appears(within: 5), "Pace offered")
        XCTAssertTrue(pace.buttons["1 ring"].isSelected, "1 ring per beat by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        pace.buttons["2 rings"].tap()
        XCTAssertTrue(pace.buttons["2 rings"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(tunnel.appears(within: 10), "the tunnel is shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("2 rings per beat") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
