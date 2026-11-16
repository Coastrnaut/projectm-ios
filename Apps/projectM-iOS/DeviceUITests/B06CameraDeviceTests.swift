// B06CameraDeviceTests.swift — QA-011 owner session B06 ("Camera and motion sensors"), automated on the device with
// the real cameras (camera access was granted once per device, PermissionPrimerDeviceTests). The camera is live
// when the Camera visual's VoiceOver value is "Live" and the DEBUG `cameraFramesShown` count grows; the iOS
// camera indicator (green dot) is the system's own and is not readable by a test.
// CAM-001-T24: the back camera live under the spectrum, with the indicator badge, through rotation.
// CAM-002-T21: the front camera the same way. CAM-002-T23: Back ↔ Front within 2 s with audio uninterrupted.
// CAM-003-T11: the lens row on D1 (Wide ↔ Ultra Wide ten times while running) and no lens row on the iPads.
import UIKit
import XCTest

@MainActor
final class B06CameraDeviceTests: DeviceAcceptanceCase {
    private var camera: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var frames: Int { Int((app.staticTexts["cameraFramesShown"].value as? String) ?? "") ?? -1 }
    private var starts: String { (app.staticTexts["sourceStarts"].value as? String) ?? "" }

    private func launchCamera(_ position: String, extra: [String] = []) {
        launch(visual: "camera", settings: ["settings.camera.position": position], extra: extra)
        if app.otherElements["cameraNotice"].exists {
            XCTFail("camera notice instead of a picture: \(app.staticTexts["cameraNoticeText"].label) "
                    + "(camera access on this device: Settings › projectM-iOS › Camera)")
        }
    }

    /// The camera is live: VoiceOver value "Live" and frames keep arriving (over 1 s).
    @discardableResult
    private func assertLive(_ task: String, _ step: String) -> Int {
        XCTAssertTrue(wait(10) { (self.camera.value as? String) == "Live" }, "\(step): Live (\(String(describing: camera.value)))")
        let before = frames
        pause(1)
        let delta = frames - before
        report(task, step, ["framesPerSecond": Double(delta)])
        XCTAssertGreaterThan(delta, 10, "\(step): camera pictures keep arriving (\(delta) in 1 s)")
        XCTAssertTrue(app.descendants(matching: .any)["cameraIndicatorStatus"].firstMatch.exists, "\(step): the camera badge")
        return delta
    }

    private func liveThroughRotation(_ task: String, _ position: String) {
        launchCamera(position)
        assertLive(task, "\(position) portrait")
        assertFrameRate(task, "\(position) portrait")
        _ = screen(task, "\(position) portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertLive(task, "\(position) landscape")
        assertFrameRate(task, "\(position) landscape")
        _ = screen(task, "\(position) landscape")
    }

    /// CAM-001-T24: the back camera live under the spectrum, badge shown, through rotation.
    func testCAM001BackCameraLiveThroughRotation() { liveThroughRotation("CAM-001-T24", "back") }

    /// CAM-002-T21: the front camera the same way (mirrored by default).
    func testCAM002FrontCameraLiveThroughRotation() { liveThroughRotation("CAM-002-T21", "front") }

    private func openCameraSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
    }

    /// CAM-002-T23: Back → Front and back within 2 s each, no audio restart.
    func testCAM002SwitchingWithinTwoSecondsAudioUninterrupted() {
        let task = "CAM-002-T23"
        launchCamera("back", extra: ["-uitestSettingsSection", "camera"])
        assertLive(task, "back")
        let audioStarts = starts
        openCameraSettings()
        let picker = app.segmentedControls["cameraPositionPicker"]
        XCTAssertTrue(wait(5) { picker.exists }, "the Camera picker")
        for target in ["Front", "Back"] {
            let before = frames
            let t0 = Date()
            picker.buttons[target].tap()
            // The new camera's first picture: the count resumes growing (pictures of the old camera are not counted
            // as the new one's; the badge and value stay on Live).
            let resumed = wait(5) { self.frames > before + 5 }
            let seconds = Date().timeIntervalSince(t0)
            report(task, "to \(target)", ["seconds": seconds])
            XCTAssertTrue(resumed, "to \(target): pictures resume")
            XCTAssertLessThan(seconds, 2.5, "to \(target): within 2 s (plus the poll)")
        }
        XCTAssertEqual(starts, audioStarts, "the audio source was never restarted")
    }

    /// CAM-003-T11: D1 switches Wide ↔ Ultra Wide ten times while running; the iPads offer no Lens row.
    func testCAM003LensRow() {
        let task = "CAM-003-T11"
        launchCamera("back", extra: ["-uitestSettingsSection", "camera"])
        assertLive(task, "back")
        openCameraSettings()
        let lens = app.segmentedControls["cameraLensPicker"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertFalse(wait(3) { lens.exists }, "no Lens row on this iPad")
            report(task, "no lens row", ["lensRow": lens.exists ? 1 : 0])
            return
        }
        XCTAssertTrue(wait(5) { lens.exists }, "the Lens row on D1")
        for i in 0..<10 {
            let target = i % 2 == 0 ? lens.buttons.element(boundBy: 0) : lens.buttons.element(boundBy: 1)
            target.tap()
            pause(1)
            XCTAssertEqual(app.state, .runningForeground, "switch \(i + 1): no crash")
        }
        app.navigationBars["Settings"].buttons["Done"].tap()
        assertLive(task, "after ten lens switches")
    }
}
