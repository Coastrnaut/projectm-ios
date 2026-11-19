// B06CameraSystemDeviceTests.swift — QA-011 Batch 4 (automation plan "Batch 4: camera"): the camera tasks that need
// iOS's own UI or the real camera's state, automated on the device with the real cameras. Camera access must already
// be granted (PromptFlowDeviceTests testZ, run alone after a fresh install); no test here meets a permission prompt.
// The app runs with `-uitestCameraDeviceProbes` (DEBUG, Debug/UITestCameraDeviceProbes.swift): `cameraDeviceState`
// counts the app's AVCaptureSession starts and stops (AVFoundation's own notifications), including the stops posted
// while the app was not active, and reads the motion sensor's own state.
//
// The system camera indicator: Control Center's privacy header naming the app with the camera (read by
// `controlCenterCameraUser()`, below) and the green dot in a screenshot (`SystemUI.statusIndicatorDotVisible`).
// Whether a screenshot shows the dot was not checked on D1 yet, so the dot is reported, never asserted; the
// Control Center read is asserted while the camera runs.
//
// CAM-001-T24 / CAM-002-T21 (D1-D3): the indicator names the app while the back and the front camera run.
// CAM-012-T13 (D1): after Stop camera the session has stopped within 1 s (dot sampled at 0.5 and 1.0 s), Control
//   Center no longer shows the camera in use; pause, resume and a background trip do not restart it.
// CAM-001-T27 (D1): another visual, pause, Stop camera and the background each stop the session; a relaunch starts
//   no camera until Camera is chosen.
// CAM-001-T26 (D1, D2): the Camera app takes the camera (a real interruption; no photo is taken), the picture returns;
//   a 3-minute run with the frame rate, the camera pictures and the thermal state every 10 s.
// CAM-013-T17 (D1, D2) / T18 (D3): the Camera app interruption and the recovery probe; revocation in Settings while
//   in the background (iOS ends the app) and the next start is denied (D1, D2; re-granted afterwards).
// CAM-006-T09 (D1): white balance locked, a Siri interruption (Siri must be on), still locked; a lens change and Stop
//   release it. CAM-011-T15 (D1): glow bound to Tilt forward and Shake (`-uitestBindGlowToMotion`) runs the real
//   sensor; Calibrate; the sensor stops while the app is in the background and runs again on return.
// Stays with a person: lock and unlock, a FaceTime call, Split View on D2 (and Retry's back-off with a persisting
// interruption), physical tilt and shake, colours under coloured light, the upright look by eye.
import UIKit
import XCTest

// MARK: Shared camera helpers (B06CameraDeviceTests and B06CameraSystemDeviceTests)

extension DeviceAcceptanceCase {
    var cameraVisualElement: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    var cameraNoticeElement: XCUIElement { app.otherElements["cameraNotice"] }

