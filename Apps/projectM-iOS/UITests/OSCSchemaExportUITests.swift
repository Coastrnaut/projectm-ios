// OSC-010-T07: Export routes… in OSC Routes on the iOS Simulator (contract osc-schema-export.md C2; S5). With
// `-uitestShareSimulation` the out-of-process share sheet is replaced by the REC-012 stand-in buttons and a probe
// whose value is the generated text. OSC stays off: no listener and no network. Simulator results are never device
// evidence; the device check is OSC-010-T09. Budget: under 30 s (owner rule 7).
import XCTest

@MainActor
final class OSCSchemaExportUITests: XCTestCase {
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

    func testExportRoutesPresentsTheShareStandInWithTheRoutes() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestShareSimulation",
                               "-settings.osc.enabled", "NO", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscRoutesLink"]
        XCTAssertTrue(app.reveal(link, long: true), "OSC Routes is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["OSC Routes"].appears(within: 5))

        let export = app.buttons["oscSchemaExport"]
        XCTAssertTrue(app.reveal(export, long: true), "Export routes… is the last section")
        export.tap()
        let completed = app.buttons["simulateShareCompleted"]
        XCTAssertTrue(completed.appears(within: 5), "the share sheet stand-in")
        let probe = app.staticTexts["oscSchemaExport.probe"]
        XCTAssertTrue(probe.exists)
        let text = probe.value as? String ?? ""
        XCTAssertTrue(text.contains("| /projectm/param/glow.intensity | effect.bloom.intensity |"), text)
        XCTAssertTrue(text.contains("| /projectm/test | osc.receiver.testValue |"), text)
        completed.tap()
        XCTAssertTrue(app.staticTexts["oscSchemaExport.notice"].appears(within: 3), "Shared.")
        XCTAssertFalse(completed.exists, "the copy is gone with the stand-in")
    }
}
