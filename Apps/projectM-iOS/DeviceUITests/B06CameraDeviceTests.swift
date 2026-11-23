// B06CameraDeviceTests.swift — QA-011 owner session B06 ("Camera and motion sensors"), automated on the device with
// the real cameras (camera access was granted once per device, PermissionPrimerDeviceTests). The camera is live
// when the Camera visual's VoiceOver value is "Live" and the DEBUG `cameraFramesShown` count grows; the iOS
// camera indicator (green dot) is the system's own and is not readable by a test.
// CAM-001-T24: the back camera live under the spectrum, with the indicator badge, through rotation.
// CAM-002-T21: the front camera the same way. CAM-002-T23: Back ↔ Front within 2 s with audio uninterrupted.
// CAM-003-T11: the lens row on D1 (Wide ↔ Ultra Wide ten times while running) and no lens row on the iPads.
// QA-011 Batch 4 (the extension at the end of this file; the system-UI camera tests are B06CameraSystemDeviceTests):
// CAM-002-T21/T22 mirror and saved-picture orientation, CAM-004-T08, CAM-005-T14, FX-009-T18, REC-003-T23 (Camera),
// and CAM-007-T15's Fit bars on the iPhone.
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
    private func launchCamera(_ position: String, extra: [String] = [], settings: [String: Any] = [:]) {
        launch(visual: "circularSpectrum", settings: settings.merging(["settings.camera.position": position]) { a, _ in a },
               extra: extra)
        openSettings()
        let row = app.buttons["visual.camera"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where !(row.exists && row.isHittable) { list.scrollStep(up: true) }
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
        for _ in 0..<8 where !(element.exists && element.isHittable) { list.scrollStep(up: true) }
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

    // MARK: Camera effects and Stop camera (D1 tasks)

    /// Frame rate and picture with an effect off and on over the live back camera; the on/off pictures must differ in
    /// the middle of the screen (the effect applied). Moving a hand in front of the camera stays a person's look.
    private func effectOverCamera(_ task: String, _ label: String, on settings: [String: Any], minimumChange: Double = 0.003) {
        launchCamera("back")
        assertLive(task, "\(label) off")
        let off = assertFrameRate(task, "\(label) off")
        let (_, a) = screen(task, "\(label) off")
        app.terminate()
        launchCamera("back", settings: settings)
        assertLive(task, "\(label) on")
        let on = assertFrameRate(task, "\(label) on")
        let (_, b) = screen(task, "\(label) on")
        let change = Self.change(a, b)
        report(task, label, ["offMinusOn": off - on, "changeFromOff": change])
        XCTAssertLessThanOrEqual(off - on, Self.effectToleranceFPS, "\(label): the frame rate stays at the visual's normal rate")
        XCTAssertGreaterThan(change, minimumChange, "\(label): the effect changes the camera picture")
        app.terminate()
    }

    /// FX-010-T17: Echo with 4 echoes at 200 ms over the camera (the trailing copies of a moving hand are by eye).
    func testFX010EchoOverCamera() {
        effectOverCamera("FX-010-T17", "echo 4 x 200 ms", on: ["settings.echo.enabled": true, "settings.echo.count": 4,
                                                               "settings.echo.delay": 0.2], minimumChange: 0)
    }

    /// FX-014-T18: Edge outline at threshold 0.2, widths 1 and 3.
    func testFX014EdgeOutlineOverCamera() {
        for width in [1, 3] {
            effectOverCamera("FX-014-T18", "edge outline width \(width)",
                             on: ["settings.edgeOutline.enabled": true, "settings.edgeOutline.threshold": 0.2,
                                  "settings.edgeOutline.width": width])
        }
    }

    /// FX-016-T17: Lens distortion at +100 % and -100 %, zoom on and off.
    func testFX016LensDistortionOverCamera() {
        for (strength, zoom) in [(1.0, true), (-1.0, true), (1.0, false)] {
            effectOverCamera("FX-016-T17", "lens distortion \(Int(strength * 100)) % zoom \(zoom ? "on" : "off")",
                             on: ["settings.lensDistortion.enabled": true, "settings.lensDistortion.strength": strength,
                                  "settings.lensDistortion.zoomToFill": zoom])
        }
    }

    /// CAM-012-T13: Stop camera ends the camera within a second, the previous visual keeps animating, music continues,
    /// and a trip to the background does not restart it.
    func testCAM012StopCameraReleasesIt() {
        let task = "CAM-012-T13"
        launchCamera("back")
        assertLive(task, "before stop")
        let stop = app.buttons["Stop camera"].firstMatch
        XCTAssertTrue(wait(5) { stop.exists }, "the Stop camera button")
        let t0 = Date()
        stop.tap()
        let gone = wait(5) { !self.camera.exists && !self.app.descendants(matching: .any)["cameraIndicatorStatus"].firstMatch.exists }
        report(task, "stop", ["seconds": Date().timeIntervalSince(t0)])
        XCTAssertTrue(gone, "the camera and its badge are gone")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2, "within about a second (plus the poll)")
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.label.contains("Active audio"), "music continues: \(overlay.label.prefix(120))")
        assertDrawingAndMoving(task, "previous visual")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        pause(2)
        XCTAssertFalse(camera.exists, "the camera does not restart after background and return")
    }

    /// CAM-007-T15 (D1) / T16 (D2, D3): back and front, Fill Center 1x, Fill Top 2x and Fit, portrait and landscape:
    /// live, and Save Frame writes a frame of the screen's size in each mode (DEBUG `-uitestCaptureDirectory`). The mode
    /// is checked from the drawn rectangle (`assertPictureRect`, DEBUG `cameraPictureRect`; spec 098 Clarifications
    /// 2026-11-23), independent of the light: Fit leaves bars, Fill covers the window, Top starts at its top. Upright,
    /// undistorted and the anchor are also judged by eye from the attached screenshots.
    func testCAM007CropModesBothCamerasAndSaveFrame() {
        let task = UIDevice.current.userInterfaceIdiom == .pad ? "CAM-007-T16" : "CAM-007-T15"
        let modes: [(String, [String: Any])] = [
            ("fill center 1x", ["settings.camera.cropMode": "fill", "settings.camera.cropAnchor": "center", "settings.camera.zoom": 1.0]),
            ("fill top 2x", ["settings.camera.cropMode": "fill", "settings.camera.cropAnchor": "top", "settings.camera.zoom": 2.0]),
            ("fit", ["settings.camera.cropMode": "fit", "settings.camera.cropAnchor": "center", "settings.camera.zoom": 1.0]),
        ]
        let probe = app.staticTexts["frameCaptureProbe"]
        for position in ["back", "front"] {
            for (label, settings) in modes {
                XCUIDevice.shared.orientation = .portrait
                launchCamera(position, extra: ["-uitestCaptureDirectory", "B06CropDeviceTests"], settings: settings)
                for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                    XCUIDevice.shared.orientation = orientation
                    pause(2)
                    let step = "\(position) \(label) \(orientation == .portrait ? "portrait" : "landscape")"
                    assertLive(task, step)
                    // QA-011 Batch 4: on an iPhone the camera's 4:3 picture leaves Fit's bars below it (portrait) or
                    // beside it (landscape); Fill covers them.
                    // D1 rerun 2026-11-23: the landscape band read 0.324 (back) and 0.802 (front), identical to three
                    // places for Fill center, Fill top 2x and Fit, so it measured no picture at all: the controls card
                    // (shown until 5 s after Settings closed, and filling most of the 393 pt landscape window) lay
                    // over it. The bands are now read with the controls hidden, clear of what stays on screen then (the
                    // status pill at the bottom centre, Emergency blackout above it at the trailing side, the overlay
                    // at the top trailing corner): portrait just under the picture's bottom edge (81 %), landscape in
                    // the leading bar. They are read from the upright screenshot (`uprightPixels`), so the fractions
                    // mean the screen as shown whatever rows the screenshot's `cgImage` keeps.
                    waitControlsHidden()
                    screen(task, step)
                    // D1 run 6 (2026-11-23): the portrait band read nonBlack 0.232 in all three modes with a mean luma
                    // of about 0.07 (the camera faced a dark room), so a dark picture and a black bar looked the same
                    // and something constant lay in the band. The band is now only reported; the mode is checked
                    // from the drawn rectangle (`cameraPictureRect`, DEBUG), read from the geometry the camera layer
                    // drew with, which does not depend on the light (spec 098 Clarifications 2026-11-23).
                    if UIDevice.current.userInterfaceIdiom == .phone, let image = lastShot?.image {
                        let (upright, size) = Self.uprightPixels(image, step: sampleStep)
                        let band: (Double, Double, Double, Double) = orientation == .portrait ? (0.1, 0.825, 0.65, 0.04)
                            : (0.03, 0.35, 0.12, 0.3)
                        let lit = Self.region(upright, width: size.0, height: size.1, band).nonBlack
                        report(task, "\(step) bar band (report only)",
                               ["nonBlack": lit, "width": Double(size.0), "height": Double(size.1),
                                "rawWidth": Double(lastSize.0), "rawHeight": Double(lastSize.1)])
                    }
                    assertPictureRect(task, step, settings: settings)
                }
                // Save Frame from the controls; the saved file is read back into the probe ("png WxH opaque").
                // D1 2026-11-18: the controls still existed (fading out, 8 s after Settings closed) when checked, so
                // nothing tapped them, and Save Frame was gone a moment later. Wait for them to hide, then show them
                // fresh (as `saveFramePNG`, which the mirror tests use).
                // D1 full run 1 (2026-11-22): in iPhone landscape (393 pt tall) the controls card holds the transport,
                // the status, route and name rows and both button rows; Save Frame is taken in portrait there, where
                // the compact card fits (the crop mode is the same; the frame has the portrait screen's size). The
                // iPads keep saving in landscape. `saveFramePNG` waits for the button itself (`tapCameraControl`).
                if UIDevice.current.userInterfaceIdiom == .phone {
                    XCUIDevice.shared.orientation = .portrait
                    pause(2)
                }
                saveFramePNG("\(position) \(label)")
                let text = probe.value as? String ?? ""
                print("CAM-007 \(position) \(label): \(text)")
                report(task, "\(position) \(label) save frame", ["saved": text.contains("x") ? 1 : 0])
                app.terminate()
            }
        }
    }

    /// CAM-007-T15/T16 (spec 098 Clarifications 2026-11-23): the crop mode from the drawn rectangle, independent of
    /// the light. `cameraPictureRect` (DEBUG, under `-uitestDiagnostics`) reports the whole upright picture's
    /// rectangle in window fractions from the geometry the camera layer drew with last frame, plus the crop and the
    /// source's upright aspect. Fit: the source's aspect, inside the window and short of it on one axis (bars).
    /// Fill: covers the window. Top: the rectangle's top edge at the window's top.
    private func assertPictureRect(_ task: String, _ step: String, settings: [String: Any]) {
        let probe = app.staticTexts["cameraPictureRect"]
        let mode = settings["settings.camera.cropMode"] as? String ?? "fill"
        let anchor = settings["settings.camera.cropAnchor"] as? String ?? "center"
        let portrait = XCUIDevice.shared.orientation.isPortrait
        var fields: [String: String] = [:]
        // Wait for a reading of this crop in this orientation (the probe refreshes every 0.5 s).
        let ready = wait(10) {
            fields = Self.probeFields((probe.value as? String) ?? "")
            guard fields["mode"] == mode, fields["anchor"] == anchor, let window = fields["window"] else { return false }
            let size = window.split(separator: "x").compactMap { Double($0) }
            return size.count == 2 && (size[1] > size[0]) == portrait
        }
        let text = (probe.value as? String) ?? ""
        XCTAssertTrue(ready, "\(step): cameraPictureRect reports \(mode)/\(anchor) in this orientation (\(text))")
        guard ready, let rectText = fields["rect"], let windowText = fields["window"],
              let sourceAspect = fields["sourceAspect"].flatMap(Double.init) else { return }
        let r = rectText.split(separator: ",").compactMap { Double($0) }
        let window = windowText.split(separator: "x").compactMap { Double($0) }
        guard r.count == 4, window.count == 2, r[2] > 0, r[3] > 0 else {
            XCTFail("\(step): unreadable cameraPictureRect (\(text))")
            return
        }
        let (x, y, w, h) = (r[0], r[1], r[2], r[3])
        let drawnAspect = (w * window[0]) / (h * window[1])
        let e = 0.005
        report(task, "\(step) picture rect", ["x": x, "y": y, "width": w, "height": h, "drawnAspect": drawnAspect,
                                              "sourceAspect": sourceAspect, "windowWidth": window[0], "windowHeight": window[1]])
        print("CAM-007 \(step) rect: \(text)")
        XCTAssertEqual(drawnAspect, sourceAspect, accuracy: sourceAspect * 0.02, "\(step): the picture keeps the source's aspect (\(text))")
        if mode == "fit" {
            XCTAssertTrue(x >= -e && y >= -e && x + w <= 1 + e && y + h <= 1 + e, "\(step): Fit lies inside the window (\(text))")
            XCTAssertLessThan(min(w, h), 0.98, "\(step): Fit is short of the window on one axis, leaving bars (\(text))")
        } else {
            XCTAssertTrue(x <= e && y <= e && x + w >= 1 - e && y + h >= 1 - e, "\(step): Fill covers the window (\(text))")
        }
        if anchor == "top" {
            XCTAssertEqual(y, 0, accuracy: e, "\(step): Top anchors the picture at the window's top (\(text))")
            if h > 1 + e { XCTAssertGreaterThan(y + h, 1 + e, "\(step): the overflow is below (\(text))") }
        } else if anchor == "center" {
            XCTAssertEqual(y + h / 2, 0.5, accuracy: e, "\(step): Center keeps the picture centred vertically (\(text))")
        }
    }

    /// "key=value key=value" → [key: value].
    private static func probeFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in text.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
        }
        return fields
    }
}