    /// `cameraDeviceState` as key → value ("running", "starts", "stops", "stopsAway", "exposure", "wb", "motion" …).
    func cameraState() -> [String: String] {
        let text = (app.staticTexts["cameraDeviceState"].value as? String) ?? ""
        var values: [String: String] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { values[String(kv[0])] = String(kv[1]) }
        }
        return values
    }

    func cameraCount(_ key: String) -> Int { Int(cameraState()[key] ?? "") ?? -1 }

    func cameraProbeText(_ id: String) -> String { (app.staticTexts[id].value as? String) ?? "" }

    func showCameraControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { return }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    /// Opens Settings from the controls. Controls that are fading out still exist when checked and are gone when their
    /// button is tapped (D2 2026-11-18, CAM-002-T21: no "settings" button to tap); then they are let go and shown fresh.
    func openSettingsForCamera() {
        let controls = app.otherElements["controls"], settings = app.buttons["settings"]
        for attempt in 0..<2 {
            if attempt == 1 { _ = wait(8) { !controls.exists } }
            showCameraControls()
            if wait(2, { settings.exists && settings.isHittable }) { settings.tap() }
            if wait(5, { self.app.navigationBars["Settings"].exists }) { return }
        }
        XCTFail("Settings opens")
    }

    func closeSettingsForCamera() {
        let done = app.navigationBars["Settings"].buttons["Done"]
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    /// Scrolls the open Settings list until `element` is hittable.
    @discardableResult
    func revealCameraSetting(_ element: XCUIElement) -> Bool {
        let list = app.collectionViews.firstMatch
        for _ in 0..<10 where !(element.exists && element.isHittable) { list.swipeUp(velocity: .slow) }
        for _ in 0..<6 where !(element.exists && element.isHittable) { list.swipeDown(velocity: .slow) }
        return element.exists && element.isHittable
    }

    /// In the open Settings: taps the visual row `raw` ("camera", "circularSpectrum").
    func tapVisualRowForCamera(_ raw: String) {
        let row = app.buttons["visual.\(raw)"]
        XCTAssertTrue(revealCameraSetting(row), "the \(raw) row")
        row.tap()
    }

    /// Opens Settings, chooses the visual `raw` and closes Settings.
    func chooseVisualForCamera(_ raw: String) {
        openSettingsForCamera()
        tapVisualRowForCamera(raw)
        closeSettingsForCamera()
    }

    /// A Settings switch flipped at its knob (a centre tap can hit the label); returns its new value.
    @discardableResult
    func flipCameraSettingSwitch(_ toggle: XCUIElement) -> String {
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if !wait(3, { (toggle.value as? String) != before }) { toggle.switches.firstMatch.tap() }
        _ = wait(3) { (toggle.value as? String) != before }
        return (toggle.value as? String) ?? ""
    }

    /// Launches on the spectrum with the probes and chooses Camera (the camera never starts at launch, CAM-001-R11).
    func launchLiveCamera(_ position: String, settings: [String: Any] = [:], extra: [String] = [], music: Bool = true) {
        launch(visual: "circularSpectrum", settings: settings.merging(["settings.camera.position": position]) { a, _ in a },
               extra: extra + ["-uitestCameraDeviceProbes"], music: music)
        chooseVisualForCamera("camera")
        XCTAssertTrue(wait(10) { self.cameraVisualElement.exists }, "the Camera visual is shown")
        if cameraNoticeElement.exists {
            XCTFail("camera notice instead of a picture: \(app.staticTexts["cameraNoticeText"].label) (camera access: "
                    + "run PromptFlowDeviceTests' grants first)")
        }
        XCTAssertTrue(waitCameraLive(), "the \(position) camera is live: \(cameraState())")
    }

    /// The Camera visual reads "Live" and a capture session runs.
    @discardableResult
    func waitCameraLive(_ timeout: Double = 10) -> Bool {
        wait(timeout) { (self.cameraVisualElement.value as? String) == "Live" && self.cameraCount("running") >= 1 }
    }

    /// A screenshot's grid (attached to the result), with the mask for the screen's shape.
    func cameraScreenGrid(_ task: String, _ label: String) -> (grid: [Double], mask: [Bool]) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(task) \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let size = shot.image.size
        return (CameraGrid.lumaGrid(shot.image), CameraGrid.gridMask(aspect: size.width > 0 ? Double(size.height / size.width) : 2))
    }

}

/// 12 × 16 luma grids of screenshots and of the app's saved frames and recordings (CAM-002 mirror and orientation).
enum CameraGrid {
    static let gridColumns = 12, gridRows = 16

