// SessionRecoveryUITests.swift — PERF-010-T08 to T10 on the iOS Simulator: the roadmap acceptance
// "Simulated crash never reopens camera or network listener without consent" (PERF-010-S1 to S5).
// A simulated crash is `terminate()` while the app is in the foreground (no background transition, so
// the session marker stays open); a clean exit is Home, then terminate. `-uitestSessionRecovery` turns
// recovery on in these harness launches (research PERF-010-D5); every other suite runs without it. The
// stand-in camera (`-uitestCamera granted`) would report frames if it were started. The DEBUG probe
// `sessionRecovery` reports the decision, the offer and whether the OSC transport listens. Simulator
// results are never device evidence; the real crash on D1 is PERF-010-T15. Budget: under 30 s per test.
import XCTest

@MainActor
final class SessionRecoveryUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private static let port = "47125"

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = (reset ? ["-uitestResetNotice"] : [])
            + ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestCamera", "granted",
               "-uitestSessionRecovery", "-settings.osc.port", Self.port] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var probe: String { app.staticTexts["sessionRecovery"].value as? String ?? "" }
    private var autosave: String { app.staticTexts["sceneAutosave"].value as? String ?? "" }
    private var offer: XCUIElement { app.descendants(matching: .any)["sessionRecoveryOffer"].firstMatch }
    private var oscBadge: XCUIElement { app.descendants(matching: .any)["oscListenerBadge"].firstMatch }
    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var cameraBadge: XCUIElement { app.descendants(matching: .any)["cameraIndicator"].firstMatch }
    private var circularSpectrum: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var bars: XCUIElement { app.segmentedControls["barsPicker"] }
    private var oscToggle: XCUIElement { app.switches["oscReceiverToggle"] }

    /// See NativeVisualUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func openSettings() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func oscStatus() -> String {
        let element = app.staticTexts["oscStatus"]
        app.reveal(element)
        return (element.value as? String) ?? element.label
    }

    private func toggleOSC() {
        XCTAssertTrue(app.reveal(oscToggle), "the OSC section is in Settings")
        oscToggle.switches.firstMatch.exists ? oscToggle.switches.firstMatch.tap() : oscToggle.tap()
    }

    /// Circular Spectrum with 16 bars, committed (closing Settings commits at once, SCN-002-R3).
    private func commitCircularSpectrum16() {
        openSettings()
        app.visualRow("Circular Spectrum").tap()
        XCTAssertTrue(bars.appears(within: 5))
        bars.buttons["16"].tap()
        closeSettings()
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        XCTAssertTrue(poll(10) { self.autosave.contains("pending=0") && !self.autosave.contains("committed=0") },
                      "the scene is committed: \(autosave)")
    }

    /// T08: OSC listening and the Camera visual live, then a simulated crash; the relaunch opens
    /// neither, offers the scene, and Reopen brings back the committed non-sensor scene only.
    func testSimulatedCrashReopensNoListenerOrCameraAndOffersTheScene() {
        launch(reset: true)
        XCTAssertTrue(probe.hasPrefix("decision=clean offer=none"), "fresh start: \(probe)")
        // One Settings visit: Circular Spectrum, 16 bars, OSC on, then Camera (session only, so the
        // committed scene records Circular Spectrum); closing Settings commits (SCN-002-R3).
        openSettings()
        app.visualRow("Circular Spectrum").tap()
        XCTAssertTrue(bars.appears(within: 5))
        bars.buttons["16"].tap()
        toggleOSC()
        app.reveal(app.visualRow("Camera"), down: true)
        app.visualRow("Camera").tap()
        closeSettings()
        XCTAssertTrue(poll(10) { self.autosave.contains("pending=0") && !self.autosave.contains("committed=0") },
                      "the scene is committed: \(autosave)")
        XCTAssertTrue(cameraVisual.appears(within: 10), "the Camera visual is shown")
        XCTAssertTrue(cameraBadge.appears(within: 10), "the camera badge is shown")
        XCTAssertTrue(oscBadge.appears(within: 5), "the OSC badge is shown")
        XCTAssertTrue(probe.hasSuffix("osc=listening"), probe)

        app.terminate()   // a crash: no background transition
        launch(reset: false)

        XCTAssertTrue(offer.appears(within: 10), "the recovery offer is shown")
        XCTAssertTrue(poll(5) { self.probe == "decision=abnormal offer=pending reopen=1 osc=off" }, probe)
        XCTAssertTrue(app.staticTexts["sessionRecoveryOSC"].exists, "the card says OSC was turned off")
        XCTAssertFalse(oscBadge.exists, "no OSC listener after the crash")
        XCTAssertFalse(cameraVisual.exists, "the camera visual is not shown")
        XCTAssertFalse(cameraBadge.exists, "no camera badge")
        XCTAssertFalse(app.staticTexts["cameraFramesShown"].exists, "the stand-in camera never started")
        XCTAssertFalse(circularSpectrum.exists, "the fresh scene (projectM) is shown until the user answers")

        // S5: the app stays usable with the offer shown (the controls open; the source kept running).
        showControls()
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1")

        app.buttons["sessionRecoveryReopen"].tap()
        XCTAssertTrue(offer.disappears(within: 5), "the offer goes away")
        XCTAssertTrue(circularSpectrum.appears(within: 10), "the committed visual returns (not Camera)")
        openSettings()
        XCTAssertTrue(bars.appears(within: 5))
        XCTAssertTrue(bars.buttons["16"].isSelected, "the committed bar count returns")
        XCTAssertTrue(app.reveal(oscToggle))
        XCTAssertEqual(oscToggle.value as? String, "0", "the stored OSC toggle is off; Reopen does not turn it on")
        closeSettings()
        XCTAssertFalse(oscBadge.exists)
        XCTAssertFalse(cameraVisual.exists)
        XCTAssertFalse(cameraBadge.exists)
        XCTAssertTrue(probe.hasPrefix("decision=abnormal offer=reopened") && probe.hasSuffix("osc=off"), probe)
    }

    /// T09: a clean exit (Home, then terminate) offers nothing and OSC listens again as stored.
    func testCleanExitShowsNoOffer() {
        launch(reset: true)
        openSettings()
        toggleOSC()
        closeSettings()
        XCTAssertTrue(poll(10) { self.probe.hasSuffix("osc=listening") }, probe)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(poll(10) { self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended },
                      "the app is in the background")
        app.terminate()
        launch(reset: false)

        XCTAssertTrue(poll(5) { self.probe.hasPrefix("decision=clean offer=none") }, probe)
        XCTAssertFalse(offer.exists, "no offer after a clean exit")
        XCTAssertTrue(oscBadge.appears(within: 10), "OSC-001-R15: the stored toggle reopens the listener after a clean exit")
        app.buttons["oscStopButton"].tap()   // leave no listener for the next suite
        XCTAssertTrue(oscBadge.disappears(within: 5))
    }

    /// T10: a crash right after Reopen offers Start fresh only.
    func testCrashAfterReopenOffersStartFreshOnly() {
        launch(reset: true)
        commitCircularSpectrum16()
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(offer.appears(within: 10))
        app.buttons["sessionRecoveryReopen"].tap()
        XCTAssertTrue(circularSpectrum.appears(within: 10))
        app.terminate()   // crashes again in the reopened session
        launch(reset: false)

        XCTAssertTrue(offer.appears(within: 10))
        XCTAssertTrue(poll(5) { self.probe.hasPrefix("decision=crashLoop offer=pending reopen=0") }, probe)
        XCTAssertFalse(app.buttons["sessionRecoveryReopen"].exists, "no Reopen in a crash loop")
        XCTAssertEqual(app.staticTexts["sessionRecoveryTitle"].label, "projectM closed unexpectedly again.")
        XCTAssertFalse(circularSpectrum.exists, "the fresh scene is shown")
        app.buttons["sessionRecoveryStartFresh"].tap()
        XCTAssertTrue(offer.disappears(within: 5))
    }
}
