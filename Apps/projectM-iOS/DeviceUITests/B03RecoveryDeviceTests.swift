// B03RecoveryDeviceTests.swift — QA-011 owner session B03 ("Debug fault injection and crash recovery"), automated
// on D1. PERF-010-T15: a real crash with the DEBUG "Crash now" button (fatalError, not terminate), then a relaunch
// from the test as from the Home Screen: the session recovery offer is shown and the decision is "abnormal".
import UIKit
import XCTest

@MainActor
final class B03RecoveryDeviceTests: DeviceAcceptanceCase {
    private var probe: String { app.staticTexts["sessionRecovery"].value as? String ?? "" }
    private var autosave: String { app.staticTexts["sceneAutosave"].value as? String ?? "" }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { return }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    private func launchForRecovery(reset: Bool) {
        let values: [String: Any] = ["settings.visual": "circularSpectrum"]
        let json = (try? JSONSerialization.data(withJSONObject: values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        app.launchArguments = (reset ? ["-uitestResetNotice", "-uitestDefaults", json] : [])
            + ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestSessionRecovery", "-uitestUnlocked", "NO",
               "-uitestSettingsSection", "storage"]
        app.launch()
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists }, "the source started")
    }

    /// PERF-010-T15: a real crash (DEBUG button), relaunch: the recovery offer and the abnormal decision.
    func testPERF010RealCrashThenRelaunchOffersRecovery() {
        let task = "PERF-010-T15"
        launchForRecovery(reset: true)
        XCTAssertTrue(wait(10) { self.probe.hasPrefix("decision=clean") }, "fresh start: \(probe)")
        // Commit a scene: closing Settings commits at once (SCN-002-R3).
        openSettings()
        closeSettings()
        XCTAssertTrue(wait(10) { self.autosave.contains("pending=0") && !self.autosave.contains("committed=0") },
                      "the scene is committed: \(autosave)")
        openSettings()
        let crash = app.buttons["debugCrashButton"]
        XCTAssertTrue(wait(5) { crash.exists }, "the DEBUG crash button is shown (Settings opens at Storage)")
        crash.tap()
        XCTAssertTrue(wait(10) { self.app.state == .notRunning }, "the app ended abnormally")
        report(task, "crash", ["notRunning": app.state == .notRunning ? 1 : 0])
        launchForRecovery(reset: false)
        let offer = app.descendants(matching: .any)["sessionRecoveryOffer"].firstMatch
        XCTAssertTrue(wait(10) { offer.exists }, "the recovery offer is shown after the real crash")
        XCTAssertTrue(wait(5) { self.probe.hasPrefix("decision=abnormal") }, "decision is abnormal: \(probe)")
        report(task, "relaunch", ["offerShown": offer.exists ? 1 : 0])
        screen(task, "recovery offer")
    }
}