// MARK: QA-011 Batch 4: mirror and orientation, exposure, focus, trails, the camera recording
// (shared helpers: B06CameraSystemDeviceTests.swift; probes: `-uitestCameraDeviceProbes`, Debug/UITestCameraDeviceProbes)
// CAM-002-T21 (D1-D3): mirror on and off are each other's mirror image. CAM-002-T22 (D1): the flip is complete in the
// first screenshot after Settings closes; Save Frame and a 3 s recording show the screen's way round, mirror on and
// off. CAM-004-T08 (D1): the lock reads back locked; a lens change and a visual change release it. CAM-005-T14 (D1):
// the focus point follows a double-tap; the front camera's mirror maps a tap to the mirrored point; Fit's bar does
// nothing; the "Focus at centre" action focuses at the centre and is announced. FX-009-T18 (D1, D2): Trails' frame-rate
// cost on Photo and Camera, and no ghost after a cue step. REC-003-T23 (D1, D3): 60 s of the Camera at Max.
// The mirror tests need a left-right asymmetric scene in front of the camera; with a symmetric one they skip, saying so.
extension B06CameraDeviceTests {
    private var mirrorToggle: XCUIElement { app.switches["cameraMirrorToggle"] }
    private static var noOverlay: [String: Any] { ["settings.performanceOverlay": false] }

