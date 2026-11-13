// NoTelemetryUITests.swift — FILE-012-T07, T08: scripted normal use for the no-telemetry observation
// (FILE-012-R8). These tests only drive the app; the evidence comes from running them under
// `scripts/observe_app_network.py`, which watches the app's sockets and network log events from the
// Mac (`--expect none` for the first four, `--expect osc:47131 --probe` for the OSC test). Run alone,
// they just exercise the flows and pass. The store is stubbed (`-uitestUnlocked NO`); OSC is off unless
// the OSC test turns it on in Settings. Simulator results are never device evidence; the device check
// is {device} FILE-012-T11. Budget: under 30 s each (owner rule 7).
import XCTest

@MainActor
final class NoTelemetryUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    /// The OSC test's port: away from 9000 and the other OSC suites' 47123 and 47124.
    private static let oscPort = "47131"
    private static let oscOff = ["-settings.osc.enabled", "NO", "-settings.osc.port", NoTelemetryUITests.oscPort]

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var controls: XCUIElement { app.otherElements["controls"] }
    private var tapArea: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"]
            + extra + Self.oscOff + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15), "In-App Playback started")
    }

    /// As in CameraUITests: shows the controls freshly (they hide on a timer).
    private func showControls() {
        if controls.exists { tapArea.tap() }
        tapArea.tap()
        if !controls.appears(within: 2) { tapArea.tap() }
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

    /// Picks a visual in Settings (scrolling to its row) and closes Settings.
    private func choose(_ title: String, shows identifier: String) {
        openSettings()
        let row = app.visualRow(title)
        XCTAssertTrue(app.reveal(row), "\(title) row")
        row.tap()
        closeSettings()
        XCTAssertTrue(app.descendants(matching: .any)[identifier].firstMatch.appears(within: 10), "\(title) is shown")
    }

    /// Launch → photosensitivity notice → source chooser → In-App Playback → controls.
    func testNoticeChooserAndInAppPlayback() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics"] + Self.oscOff + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 10), "the notice comes first")
        acknowledge.tap()
        let inApp = app.buttons["In-App Playback"]
        XCTAssertTrue(inApp.appears(within: 10), "the chooser")
        inApp.tap()
        XCTAssertTrue(controls.appears(within: 10), "the visualizer with its controls")
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 10))
        showControls()
        app.buttons["next"].tap()   // a preset switch
    }

    /// Seeded Photo, Video and Text, chosen through Settings.
    func testVisualsWithSeededPhotoVideoAndText() {
        launch(["-uitestSeedPhoto", "solid", "-uitestSeedVideo", "counter", "-uitestSeedText", "FILE-012"])
        choose("Photo", shows: "photoVisual")
        choose("Video", shows: "videoVisual")
        choose("Text", shows: "textVisual")
    }

    /// The two spectra, then back to projectM, chosen through Settings (split from the test above to
    /// stay under 30 s).
    func testSpectraAndProjectM() {
        launch([])
        choose("Circular Spectrum", shows: "circularSpectrum")
        choose("Linear Spectrum", shows: "linearSpectrum")
        choose("projectM", shows: "visualizer")
    }

    /// Save Frame → PNG and a short recording of the seeded Photo visual, written to the DEBUG folders
    /// that replace the system file pickers (as FrameCaptureUITests and VideoRecordingUITests do).
    func testSaveFrameAndShortRecording() {
        launch(["-settings.visual", "photo", "-uitestSeedPhoto", "solid",
                "-uitestCaptureDirectory", "NoTelemetryUITests", "-uitestRecordingDirectory", "NoTelemetryUITests"])
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        let frameProbe = app.staticTexts["frameCaptureProbe"]
        XCTAssertTrue(poll(10) { ((frameProbe.value as? String) ?? "").hasPrefix("png ") }, "a PNG was written")

        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(indicator.appears(within: 5), "recording")
        XCTAssertTrue(poll(10) { indicator.label == "Recording, 0:01" || indicator.label == "Recording, 0:02" }, indicator.label)
        showControls()
        app.buttons["record"].tap()
        let videoProbe = app.staticTexts["videoRecordingProbe"]
        XCTAssertTrue(poll(10) { ((videoProbe.value as? String) ?? "").hasPrefix("video ") }, "a video was written")
    }

    /// The seeded show: step through its cues; then Settings › Storage › Clear Caches.
    func testShowCuesAndStorageCleanup() {
        launch(["-uitestShowSeed"])
        let status = app.staticTexts["showCueStatus"]
        let next = app.buttons["showNextCue"]
        for n in 2...4 {
            if !controls.exists { tapArea.tap() }
            XCTAssertTrue(controls.appears(within: 3))
            next.tap()
            XCTAssertTrue(poll(3) { (status.value as? String)?.hasPrefix("Cue \(n) of 5") == true },
                          "cue \(n): \(String(describing: status.value))")
        }

        openSettings()
        let link = app.buttons["storageLink"]
        XCTAssertTrue(app.reveal(link))
        link.tap()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 5))
        let clear = app.buttons["storageClearCaches"]
        XCTAssertTrue(app.reveal(clear))
        XCTAssertTrue(poll(10) { clear.isEnabled })
        clear.tap()
        // Either the confirmation (Clear) or the nothing-to-clear alert (OK), depending on the caches.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.appears(within: 5), "the cleanup alert")
        let confirm = alert.buttons["Clear"].firstMatch
        (confirm.exists ? confirm : alert.buttons.firstMatch).tap()
        XCTAssertTrue(alert.disappears(within: 5))
    }

    /// FILE-012-T08 (run under `--expect osc:47131 --probe`): the user turns the OSC receiver on, the app
    /// listens on the chosen port while the observer sends its probe, then the user turns it off.
    func testUserEnabledOSCListensOnly() {
        launch([])
        openSettings()
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(app.reveal(toggle), "the OSC section")
        XCTAssertEqual(toggle.value as? String, "0", "off at start")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let status = app.staticTexts["oscStatus"]
        func text() -> String { (status.value as? String) ?? status.label }
        XCTAssertTrue(poll(10) { text() == "Listening on port \(Self.oscPort)" }, "status: \(text())")
        // Hold the listener open long enough for the observer's 0.2 s sampler to see it and probe it.
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(poll(10) { text() == "Off" }, "status: \(text())")
    }
}
