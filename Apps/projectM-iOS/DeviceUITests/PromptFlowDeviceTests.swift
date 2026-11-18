// PromptFlowDeviceTests.swift — QA-011 Batch 1: the self-answering prompt flow (owner rule 14 as amended
// 2026-11-18: prompting tests are automated in their own prompt-flow batch). After a fresh install made by the Mac
// (`python3 scripts/mac_device_driver.py prompt-flow --device D1`: uninstall, install, fixtures, then this class
// alone), each test meets iOS's real permission prompts and answers them itself through springboard: Don't Allow
// first, then the grants in Settings, so every later unattended batch finds camera, microphone, Local Network and
// Photos (add only) granted.
//
// It never runs inside another batch: every unattended run passes
// `-skip-testing:projectM-iOSDeviceUITests/PromptFlowDeviceTests`. The tests depend on one another's order (XCTest
// runs a class's tests in name order: testA … testZ) and on the fresh install; a run over an install whose prompts
// were already answered fails at the first prompt it expects, with that instruction.
//
// UIX-001-T14 (A): fresh install, the tutorial to Play with no prompt; audits per step (Airplane Mode: not required,
//   owner ruling 2026-11-18).
// UIX-015-T14 (B, C): the explainer, then iOS's camera / Local Network prompt; Don't Allow; again: no explainer,
//   the fallback. OSC-001-T26 (C): the Local Network prompt appears on the first enable.
// FILE-013-T11 (D): Microphone, Camera and Local Network denied; using each shows the catalog's notice.
// CAM-001-T25 (E): denied → notice, Open Settings brings Settings; grant there; live; revoke while backgrounded →
//   iOS ends the app; on return the notice, no crash (the Mac checks the device's crash logs too).
// REC-011-T16 (F): Save to Photos → the add-only prompt → Allow → saved; a frame too; Photos off → the denied
//   notice, the file still offered.
// Z: grants everything for the unattended batches, sends the OSC test value (with the Mac's OSC driver), and seeds
//   the photo library from the Documents fixtures (`-uitestSeedPhotoLibrary`).
// Each test is under 3 minutes on D1; nothing waits for a person.
import UIKit
import XCTest

@MainActor
final class PromptFlowDeviceTests: DeviceAcceptanceCase {
    private lazy var system = SystemUI(app: app)

    override func tearDown() async throws {
        system.restore()   // only what a test changed without `keep`
        try await super.tearDown()
    }

    // The catalog's texts (Apps/projectM-iOS/Coordinators/PermissionCatalog.swift; the simulator suites assert the same).
    private static let micDenied = "Microphone permission denied. Enable it in Settings › Privacy › Microphone."
    private static let cameraDenied = "Camera access is off. To show the camera, allow it in Settings."
    private static let cameraFallback = "Showing the spectrum only."
    private static let networkDenied = "Local network access is off for projectM in Settings › Privacy & Security › Local Network."
    private static let networkFallback = "OSC control is unavailable; everything else works as usual."
    private static let photosDenied =
        "Photos access is off. To save to Photos, allow adding photos for projectM in Settings. The file is still in the app."
    private static let freshInstall = "run this class through `python3 scripts/mac_device_driver.py prompt-flow` (a fresh install)"
    /// The Documents fixtures added to Photos in testZ (scripts/make_media_fixtures.py, install_test_fixtures.py).
    private static let photoLibraryFixtures = ["photo-gps.heic", "photo-transparent.png", "video-h264-1080p.mp4"]

    // MARK: Helpers