    /// A screenshot drawn into 12 × 16 grey cells, top row first (as the app's `cameraOrientationGrid`).
    static func lumaGrid(_ image: UIImage) -> [Double] {
        guard let cg = image.cgImage else { return [] }
        var cells = [UInt8](repeating: 0, count: gridColumns * gridRows)
        cells.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: buffer.baseAddress, width: gridColumns, height: gridRows, bitsPerComponent: 8,
                                      bytesPerRow: gridColumns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: gridColumns, height: gridRows))
        }
        return cells.map { Double($0) }
    }

    /// The app's hex grid ("0a1b…") as values; empty when it is not a full grid.
    static func grid(hex: String) -> [Double] {
        let chars = Array(hex)
        guard chars.count == gridColumns * gridRows * 2 else { return [] }
        return stride(from: 0, to: chars.count, by: 2).compactMap { Double(Int(String(chars[$0..<$0 + 2]), radix: 16) ?? -1) }
    }

    static func flipped(_ g: [Double]) -> [Double] {
        guard g.count == gridColumns * gridRows else { return g }
        var out = g
        for r in 0..<gridRows { for c in 0..<gridColumns { out[r * gridColumns + c] = g[r * gridColumns + gridColumns - 1 - c] } }
        return out
    }

    /// Cells that count: not the top two rows (overlay, badge, status bar), not the bottom row (home indicator, the
    /// DEBUG probe buttons) and not the centre disc where the spectrum ring moves with the music. Left-right symmetric.
    static func gridMask(aspect: Double) -> [Bool] {
        var mask = [Bool](repeating: false, count: gridColumns * gridRows)
        for r in 2..<(gridRows - 1) {
            for c in 0..<gridColumns {
                let x = (Double(c) + 0.5) / Double(gridColumns) - 0.5
                let y = ((Double(r) + 0.5) / Double(gridRows) - 0.5) * aspect   // in widths
                mask[r * gridColumns + c] = (x * x + y * y).squareRoot() > 0.42
            }
        }
        return mask
    }

    /// Pearson correlation of two grids over the masked cells (0 when either is flat).
    static func correlation(_ a: [Double], _ b: [Double], _ mask: [Bool]) -> Double {
        guard a.count == b.count, a.count == mask.count else { return 0 }
        let idx = mask.indices.filter { mask[$0] }
        guard idx.count > 2 else { return 0 }
        let ma = idx.map { a[$0] }.reduce(0, +) / Double(idx.count), mb = idx.map { b[$0] }.reduce(0, +) / Double(idx.count)
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for i in idx { sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) * (a[i] - ma); sbb += (b[i] - mb) * (b[i] - mb) }
        guard saa > 1, sbb > 1 else { return 0 }
        return sab / (saa * sbb).squareRoot()
    }

    /// How left-right asymmetric the scene is (1 − correlation with its own mirror image); a mirror test needs > 0.15.
    static func asymmetry(_ g: [Double], _ mask: [Bool]) -> Double { 1 - correlation(g, flipped(g), mask) }
}

// MARK: The tests

@MainActor
final class B06CameraSystemDeviceTests: DeviceAcceptanceCase {
    private lazy var system = SystemUI(app: app)

    /// Siri off on the device is a skip with a reason, not a failure (SiriAvailability, AudioProbeSupport.swift).
    override func record(_ issue: XCTIssue) {
        if SiriAvailability.swallow(issue) { return }
        super.record(issue)
    }

    override func tearDown() async throws {
        system.closeControlCenter()
        system.restore()   // a revoked camera permission is granted again here
        try await super.tearDown()
    }

