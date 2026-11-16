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
    /// Camera pictures shown, from the capture probe's `shown=` (the `cameraFramesShown` text went stale after Settings
    /// opened on the iPads, while this probe beside it kept counting: D2, 2026-11-16).
    private var frames: Int {
        let text = (app.staticTexts["cameraCaptureProbe"].value as? String) ?? ""
        guard let range = text.range(of: #"shown=(\d+)"#, options: .regularExpression) else { return -1 }
        return Int(text[range].dropFirst("shown=".count)) ?? -1
    }
    private var starts: String { (app.staticTexts["sourceStarts"].value as? String) ?? "" }

    /// Launches on the spectrum and chooses Camera in Settings: the camera never starts by itself at launch, only
    /// when Camera is chosen (CAM-001-R11), so a typed visual is not enough.
    private func launchCamera(_ position: String, extra: [String] = []) {
        launch(visual: "circularSpectrum", settings: ["settings.camera.position": position], extra: extra)
        openSettings()
        let row = app.buttons["visual.camera"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where !(row.exists && row.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable, "the Camera row")
        row.tap()
        closeSettings()
        XCTAssertTrue(wait(10) { self.camera.exists }, "the Camera visual is shown")
        if app.otherElements["cameraNotice"].exists {
            XCTFail("camera notice instead of a picture: \(app.staticTexts["cameraNoticeText"].label) "
                    + "(camera access on this device: Settings › projectM-iOS › Camera)")
        }
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
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

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
    }

    /// Settings scrolled to the camera rows (below the visual rows).
    private func openCameraSettings(_ element: XCUIElement) {
        openSettings()
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) { list.swipeUp(velocity: .slow) }
    }

    /// CAM-002-T23: Back → Front and back within 2 s each, no audio restart.
    func testCAM002SwitchingWithinTwoSecondsAudioUninterrupted() {
        let task = "CAM-002-T23"
        launchCamera("back")
        assertLive(task, "back")
        let audioStarts = starts
        let picker = app.segmentedControls["cameraPositionPicker"]
        openCameraSettings(picker)
        XCTAssertTrue(wait(5) { picker.exists }, "the Camera picker")
        for target in ["Front", "Back"] {
            if !picker.exists { openCameraSettings(picker) }
            let before = frames
            let t0 = Date()
            picker.buttons[target].tap()
            // Close Settings at once: the camera count only grows with drawn frames, and it stood still while Settings
            // was open (D2, 2026-11-16). The time includes the close.
            closeSettings()
            // The count may restart for the new camera, so "resumed" is: it moved off its value at the tap and then
            // rose again between two reads.
            var last = before, rises = 0
            let resumed = wait(5) {
                let now = self.frames
                if now != last { if now > last && last != before { rises += 1 }; last = now }
                return rises >= 1
            }
            let seconds = Date().timeIntervalSince(t0)
            report(task, "to \(target)", ["seconds": seconds])
            print("B06-CAPTURE to \(target): \((app.staticTexts["cameraCaptureProbe"].value as? String) ?? "none")")
            pause(2)
            print("B06-CAPTURE to \(target) +2 s: \((app.staticTexts["cameraCaptureProbe"].value as? String) ?? "none")")
            XCTAssertTrue(resumed, "to \(target): pictures resume")
            // The switch itself, timed in the app from select() to the new camera's first stored picture; the UI time
            // above adds closing Settings and the accessibility polls.
            let probe = (app.staticTexts["cameraCaptureProbe"].value as? String) ?? ""
            let ms = probe.range(of: #"switchMs=(-?\d+)"#, options: .regularExpression)
                .flatMap { Int(probe[$0].dropFirst("switchMs=".count)) } ?? -1
            report(task, "to \(target) in app", ["switchMs": Double(ms)])
            XCTAssertGreaterThanOrEqual(ms, 0, "to \(target): the new camera's first picture was timed (\(probe))")
            XCTAssertLessThan(ms, 2000, "to \(target): the new camera's first picture within 2 s (CAM-002-S7)")
            assertLive(task, "after the switch to \(target)")
        }
        XCTAssertEqual(starts, audioStarts, "the audio source was never restarted")
    }

    /// CAM-003-T11: D1 switches Wide ↔ Ultra Wide ten times while running; the iPads offer no Lens row.
    func testCAM003LensRow() {
        let task = "CAM-003-T11"
        launchCamera("back")
        assertLive(task, "back")
        let lens = app.segmentedControls["cameraLensPicker"]
        openCameraSettings(app.segmentedControls["cameraPositionPicker"])
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
