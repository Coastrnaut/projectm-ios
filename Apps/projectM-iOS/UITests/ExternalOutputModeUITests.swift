// ExternalOutputModeUITests.swift — OUT-006-T09 on the iOS Simulator: with the fake external display
// (`-uitestExternalDisplay`), Settings › External Display › Output › Clean output routes the scene overlays
// away from the display live (hidden `externalOutputMode` probe), the visual stays on the display alone, and
// the audio source is started once throughout. Simulator results are never device evidence (OUT-006-T10 is).
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ExternalOutputModeUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String? { app.descendants(matching: .any)["externalOutputMode"].firstMatch.value as? String }
    private var starts: String? { app.staticTexts["sourceStarts"].value as? String }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func choose(_ picker: String, _ option: String) {
        let row = app.buttons[picker]
        XCTAssertTrue(app.reveal(row), "\(picker) is reachable")
        row.tap()
        let button = app.buttons[option].firstMatch, text = app.staticTexts[option].firstMatch
        XCTAssertTrue(poll(3) { button.exists || text.exists }, "\(option) is listed")
        (button.exists ? button : text).tap()
    }

    func testCleanOutputChangesTheExternalRoutingLiveWithOneCapture() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { self.probe == "mode=sameScene target=external overlays=shown externalViews=1" },
                      "Same scene on the display: \(probe ?? "nil")")

        showControls()
        app.buttons["settings"].tap()
        choose("externalOutputModePicker", "Clean output")
        XCTAssertTrue(poll(3) { self.probe == "mode=clean target=external overlays=hidden externalViews=1" },
                      "Clean output, live, the visual still alone on the display: \(probe ?? "nil")")
        app.navigationBars["Settings"].buttons["Done"].tap()

        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(poll(3) { self.probe == "mode=clean target=device overlays=shown externalViews=0" },
                      "the device always shows the whole scene: \(probe ?? "nil")")
        XCTAssertEqual(starts, "1", "one capture: the source was started once")
    }
}