    /// Control Center's privacy header for the camera: an element naming the app and the camera. Opens and closes
    /// Control Center; nil when nothing names both. (SystemUI.controlCenterPrivacyUser matches the app's name alone,
    /// which Now Playing also shows while the music plays; this private helper also requires "camera".)
    private func controlCenterCameraUser(acceptPadPill: Bool = false) -> String? {
        XCUIDevice.shared.orientation = .portrait
        guard system.openControlCenter() else {
            print("B06-SYSTEM Control Center did not open")
            return nil
        }
        pause(0.8)
        let matches = SystemUI.springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", SystemUI.appDisplayName, "camera"))
        var labels = matches.allElementsBoundByIndex.prefix(4).map(\.label)
        // iPadOS (D2 27.2 and D3 26.5, 2026-11-18): the header is a green pill "projectM  Controls ›" whose camera is an
        // icon, so no label names the camera; the run found nothing on any iPad. There the app's name in the top band
        // (the privacy header, above the modules; Now Playing sits lower) counts, as the name of the sensor's user.
        if labels.isEmpty, acceptPadPill, UIDevice.current.userInterfaceIdiom == .pad {
            let height = XCUIScreen.main.screenshot().image.size.height
            let named = SystemUI.springboard.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", SystemUI.appDisplayName)).allElementsBoundByIndex
            labels = named.filter { $0.frame.minY >= 0 && $0.frame.maxY < height * 0.1 }.prefix(4).map(\.label)
            print("B06-SYSTEM Control Center app-name labels (iPad): \(named.prefix(6).map { "\($0.label) @\($0.frame.minY)" })")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Control Center"
        shot.lifetime = .keepAlways
        add(shot)
        system.closeControlCenter()
        print("B06-SYSTEM Control Center camera labels: \(labels)")
        return labels.first
    }

    /// In use: named with the camera, and not as "recently".
    private static func inUse(_ label: String?) -> Bool {
        guard let label else { return false }
        return !label.localizedCaseInsensitiveContains("recent")
    }

    /// Launches the Camera app, lets it run its camera for `seconds` (no photo is taken) and returns to the app.
    ///
    /// The Camera app asks for location on its first launch on a device (D2 2026-11-18: "Allow “Camera” to use your
    /// location?" stayed over the projectM app after the return, and the camera tests after it hung or failed). That
    /// prompt is a person's to answer (owner rule 14): the test skips, naming it, and never taps it.
    private func cameraAppInterruption(seconds: Double = 4) throws {
        SystemUI.camera.launch()
        XCTAssertTrue(SystemUI.camera.wait(for: .runningForeground, timeout: 10), "the Camera app is in front")
        pause(1.5)
        for owner in [SystemUI.springboard, SystemUI.camera] {
            let alert = owner.alerts.firstMatch
            if alert.exists {
                let label = alert.label
                app.activate()
                throw XCTSkip("the Camera app shows a system prompt (\"\(label)\") on this device; a person answers it once "
                              + "in the Camera app (Don't Allow is enough), then this test runs unattended")
            }
        }
        pause(max(0, seconds - 1.5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "back in the app")
    }

    private func homeAndBack(seconds: Double = 3) {
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(seconds)
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
    }

    // MARK: CAM-001-T24, CAM-002-T21: the system indicator while the camera runs

    func testCAM001SystemIndicatorWhileBackAndFrontRun() {
        for (task, position) in [("CAM-001-T24", "back"), ("CAM-002-T21", "front")] {
            launchLiveCamera(position)
            let dot = system.statusIndicatorDotVisible()
            let header = controlCenterCameraUser(acceptPadPill: true)
            report(task, "\(position) indicator", ["greenDot": dot ? 1 : 0, "controlCenterInUse": Self.inUse(header) ? 1 : 0])
            XCTAssertTrue(Self.inUse(header), "\(position): Control Center shows the app using the camera: \(header ?? "nothing")")
            XCTAssertTrue(waitCameraLive(), "\(position): still live after Control Center")
            app.terminate()
        }
    }

    // MARK: CAM-012-T13: Stop camera, indicator off within 1 s

    func testCAM012StopCameraIndicatorOffWithinOneSecond() {
        let task = "CAM-012-T13"
        launchLiveCamera("back")
        let stop = app.buttons["Stop camera"].firstMatch
        XCTAssertTrue(wait(5) { stop.exists }, "the Stop camera button")
        let stopsBefore = cameraCount("stops")
        let t0 = Date()
        stop.tap()
        var dots: [Double] = []
        for at in [0.5, 1.0] {
            pause(max(0, at - Date().timeIntervalSince(t0)))
            dots.append(system.statusIndicatorDotVisible() ? 1 : 0)
        }
        let stopped = wait(1) { self.cameraCount("running") == 0 && self.cameraCount("stops") > stopsBefore }
        let seconds = Date().timeIntervalSince(t0)
        let header = controlCenterCameraUser()
        report(task, "stop", ["sessionStoppedWithin1s": stopped ? 1 : 0, "checkedAt": seconds, "dotAt0_5": dots[0],
                              "dotAt1_0": dots[1], "controlCenterInUse": Self.inUse(header) ? 1 : 0])
        XCTAssertTrue(stopped, "the capture session stopped within about 1 s: \(cameraState())")
        XCTAssertFalse(Self.inUse(header), "Control Center no longer shows the camera in use: \(header ?? "nothing")")

        // Pause, resume and a background trip do not start it again.
        let starts = cameraCount("starts")
        showCameraControls()
        app.buttons["pauseResume"].tap()
        pause(2)
        showCameraControls()
        app.buttons["pauseResume"].tap()
        pause(2)
        homeAndBack()
        pause(2)
        report(task, "no restart", ["startsAfter": Double(cameraCount("starts") - starts)])
        XCTAssertEqual(cameraCount("starts"), starts, "pause, resume and the background start no camera: \(cameraState())")
        XCTAssertFalse(cameraVisualElement.exists, "the Camera visual stays off")
    }

    // MARK: CAM-001-T27: every way of leaving stops the camera

    func testCAM001IndicatorOffEachTime() {
        let task = "CAM-001-T27"
        launchLiveCamera("back")

        // 1. Another visual.
        chooseVisualForCamera("circularSpectrum")
        XCTAssertTrue(wait(3) { self.cameraCount("running") == 0 }, "another visual: the session stops: \(cameraState())")
        let afterVisual = controlCenterCameraUser()
        XCTAssertFalse(Self.inUse(afterVisual), "another visual: not in use in Control Center: \(afterVisual ?? "nothing")")

        // 2. Pause stops it; resume starts it again (CAM-001-R7).
        chooseVisualForCamera("camera")
        XCTAssertTrue(waitCameraLive(), "Camera again: live")
        showCameraControls()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(wait(3) { self.cameraCount("running") == 0 }, "pause: the session stops: \(cameraState())")
        let afterPause = controlCenterCameraUser()
        XCTAssertFalse(Self.inUse(afterPause), "pause: not in use in Control Center: \(afterPause ?? "nothing")")
        showCameraControls()
        app.buttons["pauseResume"].tap()
        XCTAssertTrue(waitCameraLive(), "resume: live again")

        // 3. Stop camera.
        let stop = app.buttons["Stop camera"].firstMatch
        XCTAssertTrue(wait(5) { stop.exists }, "the Stop camera button")
        stop.tap()
        XCTAssertTrue(wait(3) { self.cameraCount("running") == 0 }, "Stop camera: the session stops: \(cameraState())")

        // 4. The background: stopped while away (read on return), live again after it.
        chooseVisualForCamera("camera")
        XCTAssertTrue(waitCameraLive(), "Camera again: live")
        let away = cameraCount("stopsAway")
        homeAndBack()
        XCTAssertGreaterThan(cameraCount("stopsAway"), away, "the background stopped the session: \(cameraState())")
        XCTAssertTrue(waitCameraLive(), "back: live again")
        report(task, "each way", ["stops": Double(cameraCount("stops")), "stopsAway": Double(cameraCount("stopsAway"))])

        // 5. A relaunch (settings kept: the last visual was Camera) starts no camera until Camera is chosen.
        app.terminate()
        app.launchArguments = ["-uitestDiagnostics", "-uitestCameraDeviceProbes", "-autostart", "inAppPlayback",
                               "-uitestUnlocked", "NO"]
        app.launch()
        if app.buttons["acknowledgeNotice"].waitForExistence(timeout: 5) { app.buttons["acknowledgeNotice"].tap() }
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists }, "relaunched")
        pause(5)
        report(task, "relaunch", ["starts": Double(cameraCount("starts"))])
        XCTAssertEqual(cameraCount("starts"), 0, "a relaunch starts no camera: \(cameraState())")
    }

