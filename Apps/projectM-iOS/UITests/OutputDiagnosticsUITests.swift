// OutputDiagnosticsUITests.swift — OUT-011-T10 on the iOS Simulator: with the fake external display
// (`-uitestExternalDisplay`), Settings › Output Diagnostics shows the display's values, each row a labelled
// accessibility element (OUT-011-R7); after a disconnect it shows "No external display connected" and the hidden
// `externalDiagnostics` probe reads "disconnected". Simulator results are never device evidence (OUT-011-T12 is).
// Owner rule 7: under 30 s.
import XCTest

@MainActor
final class OutputDiagnosticsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: String? { app.descendants(matching: .any)["externalDiagnostics"].firstMatch.value as? String }

    private func row(_ id: String) -> XCUIElement { app.descendants(matching: .any)["outputDiagnostics." + id].firstMatch }

    private func openSettings() {
        app.tapFreshControl("settings")   // retries when the controls auto-hide mid-tap
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    func testThePanelShowsValuesThenDisconnected() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestExternalDisplay", "-uitestSettingsSection", "outputDiagnostics"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.buttons["uitestConnectExternal"].appears(within: 15))
        XCTAssertTrue(poll(3) { self.probe == "disconnected" }, "nothing connected: \(probe ?? "nil")")
        app.buttons["uitestConnectExternal"].tap()
        XCTAssertTrue(poll(5) { (self.probe ?? "").hasPrefix("connected native=1920x1080 pt=1920x1080@1 fps=60") },
                      "the fake display: \(probe ?? "nil")")

        openSettings()
        let native = row("nativeResolution")
        XCTAssertTrue(app.reveal(native), "the diagnostics are reachable")
        XCTAssertEqual(native.label, "Native resolution")
        XCTAssertEqual(native.value as? String, "1920 × 1080 px")
        XCTAssertEqual(row("refreshRate").value as? String, "60 Hz")
        XCTAssertEqual(row("gamut").value as? String, "sRGB")
        XCTAssertTrue(app.buttons["outputDiagnosticsCopy"].exists, "copy is offered while connected")
        closeSettings()

        app.buttons["uitestDisconnectExternal"].tap()
        XCTAssertTrue(poll(3) { self.probe == "disconnected" }, "the probe: \(probe ?? "nil")")
        openSettings()
        let status = row("status")
        XCTAssertTrue(app.reveal(status), "the status row is reachable")
        XCTAssertEqual(status.value as? String, "No external display connected")
        XCTAssertFalse(row("nativeResolution").exists, "no old value remains")
        XCTAssertFalse(app.buttons["outputDiagnosticsCopy"].exists)
    }
}
