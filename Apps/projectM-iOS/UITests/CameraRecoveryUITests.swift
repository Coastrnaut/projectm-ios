// CameraRecoveryUITests.swift — CAM-013-T12 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted -uitestCameraEvents`, DEBUG only): the roadmap acceptance "Injected
// interruption clears last frame and offers retry" (CAM-013-S6). The interruption is injected with
// the DEBUG panel; the app's handling is real. Simulator results are never device evidence
// (Constitution X); real interruptions are CAM-013-T17 and T18. Waits are ceilings, never budgets.
import XCTest

@MainActor
final class CameraRecoveryUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var indicator: XCUIElement { app.otherElements["cameraIndicator"] }
    private var framesShown: Int { Int(app.staticTexts["cameraFramesShown"].value as? String ?? "") ?? -1 }
    private var noticeText: XCUIElement { app.staticTexts["cameraNoticeText"] }
    private var retry: XCUIElement { app.buttons["cameraRetry"] }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func chooseCamera() {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func assertFramesAdvance(_ message: String) {
        let first: Int = framesShown
        XCTAssertTrue(poll(5) { self.framesShown > first }, "\(message): camera frames are shown (\(first) → \(framesShown))")
    }

    /// S6: an injected interruption stops camera frames, names the reason and offers Retry, hides the
    /// badge and is announced; Retry brings the frames, the badge and no notice back.
    func testInjectedInterruptionClearsTheCameraAndRetryBringsItBack() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted", "-uitestCameraEvents"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        chooseCamera()
        XCTAssertTrue(cameraVisual.appears(within: 10))
        XCTAssertTrue(indicator.appears(within: 5), "the badge shows while the camera runs")
        assertFramesAdvance("before")

        app.buttons["camera:interrupt:anotherApp"].tap()
        XCTAssertTrue(noticeText.appears(within: 5), "the notice appears")
        XCTAssertEqual(noticeText.label, "Another app is using the camera. It comes back when the camera is free, or tap Retry.")
        XCTAssertTrue(retry.exists, "it offers Retry")
        XCTAssertEqual(retry.label, "Retry camera")
        XCTAssertTrue(indicator.disappears(within: 5), "the badge never says Camera on while interrupted")
        let probe = app.staticTexts["announcementProbe"]
        XCTAssertTrue(poll(5) { (probe.value as? String)?.hasPrefix("camera|Another app") == true },
                      "announced: \(String(describing: probe.value))")
        let stopped: Int = framesShown
        RunLoop.current.run(until: Date().addingTimeInterval(1))   // the readout refreshes every 0.5 s
        XCTAssertEqual(framesShown, stopped, "no camera frame is drawn while interrupted")

        retry.tap()
        XCTAssertTrue(noticeText.disappears(within: 5), "the notice goes")
        XCTAssertTrue(indicator.appears(within: 5), "the badge returns")
        assertFramesAdvance("after Retry")
        let recovery = app.staticTexts["cameraRecovery"]
        XCTAssertTrue(poll(3) { (recovery.value as? String)?.hasPrefix("running|none|1|no|anotherApp:1,retries:1") == true },
                      "probe: \(String(describing: recovery.value))")
    }
}
