// OSC-004-T10: OSC learn on the iOS Simulator with the DEBUG stand-in OSC source (`-uitestFakeOSC`; OSC-004-R1, S4).
// OSC is on at launch over the stand-in transport (no socket, no Local Network prompt) and no aliases are stored;
// open OSC Routes, tap Learn beside Glow intensity, send `/fader/7 0.5` from the stand-in controller, and read the
// status and the new alias row. Simulator results are never device evidence; a LAN controller on D1 is the {device}
// task OSC-004-T14. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCLearnUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testArmInjectBound() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestFakeOSC",
                               "-settings.osc.enabled", "YES", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscRoutesLink"]
        XCTAssertTrue(app.reveal(link, long: true), "OSC Routes is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["OSC Routes"].appears(within: 5))

        let learn = app.buttons["oscLearn.effect.bloom.intensity"]
        XCTAssertTrue(learn.appears(within: 5))
        XCTAssertTrue(poll(5) { learn.isEnabled }, "Learn is enabled while the receiver listens")
        learn.tap()
        let status = app.staticTexts["oscLearnStatus"]
        XCTAssertTrue(poll(5) { ((status.value as? String) ?? "").hasPrefix("Send a message") },
                      "learning: \(String(describing: status.value))")

        app.buttons["oscFakeSend"].tap()   // /fader/7 0.5 from 192.168.1.20
        XCTAssertTrue(poll(5) { status.value as? String == "Glow intensity now listens to /fader/7." },
                      "status: \(String(describing: status.value))")
        XCTAssertFalse(app.buttons["oscLearnCancel"].exists, "learn mode exited")
        let row = app.switches["oscRoute_fader_7"]
        XCTAssertTrue(app.reveal(row), "the learned alias is listed")
        XCTAssertEqual(row.value as? String, "1", "on")
    }
}
