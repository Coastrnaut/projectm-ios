// ExternalRehearsalUITests.swift — OUT-012-T09 (OUT-012-S4) on the iOS Simulator: Settings › External
// Display › "Rehearse output…" opens the rehearsal; with Shape Device the hidden DEBUG `rehearsalProbe`
// reads the 16:9 1080p profile and pillarbox bars, the preview's VoiceOver label says so, and Done
// closes it. No external display (fake or real) is involved. Owner rule 7: under 30 s. Simulator
// results are never device evidence (OUT-012-T11 is).
import XCTest

@MainActor
final class ExternalRehearsalUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String? { app.descendants(matching: .any)["rehearsalProbe"].firstMatch.value as? String }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testTheRehearsalPreviewReadsTheProfileAndBars() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "externalDisplay"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["visualizer"].firstMatch.appears(within: 15))

        showControls()
        app.buttons["settings"].tap()
        let rehearse = app.buttons["externalRehearseButton"]
        XCTAssertTrue(app.reveal(rehearse), "Rehearse output… is reachable")
        XCTAssertTrue(rehearse.isEnabled, "no display connected")
        rehearse.tap()

        XCTAssertTrue(app.buttons["rehearsalDone"].appears(within: 5), "the rehearsal is open")
        XCTAssertTrue(poll(3) { (self.probe ?? "").hasPrefix("profile=1920x1080 par=1.00 fit=fit shape=display") },
                      "default profile with the stored setting: \(probe ?? "nil")")
        let device = app.segmentedControls["rehearsalShapePicker"].buttons["Device"]
        XCTAssertTrue(device.appears(within: 3))
        device.tap()
        XCTAssertTrue(poll(3) { (self.probe ?? "").hasSuffix("bars=pillarbox") }, "portrait device on 16:9: \(probe ?? "nil")")
        XCTAssertTrue(probe?.hasPrefix("profile=1920x1080 par=1.00 fit=fit shape=device") == true, probe ?? "nil")
        let preview = app.descendants(matching: .any)["rehearsalPreview"].firstMatch
        XCTAssertEqual(preview.label, "Previewing 16 by 9 display, fit, pillarbox")

        app.buttons["rehearsalDone"].tap()
        XCTAssertTrue(app.buttons["rehearsalDone"].disappears(within: 5), "Done ends the rehearsal")
        XCTAssertTrue(app.navigationBars["Settings"].exists, "back in Settings")
    }
}