    /// Flips Mirror in Settings and closes Settings.
    private func flipMirror() {
        openSettingsForCamera()
        XCTAssertTrue(revealCameraSetting(mirrorToggle), "the Mirror switch")
        flipCameraSettingSwitch(mirrorToggle)
        closeSettingsForCamera()
    }

    /// The mirror tests compare the camera's picture with its mirror image, so the screenshot must be mostly camera.
    /// D1 full run 1 (2026-11-22): both cameras saw a dark scene (CAM-002-T21 front portrait: mean luma 0.075, 12 %
    /// non-black; CAM-007 back: 0.064, 11 %). The grid's contrast then came from what does not mirror (the DEBUG probe
    /// buttons, captions), the "asymmetry" read 0.80 and the tests ran: mirror on and off then matched directly (0.97)
    /// and neither saved picture matched the screen either way round (0.13 vs 0.15), so the camera was not in the
    /// comparison. A scene must now be lit (at least half the compared cells above 5 % luma, the `nonBlack` level of
    /// `screen()`) as well as asymmetric, or the test skips saying which. D2's passing run (pass 4) was 99 % non-black.
    private func skipUnlessMirrorScene(_ task: String, _ grid: [Double], _ mask: [Bool]) throws {
        let asymmetry = CameraGrid.asymmetry(grid, mask), lit = CameraGrid.litShare(grid, mask)
        report(task, "scene", ["asymmetry": asymmetry, "litShare": lit])
        try XCTSkipIf(lit < 0.5, "the front camera sees a dark scene (\(Int(lit * 100)) % of the compared cells lit); "
                      + "light the scene in front of the device")
        try XCTSkipIf(asymmetry < 0.15, "the front camera sees a left-right symmetric scene (asymmetry \(asymmetry)); "
                      + "place the device facing something asymmetric")
    }