    // MARK: CAM-001-T26: another app takes the camera; 3 minutes running

    func testCAM001CameraAppInterruptionPictureReturns() throws {
        let task = "CAM-001-T26"
        launchLiveCamera("back")
        let away = cameraCount("stopsAway")
        try cameraAppInterruption()
        let t0 = Date()
        XCTAssertTrue(waitCameraLive(), "the picture returns: \(cameraState())")
        report(task, "camera app", ["returnSeconds": Date().timeIntervalSince(t0),
                                    "stoppedWhileAway": cameraCount("stopsAway") > away ? 1 : 0])
        pause(3)
        XCTAssertFalse(cameraNoticeElement.exists, "no notice left once the picture is back")
        assertFrameRate(task, "after the Camera app")
    }

    /// CAM-001-R8: 3 minutes with the camera: frame rate, camera pictures and thermal state every 10 s.
    func testCAM001ThreeMinutesRunning() {
        let task = "CAM-001-T26"
        launchLiveCamera("back")
        func shown() -> Int {
            let text = cameraProbeText("cameraCaptureProbe")
            guard let r = text.range(of: #"shown=(\d+)"#, options: .regularExpression) else { return -1 }
            return Int(text[r].dropFirst("shown=".count)) ?? -1
        }
        var rates: [Double] = [], worstThermal = 0
        var last = shown()
        for i in 1...18 {
            pause(10)
            let fps = overlayFPS() ?? 0
            let now = shown()
            let thermal = ProcessInfo.processInfo.thermalState.rawValue   // the device's, read in the test runner
            worstThermal = max(worstThermal, thermal)
            rates.append(fps)
            report(task, "3 min t=\(i * 10)s", ["fps": fps, "cameraPictures": Double(now - last), "thermal": Double(thermal)])
            XCTAssertGreaterThan(now, last, "t=\(i * 10) s: camera pictures keep arriving")
            last = now
        }
        let median = Self.median(rates)
        report(task, "3 min", ["fpsMedian": median, "fpsMin": rates.min() ?? 0, "worstThermal": Double(worstThermal)])
        XCTAssertGreaterThanOrEqual(median, Self.minimumFPS, "3 min median \(median) fps")
        XCTAssertLessThan(worstThermal, ProcessInfo.ThermalState.critical.rawValue, "never critical")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    // MARK: CAM-013-T17 (D1, D2), T18 (D3): real interruption, recovery probe, revocation

    func testCAM013InterruptionRecoveryAndRevocation() throws {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let ios26 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
        let task = ios26 ? "CAM-013-T18" : "CAM-013-T17"
        launchLiveCamera("back", extra: ["-uitestCameraEvents"])   // the panel's `cameraRecovery` probe
        let recovery = { self.cameraProbeText("cameraRecovery") }
        XCTAssertTrue(wait(5) { recovery().hasPrefix("running|none|") }, "running, no reason: \(recovery())")

        try cameraAppInterruption()
        XCTAssertTrue(waitCameraLive(), "the picture returns after the Camera app: \(cameraState())")
        XCTAssertTrue(wait(5) { recovery().hasPrefix("running|none|") && recovery().contains("|no|") },
                      "running again, no reason, no retry pending: \(recovery())")
        XCTAssertFalse(cameraNoticeElement.exists, "no notice left")
        print("B06-SYSTEM \(task) recovery after the Camera app: \(recovery())")
        report(task, "camera app", ["live": waitCameraLive(1) ? 1 : 0])
        if ios26 { return }   // T18: the iOS 26 path's interruption; revocation is T17's (D1, D2)

        // Revocation while in the background: iOS ends the app; the next start is denied; granted again afterwards.
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        XCTAssertTrue(system.setAppPermission(.camera, on: false), "the Camera switch on the app's Settings page")
        let ended = wait(10) { self.app.state == .notRunning }
        report(task, "revoked", ["endedByIOS": ended ? 1 : 0, "pad": pad ? 1 : 0])
        XCTAssertTrue(ended, "iOS ends the app when camera access is revoked")
        SystemUI.preferences.terminate()
        launch(visual: "circularSpectrum", extra: ["-uitestCameraDeviceProbes"])
        chooseVisualForCamera("camera")
        XCTAssertTrue(wait(10) { self.cameraNoticeElement.exists }, "the next start is denied: the notice")
        XCTAssertEqual(app.staticTexts["cameraNoticeText"].label, "Camera access is off. To show the camera, allow it in Settings.")
        XCTAssertEqual(cameraCount("starts"), 0, "no session started without access: \(cameraState())")
        app.terminate()
        system.setAppPermission(.camera, on: true, keep: true)   // and restore() would too
    }

    // MARK: CAM-006-T09: white balance through an interruption

    private var whiteBalanceSwitch: XCUIElement { app.switches["cameraWhiteBalanceLock"] }

    private func lockWhiteBalance(_ step: String) {
        openSettingsForCamera()
        XCTAssertTrue(revealCameraSetting(whiteBalanceSwitch), "\(step): the Lock white balance row")
        XCTAssertTrue(wait(5) { self.whiteBalanceSwitch.isEnabled }, "\(step): the switch can be used")
        if (whiteBalanceSwitch.value as? String) != "1" { flipCameraSettingSwitch(whiteBalanceSwitch) }
        XCTAssertEqual(whiteBalanceSwitch.value as? String, "1", "\(step): locked (read back from the camera)")
        closeSettingsForCamera()
        XCTAssertTrue(wait(3) { self.cameraState()["wb"] == "locked" }, "\(step): the camera reports locked: \(cameraState())")
    }

    func testCAM006WhiteBalanceLockThroughSiriLensAndStop() throws {
        let task = "CAM-006-T09"
        launchLiveCamera("back")
        lockWhiteBalance("lock")
        let (_, before) = screen(task, "locked")
        SiriAvailability.unavailableSeen = false
        system.siriInterruption()
        try XCTSkipIf(SiriAvailability.unavailableSeen, SiriAvailability.skipReason)
        XCTAssertTrue(waitCameraLive(), "after Siri: live")
        let (_, after) = screen(task, "after Siri")
        report(task, "siri", ["locked": cameraState()["wb"] == "locked" ? 1 : 0, "pictureChange": Self.change(before, after)])
        XCTAssertEqual(cameraState()["wb"], "locked", "still locked after the interruption: \(cameraState())")

        if UIDevice.current.userInterfaceIdiom == .phone {   // D1 has a lens row
            openSettingsForCamera()
            let lens = app.segmentedControls["cameraLensPicker"]
            XCTAssertTrue(revealCameraSetting(lens), "the Lens row")
            lens.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(wait(5) { (self.whiteBalanceSwitch.value as? String) == "0" || !self.whiteBalanceSwitch.exists },
                          "a lens change releases the lock")
            closeSettingsForCamera()
            XCTAssertTrue(waitCameraLive(), "the other lens: live")
            XCTAssertTrue(wait(3) { self.cameraState()["wb"] == "continuousAuto" }, "lens: automatic: \(cameraState())")
            lockWhiteBalance("lock again")
        }
        let stop = app.buttons["Stop camera"].firstMatch
        XCTAssertTrue(wait(5) { stop.exists }, "the Stop camera button")
        stop.tap()
        XCTAssertTrue(wait(3) { self.cameraCount("running") == 0 }, "stopped")
        chooseVisualForCamera("camera")
        XCTAssertTrue(waitCameraLive(), "Camera again: live")
        XCTAssertTrue(wait(3) { self.cameraState()["wb"] == "continuousAuto" }, "after Stop: automatic: \(cameraState())")
        report(task, "stop", ["automatic": cameraState()["wb"] == "continuousAuto" ? 1 : 0])
    }

    // MARK: CAM-011-T15: the motion sensor runs while used and stops in the background

    func testCAM011MotionSensorFollowsDemandAndStopsInBackground() {
        let task = "CAM-011-T15"
        // Without a motion binding and with Settings closed nothing reads motion: the sensor is off.
        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true],
               extra: ["-uitestCameraDeviceProbes"])
        pause(2)
        XCTAssertEqual(cameraState()["motion"], "0", "no binding: the sensor is off: \(cameraState())")
        app.terminate()

        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true],
               // Settings opens at Settings › Motion (as MotionCalibrationUITests): on D2 and D3 (2026-11-18) 16 swipes
               // through the long Settings list did not reach Calibrate.
               extra: ["-uitestCameraDeviceProbes", "-uitestBindGlowToMotion", "-uitestSettingsSection", "motion"])
        XCTAssertTrue(wait(5) { self.cameraState()["motion"] == "1" }, "glow bound to Tilt and Shake: the sensor runs: \(cameraState())")
        report(task, "bound", ["rateHz": Double(cameraState()["rate"] ?? "") ?? -1])

        // Calibrate in Settings › Motion: every attitude value reads 50 % and it is announced.
        openSettingsForCamera()
        let calibrate = app.buttons["motionCalibrateButton"]
        XCTAssertTrue(revealCameraSetting(calibrate), "Calibrate in Settings › Motion")
        calibrate.tap()
        let pitch = app.descendants(matching: .any)["motionReadout.pitch"].firstMatch
        XCTAssertTrue(wait(3) { ((pitch.value as? String) ?? "").hasPrefix("5") }, "Tilt forward near 50 %: \(String(describing: pitch.value))")
        XCTAssertTrue(wait(3) { self.cameraProbeText("announcementProbe").contains("Motion calibrated") },
                      "announced: \(cameraProbeText("announcementProbe"))")
        closeSettingsForCamera()

        // The background stops the sensor (counted while away, read on return); it runs again after.
        let away = cameraCount("motionStopsAway")
        homeAndBack()
        let stoppedAway = cameraCount("motionStopsAway") > away
        report(task, "background", ["stoppedWhileAway": stoppedAway ? 1 : 0,
                                    "samplesWhileAway": Double(cameraCount("awaySamples"))])
        XCTAssertTrue(stoppedAway, "the sensor stopped while the app was in the background: \(cameraState())")
        XCTAssertTrue(wait(5) { self.cameraState()["motion"] == "1" }, "back: the sensor runs again: \(cameraState())")
        assertDrawingAndMoving(task, "glow bound to motion")
    }
}
