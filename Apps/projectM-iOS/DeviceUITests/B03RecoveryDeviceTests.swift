// B03RecoveryDeviceTests.swift — QA-011 owner session B03 ("Debug fault injection and crash recovery"), automated
// on D1. PERF-010-T15: a real crash with the DEBUG "Crash now" button (fatalError, not terminate), then a relaunch
// from the test as from the Home Screen: the session recovery offer is shown and the decision is "abnormal".
// SCN-002-T10: a force quit from the app switcher (SystemUI) right after an uncommitted edit; the relaunch restores a
// committed scene.
import UIKit
import XCTest

@MainActor
final class B03RecoveryDeviceTests: DeviceAcceptanceCase {
    /// The crash is the point of the test: XCTest records "<bundle> crashed" (asynchronously, often after the
    /// relaunch) as an issue. While this is set, only that issue is dropped and logged; every other one still fails.
    private var crashExpected = false

    override func record(_ issue: XCTIssue) {
        if crashExpected, issue.compactDescription.hasSuffix("org.projectmios.ProjectMiOS crashed") {
            print("B03: expected crash recorded and accepted: \(issue.compactDescription)")
            return
        }
        super.record(issue)
    }

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
        // Commit a scene: an edit (Linear Spectrum), then closing Settings commits at once (SCN-002-R3).
        // Settings opens at Storage, so scroll back up to the visual rows.
        openSettings()
        let row = app.buttons["visual.linearSpectrum"]
        // Scroll the list itself, slowly, and stop once the row exists: a swipe at the top of the list pulls the
        // Settings sheet down and dismisses it (seen on D1, 2026-11-15).
        let list = app.collectionViews.firstMatch, nav = app.navigationBars["Settings"]
        // A status-bar tap scrolls the list to its top (Storage is dozens of sections down); swipes are the fallback.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap()
        _ = wait(3) { row.exists }
        for _ in 0..<10 where !row.exists && nav.exists { list.swipeDown(velocity: .slow) }
        for _ in 0..<3 where row.exists && !row.isHittable && nav.exists { list.swipeDown(velocity: .slow) }
        XCTAssertTrue(nav.exists, "Settings is still open")
        XCTAssertTrue(row.isHittable, "the Linear Spectrum row is reachable")
        row.tap()
        closeSettings()
        XCTAssertTrue(wait(10) { self.autosave.contains("pending=0") && !self.autosave.contains("committed=0") },
                      "the scene is committed: \(autosave)")
        openSettings()
        let crash = app.buttons["debugCrashButton"]
        XCTAssertTrue(wait(5) { crash.exists }, "the DEBUG crash button is shown (Settings opens at Storage)")
        crashExpected = true
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

    // MARK: SCN-002-T10 (QA-011 Batch 1)

    private var bars: XCUIElement { app.segmentedControls["barsPicker"] }

    /// Opens Settings and scrolls (slowly, the list itself) to the Bars picker below the visual rows.
    private func openBars() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !(bars.exists && bars.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(bars.isHittable, "the Bars picker")
    }

    private func launchScene(reset: Bool) {
        let values: [String: Any] = ["settings.visual": "circularSpectrum"]
        let json = (try? JSONSerialization.data(withJSONObject: values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        app.launchArguments = (reset ? ["-uitestResetNotice", "-uitestDefaults", json] : [])
            + ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO"]
        app.launch()
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists }, "the source started")
    }

    /// SCN-002-T10: Circular Spectrum, 16 bars, Settings closed (committed); then 32 bars with Settings open and at
    /// once the app switcher and a force quit there (the user's way; the switcher passes through the background, so
    /// 32 is expected). Relaunch: a committed value (32, or 16), never the default 64, and the visual draws.
    func testSCN002ForceQuitFromSwitcher() {
        let task = "SCN-002-T10"
        let system = SystemUI(app: app)
        launchScene(reset: true)
        openBars()
        bars.buttons["16"].tap()
        XCTAssertTrue(bars.buttons["16"].isSelected)
        closeSettings()
        XCTAssertTrue(wait(10) { self.autosave.contains("pending=0") && !self.autosave.contains("committed=0") },
                      "16 bars committed: \(autosave)")

        openBars()
        bars.buttons["32"].tap()
        XCTAssertTrue(bars.buttons["32"].isSelected)
        system.openAppSwitcher()
        let ended = system.forceQuitFromSwitcher()
        report(task, "force quit", ["ended": ended ? 1 : 0])
        XCTAssertTrue(ended, "the app ended from the switcher")

        launchScene(reset: false)
        XCTAssertTrue(wait(10) { self.autosave.hasPrefix("restored=main") }, "restored from the committed scene: \(autosave)")
        XCTAssertTrue(wait(10) { (self.app.staticTexts["visualRunning"].value as? String) == "yes" }, "the visual draws")
        XCTAssertTrue(wait(10) { self.app.descendants(matching: .any)["circularSpectrum"].firstMatch.exists },
                      "the Circular Spectrum is restored")
        openBars()
        let restored = ["16", "32", "64"].first { bars.buttons[$0].isSelected } ?? "none"
        report(task, "relaunch", ["bars": Double(restored) ?? -1])
        print("SCN002 restored bars=\(restored) probe=\(autosave)")
        XCTAssertTrue(restored == "32" || restored == "16", "a committed bar count (32 expected), got \(restored)")
        XCTAssertNotEqual(restored, "64", "never the default")
        closeSettings()
    }
}