    /// Taps the control `id` once it exists, is hittable and satisfies `ready`, showing the controls as needed; the tap
    /// lands at the button's place read just before it. Returns whether it tapped.
    /// D1 full run 1 (2026-11-22, CAM-007-T15 in landscape): `controls` still existed 16 s after Settings closed, so
    /// `showCameraControls()` tapped nothing and no "saveFrame" button was in the tree ("No matches found"). The
    /// container says nothing about the button, so this waits for the button itself: a tap on the visualization
    /// shows the controls (or hides stale ones, and the next tap shows them fresh), as `tapFreshControl` does in the
    /// simulator suites.
    ///
    /// QA-011 D1 rerun (2026-11-23, REC-003-T23): after the 60 s recording the controls had hidden, and four taps at the
    /// tap area's centre never brought them back ("No matches found for record"; the failure dump shows no controls,
    /// only the camera probes, the recording indicator and a thermal notice). The window's centre is where the DEBUG
    /// probe readouts stack on a phone (`showCameraControls`), so the reveal taps land off-centre like
    /// `showCameraControls`: at 62 % and 70 % of the height, below the top status (the recording indicator and its
    /// notice reach 35 %) and above the bottom status.
    @discardableResult
    private func tapCameraControl(_ id: String, ready: @escaping (XCUIElement) -> Bool = { _ in true }) -> Bool {
        let button = app.buttons[id].firstMatch, area = app.otherElements["visualizerTapArea"].firstMatch
        for attempt in 0..<4 {
            var frame = CGRect.zero
            let found = wait(2) {
                guard button.exists, button.isHittable, ready(button) else { return false }
                frame = button.frame
                return !frame.isEmpty
            }
            if found {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
                return true
            }
            if area.exists { area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: attempt % 2 == 0 ? 0.62 : 0.7)).tap() }
        }
        return false
    }

    private func waitControlsHidden() {
        let controls = app.otherElements["controls"]
        _ = wait(8) { !controls.exists }
    }

    /// CAM-002-T21: the front camera with Mirror on, then off: one picture is the other's mirror image.
    func testCAM002MirroredMatchesFlip() throws {
        let task = "CAM-002-T21"
        launchLiveCamera("front", settings: Self.noOverlay.merging(["settings.camera.mirrorFront": true]) { a, _ in a })
        pause(1)
        let (a, mask) = cameraScreenGrid(task, "mirror on")
        try skipUnlessMirrorScene(task, a, mask)
        flipMirror()
        pause(1)
        let (b, _) = cameraScreenGrid(task, "mirror off")
        let mirrored = CameraGrid.correlation(a, CameraGrid.flipped(b), mask), direct = CameraGrid.correlation(a, b, mask)
        report(task, "mirror", ["flippedCorrelation": mirrored, "directCorrelation": direct])
        XCTAssertGreaterThan(mirrored, 0.8, "mirror off is the mirror image of mirror on (\(mirrored))")
        XCTAssertGreaterThan(mirrored, direct + 0.1, "closer to the mirror image (\(mirrored)) than to the same picture (\(direct))")
        XCTAssertTrue(waitCameraLive(), "still live")
    }

    private func saveFramePNG(_ label: String) {
        XCTAssertTrue(tapCameraControl("saveFrame"), "\(label): Save Frame could be tapped")
        let png = app.buttons["PNG"].firstMatch
        if wait(5, { png.exists }) { png.tap() }
        let probe = app.staticTexts["frameCaptureProbe"]
        XCTAssertTrue(wait(10) { ((probe.value as? String) ?? "").hasPrefix("png") }, "\(label): frame saved: \(String(describing: probe.value))")
        pause(1)
    }

    private func recordCamera(seconds: Double, _ label: String) {
        let button = app.buttons["record"]
        XCTAssertTrue(tapCameraControl("record") { $0.label == "Record" }, "\(label): Record is offered (\(button.label))")
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(wait(5) { indicator.exists }, "\(label): the recording indicator")
        pause(seconds)
        XCTAssertTrue(tapCameraControl("record") { $0.label == "Stop recording" }, "\(label): Stop recording (\(button.label))")
        XCTAssertTrue(wait(30) { !indicator.exists }, "\(label): the recording stopped")
        let probe = app.staticTexts["videoRecordingProbe"]
        XCTAssertTrue(wait(30) { ((probe.value as? String) ?? "").hasPrefix("video ") }, "\(label): read back: \(String(describing: probe.value))")
        pause(2)
    }

    private var orientationGridValue: String { (app.staticTexts["cameraOrientationGrid"].value as? String) ?? "" }

    /// The probe's file counts ("files=<frames>/<recordings>"); (0, 0) before its first refresh.
    private func savedFileCounts() -> (frames: Int, videos: Int) {
        guard let part = orientationGridValue.split(separator: " ").first(where: { $0.hasPrefix("files=") }) else { return (0, 0) }
        let n = part.dropFirst(6).split(separator: "/").map { Int($0) ?? 0 }
        return n.count == 2 ? (n[0], n[1]) : (0, 0)
    }

    /// The app's grids of the newest saved frame and recording (`cameraOrientationGrid`), once the folders hold more
    /// files than `before` (the counts read before this label's frame and recording were made).
    /// Pass 3 (2026-11-19, D3): the refresh button's tap never reached it (the grid kept its launch value
    /// "frame=none video=none"); the probe now refreshes by itself when a new file appears (and its button moved
    /// top-leading), and reports the folders' file counts.
    private func savedGrids(_ label: String, after before: (frames: Int, videos: Int)) -> (frame: [Double], video: [Double]) {
        waitControlsHidden()
        let value = { self.orientationGridValue }
        let button = app.buttons["cameraOrientationGridRefresh"]
        print("CAM002-GRID-BUTTON \(label) exists=\(button.exists) hittable=\(button.exists && button.isHittable) frame=\(button.frame)")
        if button.exists, button.isHittable { button.tap() }
        XCTAssertTrue(wait(20) {
            let counts = self.savedFileCounts()
            return value().hasPrefix("frame=") && !value().contains("none") && counts.frames > before.frames
                && counts.videos > before.videos
        }, "\(label): the grids of the new frame and recording: \(value()) (before \(before))")
        var frame: [Double] = [], video: [Double] = []
        for part in value().split(separator: " ") {
            if part.hasPrefix("frame=") { frame = CameraGrid.grid(hex: String(part.dropFirst(6))) }
            if part.hasPrefix("video=") { video = CameraGrid.grid(hex: String(part.dropFirst(6))) }
        }
        return (frame, video)
    }

    /// CAM-002-T22: Mirror flips at once (the first screenshot after Settings closes and one 0.2 s later agree), and
    /// a saved frame and a 3 s recording show the screen's way round, with Mirror off and on.
    func testCAM002MirrorAtOnceAndSavedPicturesMatchTheScreen() throws {
        let task = "CAM-002-T22"
        launchLiveCamera("front", settings: Self.noOverlay.merging(["settings.camera.mirrorFront": true]) { a, _ in a },
                         extra: ["-uitestCaptureDirectory", "B06MirrorFrames", "-uitestRecordingDirectory", "B06MirrorRecordings"])
        pause(1)
        let (a, mask) = cameraScreenGrid(task, "mirror on")
        try skipUnlessMirrorScene(task, a, mask)
        flipMirror()
        let (b, _) = cameraScreenGrid(task, "right after the flip")
        pause(0.2)
        let (c, _) = cameraScreenGrid(task, "0.2 s later")
        let flippedAB = CameraGrid.correlation(a, CameraGrid.flipped(b), mask), directAB = CameraGrid.correlation(a, b, mask)
        let directBC = CameraGrid.correlation(b, c, mask), flippedBC = CameraGrid.correlation(b, CameraGrid.flipped(c), mask)
        report(task, "at once", ["flippedAB": flippedAB, "directAB": directAB, "directBC": directBC, "flippedBC": flippedBC])
        XCTAssertGreaterThan(flippedAB, directAB, "the first screenshot after closing Settings is already flipped")
        XCTAssertGreaterThan(directBC, flippedBC, "and 0.2 s later it has not flipped again")

        for label in ["mirror off", "mirror on"] {
            if label == "mirror on" { flipMirror(); pause(1) }
            waitControlsHidden()
            let (shown, _) = cameraScreenGrid(task, "\(label) before saving")
            let before = savedFileCounts()
            saveFramePNG(label)
            recordCamera(seconds: 3, label)
            let saved = savedGrids(label, after: before)
            for (name, grid) in [("saved frame", saved.frame), ("recording", saved.video)] {
                XCTAssertFalse(grid.isEmpty, "\(label) \(name): a readable picture")
                let same = CameraGrid.correlation(grid, shown, mask)
                let mirrored = CameraGrid.correlation(grid, CameraGrid.flipped(shown), mask)
                report(task, "\(label) \(name)", ["sameCorrelation": same, "mirroredCorrelation": mirrored])
                XCTAssertGreaterThan(same, mirrored, "\(label) \(name): the screen's way round (\(same) vs mirrored \(mirrored))")
            }
        }
    }

    /// CAM-004-T08: Lock exposure reads back locked from the camera; a lens change (D1) and a visual change release it.
    /// "Holds brightness under a real light change" stays a person's (no controlled light): the drift over 3 s is reported.
    func testCAM004ExposureLockReleasedByLensAndVisualChange() {
        let task = "CAM-004-T08"
        launchLiveCamera("back")
        let lock = app.switches["cameraExposureLock"]
        func lockExposure(_ step: String) {
            openSettingsForCamera()
            XCTAssertTrue(revealCameraSetting(lock), "\(step): the Lock exposure row")
            XCTAssertTrue(wait(5) { lock.isEnabled }, "\(step): the switch can be used")
            XCTAssertEqual(lock.value as? String, "0", "\(step): automatic before the lock")
            XCTAssertEqual(flipCameraSettingSwitch(lock), "1", "\(step): locked (read back from the camera)")
            closeSettingsForCamera()
            XCTAssertTrue(wait(3) { self.cameraState()["exposure"] == "locked" }, "\(step): the camera reports locked: \(cameraState())")
        }
        XCTAssertTrue(wait(3) { self.cameraState()["exposure"] == "continuousAuto" }, "automatic at the start: \(cameraState())")
        lockExposure("lock")
        let (first, _) = screen(task, "locked")
        pause(3)
        let (later, _) = screen(task, "locked +3 s")
        report(task, "locked", ["lumaDrift": abs(first.meanLuma - later.meanLuma)])

        if UIDevice.current.userInterfaceIdiom == .phone {
            openSettingsForCamera()
            let lens = app.segmentedControls["cameraLensPicker"]
            XCTAssertTrue(revealCameraSetting(lens), "the Lens row")
            // Tap a lens that is not the running one. QA-011 D1 rerun (2026-11-23): the row lists the lenses widest first
            // (Ultra Wide, Wide) and the camera opens on Wide, so segment 1 was the running lens: the tap changed nothing,
            // the camera never restarted (`starts` stayed 1) and the lock stayed (the app releases it on a real switch,
            // AVCameraFrameProvider.switchLens, CAM-004-R6).
            let segments = lens.buttons.allElementsBoundByIndex
            let shownBefore = lens.value as? String ?? ""
            let other = segments.first { !$0.isSelected } ?? lens.buttons.element(boundBy: 0)
            let otherTitle = other.label
            other.tap()
            XCTAssertTrue(wait(5) { (lens.value as? String ?? "") == otherTitle },
                          "the Lens row shows the other lens: \(shownBefore) → \(lens.value as? String ?? "") (wanted \(otherTitle))")
            closeSettingsForCamera()
            XCTAssertTrue(waitCameraLive(), "the other lens: live")
            XCTAssertTrue(wait(5) { self.cameraState()["exposure"] == "continuousAuto" }, "a lens change releases it: \(cameraState())")
            lockExposure("lock on the other lens")
        }
        chooseVisualForCamera("circularSpectrum")
        XCTAssertTrue(wait(3) { self.cameraState()["exposure"] == "notRunning" }, "another visual: the camera stopped: \(cameraState())")
        chooseVisualForCamera("camera")
        XCTAssertTrue(waitCameraLive(), "Camera again: live")
        XCTAssertTrue(wait(5) { self.cameraState()["exposure"] == "continuousAuto" }, "a visual change released it: \(cameraState())")
        report(task, "released", ["automatic": cameraState()["exposure"] == "continuousAuto" ? 1 : 0])
    }

    /// specs/227-cam-005-focus-point/contracts/focus-point.md: the text for a camera without point focus.
    private enum CameraFocusContract { static let unsupported = "This camera can't focus on a point." }

    private typealias FocusReading = (x: Double, y: Double, mode: String)

    /// "x,y,mode" of the focus read back from the camera (`cameraFocusProbe`).
    private var focus: FocusReading? {
        let parts = cameraProbeText("cameraFocusProbe").split(separator: ",").map(String.init)
        guard parts.count == 3, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return (x, y, parts[2])
    }

    private static func distance(_ a: FocusReading?, _ b: FocusReading?) -> Double {
        guard let a, let b else { return .infinity }
        return ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Double-taps the visualization at a normalized point (after the controls have hidden).
    private func doubleTapPicture(_ x: Double, _ y: Double) {
        waitControlsHidden()
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).doubleTap()
    }

    /// Double-taps and waits for the focus point to move from where it was; returns the new reading.
    private func focusAfterDoubleTap(_ x: Double, _ y: Double, _ step: String) -> FocusReading? {
        let before = focus
        doubleTapPicture(x, y)
        let moved = wait(4) { Self.distance(self.focus, before) > 0.02 }
        print("B06 CAM-005 \(step): \(cameraProbeText("cameraFocusProbe"))")
        XCTAssertTrue(moved, "\(step): the focus point follows the double-tap: \(cameraProbeText("cameraFocusProbe"))")
        return focus
    }

    /// CAM-005-T14: the focus point follows double-taps on the back camera; on the front camera with Mirror on a tap
    /// focuses where the mirrored tap focuses with it off; a tap in Fit's bar does nothing (iPhone); the "Focus at
    /// centre" custom action (VoiceOver's, performed through the DEBUG probe button) focuses at the centre and is
    /// announced. Sharpness on near and far objects stays a person's.
    func testCAM005FocusFollowsDoubleTap() {
        let task = "CAM-005-T14"
        launchLiveCamera("back")
        XCTAssertTrue(wait(5) { self.focus != nil }, "the focus probe: \(cameraProbeText("cameraFocusProbe"))")
        let a = focusAfterDoubleTap(0.3, 0.4, "back A")
        let b = focusAfterDoubleTap(0.7, 0.6, "back B")
        report(task, "back", ["ax": a?.x ?? -1, "ay": a?.y ?? -1, "bx": b?.x ?? -1, "by": b?.y ?? -1])
        XCTAssertGreaterThan(Self.distance(a, b), 0.1, "two taps, two focus points")
        app.terminate()

        // The mirror mapping needs a front camera that focuses on a point. The iPads' front cameras do not (D2, D3
        // 2026-11-18: the focus stayed "0.500,0.500,locked" and the app said "This camera can't focus on a point.",
        // its contract for such a camera, CAM-005-T11): there the contract message is checked and the mapping is not.
        launchLiveCamera("front", settings: ["settings.camera.mirrorFront": true])
        let frontBefore = focus
        doubleTapPicture(0.3, 0.4)
        let frontMoved = wait(4) { Self.distance(self.focus, frontBefore) > 0.02 }
        let unsupported = cameraProbeText("announcementProbe").contains(CameraFocusContract.unsupported)
        report(task, "front point focus", ["supported": frontMoved ? 1 : 0, "unsupportedAnnounced": unsupported ? 1 : 0])
        if frontMoved {
            let mirroredTap = focus
            app.terminate()
            launchLiveCamera("front", settings: ["settings.camera.mirrorFront": false])
            let plainTap = focusAfterDoubleTap(0.7, 0.4, "front mirror off, mirrored point")
            let gap = Self.distance(mirroredTap, plainTap)
            report(task, "front mirror", ["gap": gap])
            XCTAssertLessThan(gap, 0.05, "Mirror on maps a tap to the mirrored point")
        } else {
            XCTAssertTrue(unsupported, "a front camera without point focus says so: \(cameraProbeText("announcementProbe")) "
                          + "(focus \(cameraProbeText("cameraFocusProbe")))")
            print("DEVICE-ACCEPT-NOTE \(task): the front camera cannot focus on a point; the mirror mapping is not checked here")
        }

        // The rest runs on the back camera (the iPads' front camera has no point focus and no "Focus at centre").
        app.terminate()
        if UIDevice.current.userInterfaceIdiom == .phone {   // the iPads' 4:3 screens leave no bar
            launchLiveCamera("back", settings: ["settings.camera.cropMode": "fit"])
            let before = focus
            doubleTapPicture(0.5, 0.92)
            pause(2)
            report(task, "fit bar", ["moved": Self.distance(focus, before)])
            XCTAssertLessThan(Self.distance(focus, before), 0.001, "a double-tap in Fit's bar does nothing")
        } else {
            launchLiveCamera("back")
        }

        // Focus at centre: off centre first, then the action.
        _ = focusAfterDoubleTap(0.35, 0.4, "off centre")
        waitControlsHidden()
        let action = app.buttons["cameraFocusCentreAction"]
        // Pass 3 (2026-11-19, D3): the tap never reached the button at the bottom-leading corner (its value stayed
        // "none"); it sits top-leading now. Its frame and hit state are logged for the next run.
        print("CAM005-FOCUS-BUTTON exists=\(action.exists) hittable=\(action.exists && action.isHittable) frame=\(action.frame)")
        // Pass 4 (2026-11-19, D2 and D3): at the top-leading corner too the hittable button's synthesized tap never ran
        // its action (value "none"), so the focus stayed off centre and nothing was announced. The probe now takes a
        // Darwin notification (UITestFocusCentreRequest); the tap stays as the fallback.
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName("org.projectmios.uitest.cameraFocusCentre" as CFString),
                                             nil, nil, true)
        var via = "notification"
        if !wait(3, { (action.value as? String) != "none" }) {
            via = "tap"
            action.tap()
        }
        print("CAM005-FOCUS-ACTION via=\(via) value=\(String(describing: action.value))")
        XCTAssertTrue(wait(3) { (action.value as? String) == "performed" }, "the custom action was found (\(via)): \(String(describing: action.value))")
        XCTAssertTrue(wait(4) { abs((self.focus?.x ?? 0) - 0.5) < 0.03 && abs((self.focus?.y ?? 0) - 0.5) < 0.03 },
                      "focused at the centre: \(cameraProbeText("cameraFocusProbe"))")
        XCTAssertTrue(wait(3) { self.cameraProbeText("announcementProbe").contains("Focusing at centre") },
                      "announced: \(cameraProbeText("announcementProbe"))")
    }

    /// FX-009-T18: Trails (0.2 s) on Photo and on Camera within the effect tolerance of Trails off; after a cue step
    /// (cue 4 → 5, the Text cue) the first screenshot carries no more of the old scene with Trails than without.
    func testFX009TrailsFrameRateAndNoGhostAfterCueStep() {
        let task = "FX-009-T18"
        for visual in ["photo", "camera"] {
            var rates: [Bool: Double] = [:]
            for trails in [false, true] {
                let settings: [String: Any] = ["settings.feedback.enabled": trails, "settings.feedback.halfLife": 0.2]
                if visual == "camera" {
                    launchLiveCamera("back", settings: settings)
                } else {
                    launch(visual: "photo", settings: settings, extra: ["-uitestSeedPhoto", "pattern"])
                }
                rates[trails] = assertFrameRate(task, "\(visual) trails \(trails ? "on" : "off")")
                app.terminate()
            }
            let cost = (rates[false] ?? 0) - (rates[true] ?? 0)
            report(task, "\(visual) trails cost", ["fps": cost])
            XCTAssertLessThanOrEqual(cost, Self.effectToleranceFPS, "\(visual): Trails costs at most \(Self.effectToleranceFPS) fps")
        }

        var ghost: [Bool: Double] = [:]
        for trails in [false, true] {
            launch(visual: "circularSpectrum", settings: ["settings.feedback.enabled": trails, "settings.feedback.halfLife": 0.5],
                   extra: ["-uitestShowSeed"])
            for _ in 0..<3 {
                showCameraControls()
                app.buttons["showNextCue"].tap()
                pause(1)
            }
            pause(2)
            showCameraControls()
            app.buttons["showNextCue"].tap()
            let (first, _) = screen(task, "trails \(trails ? "on" : "off") right after the step")
            pause(3)
            let (settled, _) = screen(task, "trails \(trails ? "on" : "off") settled")
            XCTAssertTrue(cameraProbeText("showAppliedScene").hasSuffix("|text"), "on the Text cue: \(cameraProbeText("showAppliedScene"))")
            ghost[trails] = first.meanLuma - settled.meanLuma
            app.terminate()
        }
        let extra = (ghost[true] ?? 0) - (ghost[false] ?? 0)
        report(task, "cue step", ["ghostOn": ghost[true] ?? -1, "ghostOff": ghost[false] ?? -1, "extra": extra])
        XCTAssertLessThan(extra, 0.03, "no ghost of the previous scene after a cue step with Trails")
    }

    /// REC-003-T23, the Camera part: 60 s of the back camera at Max (the drawable's size); the file reads back at the
    /// recorded length; frames, dropped slots, size and the thermal state before and after are reported.
    func testREC003SixtySecondCameraRecording() {
        let task = "REC-003-T23"
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        launchLiveCamera("back", settings: ["settings.recording.qualityProfile": "max"],
                         extra: ["-uitestRecordingDirectory", "B06CameraRecording"])
        recordCamera(seconds: 60, "camera 60 s")
        let probe = cameraProbeText("videoRecordingProbe")
        print("B06 \(task) camera: \(probe) facts \(cameraProbeText("recordingFacts"))")
        let parts = probe.split(separator: " ").map(String.init)
        let duration = parts.first { $0.hasPrefix("duration=") }.flatMap { Double($0.dropFirst("duration=".count)) } ?? 0
        let size = parts.count > 2 ? parts[2].split(separator: "x").compactMap { Double($0) } : []
        var facts: [String: Double] = [:]
        for part in cameraProbeText("recordingFacts").split(separator: " ") {
            let kv = part.split(separator: "=")
            if kv.count == 2, let v = Double(kv[1]) { facts[String(kv[0])] = v }
        }
        let thermalAfter = ProcessInfo.processInfo.thermalState.rawValue
        let written = facts["frames"] ?? 0, dropped = facts["dropped"] ?? 0
        report(task, "camera 60 s", ["duration": duration, "width": size.first ?? 0, "height": size.last ?? 0,
                                     "fps": facts["fps"] ?? 0, "written": written, "dropped": dropped,
                                     "droppedShare": written + dropped > 0 ? dropped / (written + dropped) : 0,
                                     "bytes": facts["bytes"] ?? 0, "thermalBefore": Double(thermalBefore),
                                     "thermalAfter": Double(thermalAfter)])
        XCTAssertGreaterThanOrEqual(duration, 58, "about 60 s recorded: \(probe)")
        XCTAssertGreaterThan(written, 0, "frames written")
        XCTAssertGreaterThan(facts["bytes"] ?? 0, 0, "the file exists")
        XCTAssertTrue(waitCameraLive(), "the camera still runs after the recording")
    }
}

extension CameraGrid {
    /// The share of the masked cells brighter than 5 % luma (the per-pixel `nonBlack` level of `screen()`).
    static func litShare(_ g: [Double], _ mask: [Bool]) -> Double {
        guard g.count == mask.count else { return 0 }
        let idx = mask.indices.filter { mask[$0] }
        guard !idx.isEmpty else { return 0 }
        return Double(idx.filter { g[$0] > 0.05 * 255 }.count) / Double(idx.count)
    }
}