    private func launchApp(_ arguments: [String], visual: String? = "circularSpectrum") {
        XCUIDevice.shared.orientation = .portrait
        var args = arguments + ["-uitestUnlocked", "NO"]
        if let visual {
            let json = (try? JSONSerialization.data(withJSONObject: ["settings.visual": visual]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            args += ["-uitestDefaults", json]
        }
        app.launchArguments = args
        app.launch()
    }

    private func launchVisualizer(_ extra: [String] = [], reset: Bool = true, visual: String? = "circularSpectrum") {
        launchApp((reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-autostart", "inAppPlayback"] + extra,
                  visual: reset ? visual : nil)
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists }, "the source started")
    }

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
        let done = app.navigationBars["Settings"].buttons["Done"]
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    private func reveal(_ element: XCUIElement) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) { list.swipeUp(velocity: .slow) }
        for _ in 0..<4 where !(element.exists && element.isHittable) { list.swipeDown(velocity: .slow) }
    }

    private func tapVisualRow(_ raw: String) {
        let row = app.buttons["visual.\(raw)"]
        reveal(row)
        XCTAssertTrue(row.isHittable, "the \(raw) row")
        row.tap()
    }

    /// The OSC switch, tapped at its knob (a centre tap hits the label; docs/autotester.md).
    private func tapOSCToggle() {
        let toggle = app.switches["oscReceiverToggle"].firstMatch
        reveal(toggle)
        XCTAssertTrue(toggle.exists, "the OSC switch")
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if !wait(3, { (toggle.value as? String) != before }) { toggle.switches.firstMatch.tap() }
    }

    private func explainer(_ permission: String) -> XCUIElement {
        app.descendants(matching: .any)["permissionExplainer.\(permission)"].firstMatch
    }

    private func label(_ id: String, timeout: Double = 10) -> String {
        let element = app.staticTexts[id]
        return wait(timeout, { element.exists }) ? element.label : ""
    }

    /// Waits for iOS's prompt and answers it; fails (with the fresh-install instruction) when none comes.
    @discardableResult
    private func expectPrompt(_ what: String, containing words: [String], answer: String, timeout: Double = 12) -> Bool {
        guard let alert = system.systemAlert(timeout: timeout) else {
            XCTFail("\(what): no iOS prompt within \(Int(timeout)) s; \(Self.freshInstall)")
            return false
        }
        let text = system.alertText(alert)
        XCTAssertTrue(words.contains { text.localizedCaseInsensitiveContains($0) }, "\(what): the prompt is iOS's \(what) prompt: \(text)")
        _ = screen("PROMPT", "\(what) prompt")
        system.answerAlert(answer, timeout: 1)
        return true
    }

    private var cameraNotice: XCUIElement { app.otherElements["cameraNotice"] }

    // MARK: A: UIX-001-T14

    /// Fresh install: the tutorial's five steps to Play with no sign-in, network or permission prompt at any step; an
    /// accessibility audit of each step. Airplane Mode (the USB cable) is not required (owner ruling 2026-11-18);
    /// VoiceOver listening stays a person's.
    func testA_UIX001FreshInstallOffline() {
        let task = "UIX-001-T14"
        launchApp(["-uitestResetNotice", "-uitestDiagnostics", "-uitestGuidedFirstScene"], visual: nil)
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(wait(15) { acknowledge.exists }, "the photosensitivity notice first")
        acknowledge.tap()
        let guide = app.descendants(matching: .any)["guidedFirstScene"].firstMatch
        XCTAssertTrue(wait(5) { guide.exists }, "the tutorial follows the notice on a new install")
        var issues: [String] = []
        for step in ["welcome", "sound", "visual", "look", "play"] {
            XCTAssertTrue(wait(5) { self.app.staticTexts["guide.step.\(step)"].exists }, "step \(step)")
            XCTAssertNil(system.systemAlert(), "no system prompt at \(step)")
            issues += auditIssues(app, "uix001-\(step)")
            let next = app.buttons["guide.next"]
            if !next.isHittable { app.swipeUp(velocity: .slow) }
            next.tap()
        }
        XCTAssertTrue(wait(5) { !guide.exists }, "Play closes the tutorial")
        XCTAssertTrue(wait(10) { (self.app.staticTexts["visualRunning"].value as? String) == "yes" }, "the scene plays")
        pause(3)
        XCTAssertNil(system.systemAlert(), "no system prompt after Play")
        report(task, "tutorial", ["auditIssues": Double(issues.count)])
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    // MARK: B: UIX-015-T14, camera

    /// The explainer comes first and iOS's camera prompt follows it; Don't Allow; the notice names the fallback;
    /// choosing Camera again shows no explainer, only the notice.
    func testB_UIX015CameraExplainerThenPrompt() {
        let task = "UIX-015-T14"
        launchVisualizer(["-uitestPermissionExplainers"])
        openSettings()
        tapVisualRow("camera")
        XCTAssertTrue(wait(5) { self.explainer("camera").exists }, "the explainer before iOS's prompt")
        XCTAssertNil(system.systemAlert(), "no iOS prompt before Continue")
        app.buttons["permissionExplainerContinue"].tap()
        if system.systemAlert(timeout: 6) == nil { closeSettings() }   // the prompt may wait for the visual
        expectPrompt("camera", containing: ["Camera", "camera"], answer: "Don't Allow")
        closeSettings()
        XCTAssertTrue(wait(10) { self.cameraNotice.exists }, "the denied notice")
        XCTAssertEqual(label("cameraNoticeText"), Self.cameraDenied)
        XCTAssertEqual(label("cameraNoticeFallback"), Self.cameraFallback, "the fallback is named")

        openSettings()
        tapVisualRow("circularSpectrum")
        tapVisualRow("camera")
        XCTAssertFalse(wait(1.5) { self.explainer("camera").exists }, "no explainer after a denial")
        XCTAssertNil(system.systemAlert(timeout: 2), "iOS does not ask again")
        closeSettings()
        XCTAssertTrue(wait(10) { self.cameraNotice.exists }, "the fallback notice again")
        report(task, "camera", ["noticeShown": cameraNotice.exists ? 1 : 0])
    }

    // MARK: C: UIX-015-T14, Local Network; OSC-001-T26 prompt

    /// Turning OSC on explains first, then iOS's Local Network prompt appears (OSC-001-T26's first enable);
    /// Don't Allow; the notice names the fallback; off and on again: no explainer, the notice.
    func testC_UIX015LocalNetworkExplainerThenPrompt() {
        launchVisualizer(["-uitestPermissionExplainers", "-settings.osc.enabled", "NO", "-settings.osc.port", "9000",
                          "-uitestSettingsSection", "osc"])
        openSettings()
        tapOSCToggle()
        XCTAssertTrue(wait(5) { self.explainer("localNetwork").exists }, "the explainer before iOS's prompt")
        XCTAssertNil(system.systemAlert(), "no iOS prompt before Continue")
        app.buttons["permissionExplainerContinue"].tap()
        let prompted = expectPrompt("Local Network", containing: ["local network", "Local Network", "devices on your"],
                                    answer: "Don't Allow", timeout: 15)
        report("OSC-001-T26", "first enable", ["localNetworkPrompt": prompted ? 1 : 0])
        let text = app.staticTexts["localNetworkNoticeText"]
        XCTAssertTrue(wait(15) { text.exists }, "the denied notice")
        reveal(text)
        XCTAssertEqual(text.label, Self.networkDenied)
        XCTAssertEqual(label("localNetworkNoticeFallback"), Self.networkFallback, "the fallback is named")

        tapOSCToggle()   // off
        XCTAssertTrue(wait(10) { !text.exists }, "off clears the notice")
        tapOSCToggle()   // on again
        XCTAssertFalse(wait(1.5) { self.explainer("localNetwork").exists }, "no explainer after a denial")
        XCTAssertNil(system.systemAlert(timeout: 2), "iOS does not ask again")
        XCTAssertTrue(wait(15) { text.exists }, "the notice again")
        report("UIX-015-T14", "local network", ["noticeShown": text.exists ? 1 : 0])
    }

    // MARK: D: FILE-013-T11

    /// Microphone (denied at its prompt), Camera and Local Network (off in Settings): using each shows the catalog's
    /// notice. Screen Time restrictions stay a person's (the Screen Time passcode).
    func testD_FILE013DeniedPermissions() {
        let task = "FILE-013-T11"
        // Microphone: the chooser's row; FR-005's explainer, then iOS's prompt on a fresh install.
        app.terminate()
        launchApp(["-uitestResetNotice"], visual: nil)
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(wait(15) { acknowledge.exists }, "the notice")
        acknowledge.tap()
        let row = app.buttons["Microphone"]
        XCTAssertTrue(wait(10) { row.exists }, "the Microphone row")
        row.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 3) { app.buttons["Continue"].tap() }
        if system.systemAlert(timeout: 8) != nil {
            expectPrompt("microphone", containing: ["Microphone", "microphone"], answer: "Don't Allow", timeout: 1)
        }
        let micText = app.staticTexts.matching(NSPredicate(format: "label == %@", Self.micDenied)).firstMatch
        XCTAssertTrue(wait(10) { micText.exists }, "Microphone: the catalog's denied text")
        XCTAssertTrue(app.buttons["Open Settings"].exists, "Microphone: Open Settings")
        report(task, "microphone", ["notice": micText.exists ? 1 : 0])
        app.terminate()

        // Camera and Local Network: off in Settings (already denied by B and C; set here so D stands alone).
        for permission in [AppPermission.microphone, .camera, .localNetwork] {
            let listed = system.setAppPermission(permission, on: false, keep: true)
            print("PROMPT-FLOW FILE-013: \(permission.rawValue) off in Settings: \(listed ? "set" : "not listed")")
        }
        launchVisualizer()
        openSettings()
        tapVisualRow("camera")
        closeSettings()
        XCTAssertNil(system.systemAlert(timeout: 2), "Camera: no prompt once denied")
        XCTAssertTrue(wait(10) { self.cameraNotice.exists }, "Camera: the notice")
        XCTAssertEqual(label("cameraNoticeText"), Self.cameraDenied, "Camera: the catalog's text")
        report(task, "camera", ["notice": cameraNotice.exists ? 1 : 0])
        app.terminate()

        launchVisualizer(["-settings.osc.enabled", "NO", "-settings.osc.port", "9000", "-uitestSettingsSection", "osc"])
        openSettings()
        tapOSCToggle()
        let text = app.staticTexts["localNetworkNoticeText"]
        XCTAssertTrue(wait(15) { text.exists }, "Local Network: the notice")
        XCTAssertEqual(text.label, Self.networkDenied, "Local Network: the catalog's text")
        XCTAssertTrue(app.buttons["localNetworkOpenSettings"].exists, "Local Network: Open Settings")
        report(task, "local network", ["notice": text.exists ? 1 : 0])
        tapOSCToggle()
    }

    // MARK: E: CAM-001-T25

    /// Denied → the notice and Open Settings (Settings comes forward); allowed there → live; revoked in Settings while
    /// the app is in the background → iOS ends the app; back in the app: the notice, no crash.
    func testE_CAM001DenyThenRevokeWhileBackgrounded() {
        let task = "CAM-001-T25"
        let started = Date()
        app.terminate()
        system.setAppPermission(.camera, on: false, keep: true)
        launchVisualizer()
        openSettings()
        tapVisualRow("camera")
        closeSettings()
        XCTAssertTrue(wait(10) { self.cameraNotice.exists }, "denied: the notice")
        let open = app.buttons["cameraOpenSettings"]
        XCTAssertTrue(open.exists, "Open Settings is offered")
        open.tap()
        XCTAssertTrue(SystemUI.preferences.wait(for: .runningForeground, timeout: 10), "Open Settings brings Settings forward")
        system.setAppPermission(.camera, on: true, keep: true)

        // Allowed: back in the app (iOS may have ended it for the change), Camera live.
        app.activate()
        if !wait(5, { self.app.state == .runningForeground && self.app.staticTexts["sourceStarts"].exists }) {
            launchVisualizer(reset: false)
        }
        let visual = app.descendants(matching: .any)["cameraVisual"].firstMatch
        if !wait(5, { visual.exists }) {
            openSettings()
            tapVisualRow("camera")
            closeSettings()
        }
        XCTAssertTrue(wait(10) { (visual.value as? String) == "Live" }, "allowed: live (\(String(describing: visual.value)))")
        report(task, "allowed", ["live": (visual.value as? String) == "Live" ? 1 : 0])

        // Revoked while in the background.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(wait(10) { self.app.state != .runningForeground }, "in the background")
        system.setAppPermission(.camera, on: false, keep: true)
        let ended = wait(10) { self.app.state == .notRunning }
        report(task, "revoked", ["endedByIOS": ended ? 1 : 0])
        MacDriver.request("device.crashlogs", ["bundle": "org.projectmios.ProjectMiOS", "since": started.timeIntervalSince1970])
        launchVisualizer(reset: false)
        if !wait(5, { visual.exists }) {
            openSettings()
            tapVisualRow("camera")
            closeSettings()
        }
        XCTAssertTrue(wait(10) { self.cameraNotice.exists }, "on return: the notice")
        XCTAssertEqual(label("cameraNoticeText"), Self.cameraDenied)
        XCTAssertEqual(app.state, .runningForeground, "the app runs (no crash)")
        _ = screen(task, "notice after revoke")
    }

    // MARK: F: REC-011-T16

    private func record(seconds: Double) {
        showControls()
        app.buttons["record"].tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(wait(5) { indicator.exists }, "the recording indicator")
        pause(seconds)
        showControls()
        app.buttons["record"].tap()
    }

    private var photosNotice: String {
        let e = app.staticTexts["photosSaveNoticeText"]
        return e.exists ? e.label : ""
    }

    /// Record, Save to Photos: iOS's add-only prompt, Allow, saved; a frame too; then Photos off in Settings:
    /// the denied notice, the recording still offered.
    func testF_REC011SaveToPhotosAllowThenDeny() {
        let task = "REC-011-T16"
        launchVisualizer(["-uitestSeedPhoto", "pattern"], visual: "photo")
        record(seconds: 2)
        let toPhotos = app.buttons["recordingResultPhotos"]
        XCTAssertTrue(wait(15) { toPhotos.exists }, "Recording ready with Save to Photos")
        toPhotos.tap()
        expectPrompt("Photos (add only)", containing: ["Photos", "photo"], answer: "Allow")
        XCTAssertTrue(wait(20) { self.photosNotice == "Saved to Photos." }, "the recording is in Photos: \(photosNotice)")
        XCTAssertTrue(app.buttons["recordingResultShare"].exists, "the recording is still offered")
        report(task, "recording saved", ["saved": photosNotice == "Saved to Photos." ? 1 : 0])
        if app.buttons["photosSaveNoticeDismiss"].exists { app.buttons["photosSaveNoticeDismiss"].tap() }
        if app.buttons["recordingResultDiscard"].exists { app.buttons["recordingResultDiscard"].tap() }

        showControls()
        app.buttons["saveFrame"].tap()
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(wait(5) { png.exists }, "the frame format choice")
        png.tap()
        let framePhotos = app.buttons["frameResultPhotos"]
        XCTAssertTrue(wait(10) { framePhotos.exists }, "Frame ready with Save to Photos")
        framePhotos.tap()
        XCTAssertNil(system.systemAlert(timeout: 2), "no second prompt")
        XCTAssertTrue(wait(10) { self.photosNotice == "Saved to Photos." }, "the frame is in Photos: \(photosNotice)")

        // The new items in Photos, for the record (add-only access cannot read the library back).
        SystemUI.photosApp.launch()
        pause(3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(task) Photos after the saves"
        shot.lifetime = .keepAlways
        add(shot)
        SystemUI.photosApp.terminate()

        // Photos off: the denied notice, the recording still offered.
        app.terminate()
        XCTAssertTrue(system.setAppPermission(.photos, on: false, keep: true), "the Photos row in Settings")
        launchVisualizer(["-uitestSeedPhoto", "pattern"], visual: "photo")
        record(seconds: 2)
        XCTAssertTrue(wait(15) { toPhotos.exists }, "Recording ready")
        toPhotos.tap()
        XCTAssertNil(system.systemAlert(timeout: 2), "no prompt once answered")
        XCTAssertTrue(wait(10) { self.photosNotice == Self.photosDenied }, "the denied notice: \(photosNotice)")
        XCTAssertTrue(app.buttons["photosSaveNoticeSettings"].exists, "Open Settings")
        XCTAssertTrue(app.buttons["recordingResultShare"].exists, "the recording is still offered")
        report(task, "denied", ["notice": photosNotice == Self.photosDenied ? 1 : 0])
        if app.buttons["recordingResultDiscard"].exists { app.buttons["recordingResultDiscard"].tap() }
    }

    // MARK: Z: grants for the unattended batches

    /// Every permission on in Settings (Photos: Add Photos Only); OSC receives the Mac's test value (OSC-001-T26,
    /// with TEST_RUNNER_OSC_DRIVER=1 and scripts/osc_device_driver.py following the log); the photo library gets the
    /// Documents fixtures for the picker tests.
    func testZ_GrantEverythingForUnattendedRuns() {
        app.terminate()
        for permission in AppPermission.allCases {
            let listed = system.setAppPermission(permission, on: true, keep: true)
            print("PROMPT-FLOW grant \(permission.rawValue): \(listed ? "on" : "not listed (never asked on this install)")")
            XCTAssertTrue(listed, "\(permission.rawValue) is listed on the app's Settings page")
        }
        SystemUI.preferences.terminate()

        // OSC with Local Network allowed.
        launchVisualizer(["-settings.osc.enabled", "YES", "-settings.osc.port", "9000", "-uitestSettingsSection", "osc"])
        openSettings()
        let status = app.descendants(matching: .any)["oscStatus"].firstMatch
        reveal(status)
        XCTAssertNil(system.systemAlert(timeout: 2), "Local Network: no prompt once answered")
        XCTAssertTrue(wait(10) { (status.value as? String ?? "").localizedCaseInsensitiveContains("listening") },
                      "OSC listens with Local Network allowed: \(String(describing: status.value))")
        print("OSC-READY test")
        if ProcessInfo.processInfo.environment["OSC_DRIVER"] == "1" {
            let value = app.descendants(matching: .any)["oscTestValue"].firstMatch
            let arrived = wait(20) { ((value.value as? String) ?? value.label).contains("0.42") }
            report("OSC-001-T26", "test value after the grant", ["arrived": arrived ? 1 : 0])
            XCTAssertTrue(arrived, "Test value 0.42 from the Mac")
        }
        closeSettings()
        app.terminate()

        // The photo library seed (add-only, now allowed).
        launchVisualizer(["-uitestSeedPhotoLibrary", Self.photoLibraryFixtures.joined(separator: ",")])
        let probe = app.staticTexts["photoLibrarySeed"]
        XCTAssertNil(system.systemAlert(timeout: 2), "Photos: no prompt once answered")
        XCTAssertTrue(wait(30) { ((probe.value as? String) ?? "").hasSuffix("done=1") }, "the seed finished: \(String(describing: probe.value))")
        let result = (probe.value as? String) ?? ""
        print("PROMPT-FLOW photo library seed: \(result)")
        if result.contains("missing=\(Self.photoLibraryFixtures.count)") {
            print("PROMPT-FLOW photo library seed: no fixtures in Documents (python3 scripts/install_test_fixtures.py --media)")
        } else {
            XCTAssertTrue(result.hasPrefix("status=granted"), result)
            XCTAssertFalse(result.contains("added=0"), "the fixtures were added: \(result)")
        }
    }
}
