// PermissionExplainerUITests.swift — UIX-015-T08, T10 (specs/108-uix-015-onboarding-permission-explainer)
// on the iOS Simulator: the explainer before iOS's prompt, Not now asks nothing, Continue goes ahead,
// and after a denial no explainer again and the fallback is visible.
// * Camera: the stand-in (`-uitestCamera notDeterminedDeny` / `denied`); the simulator has no rear
//   camera and its real prompt cannot be scripted. The stand-in never shows a real prompt.
// * Local Network: `-uitestOSCFailure localNetworkDenied` (not scriptable on the simulator).
// * Microphone: the simulator's real permission, never asked (the runner resets it with
//   `xcrun simctl privacy <udid> reset microphone org.projectmios.ProjectMiOS`); FR-005's explainer.
//   The real denial is FILE-013's PermissionAuditUITests.testMicrophoneDeniedForReal… (UIX-015-T11).
// Every launch passes `-uitestPermissionExplainers` (harness launches suppress explainers otherwise).
// Simulator results are never device evidence (UIX-015-T14 is D1). Each test < 30 s (owner rule 7).
import XCTest

@MainActor
final class PermissionExplainerUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static let cameraUsage = "The Camera visual shows the live view from the front or rear camera you choose, behind the visualization. The picture stays on your device: it is never sent, and it is saved only when you save a frame or record the visualization yourself."
    private static let cameraDenied = "Camera access is off. To show the camera, allow it in Settings."
    private static let cameraFallback = "Showing the spectrum only."
    private static let networkDenied = "Local network access is off for projectM in Settings › Privacy & Security › Local Network."
    private static let networkFallback = "OSC control is unavailable; everything else works as usual."

    // MARK: Helpers

    private func launchVisualizer(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestPermissionExplainers"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func explainer(_ permission: String) -> XCUIElement {
        app.descendants(matching: .any)["permissionExplainer.\(permission)"].firstMatch
    }

    private var anyExplainer: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'permissionExplainer.'")).firstMatch
    }

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

    private func tapVisualRow(_ title: String) {
        let row = app.visualRow(title)
        XCTAssertTrue(row.appears(within: 5))
        app.reveal(row, down: true)
        row.tap()
    }

    private func tapOSCToggle() {
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertTrue(app.reveal(toggle), "the OSC section is in Settings")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    private func label(_ id: String) -> String? {
        let element = app.staticTexts[id]
        return element.appears(within: 5) ? element.label : nil
    }

    // MARK: Camera

    /// R1, R3, R4, S1, S3: no explainer at launch; picking Camera explains first; Not now keeps the
    /// visual and asks nothing; the next pick explains again; Continue chooses Camera (the stand-in is
    /// asked once and denies), the notice names the fallback, and a later pick shows no explainer (R6).
    func testCameraExplainerNotNowThenContinueThenNoNagAfterDenial() {
        launchVisualizer(["-uitestCamera", "notDeterminedDeny"])
        XCTAssertFalse(anyExplainer.exists, "never at launch (S1)")
        openSettings()
        tapVisualRow("Camera")
        XCTAssertTrue(explainer("camera").appears(within: 5), "the explainer before iOS's prompt")
        XCTAssertEqual(label("permissionExplainerTitle"), "Camera")
        XCTAssertEqual(label("permissionExplainerText"), Self.cameraUsage, "the catalog's (Info.plist) text")
        XCTAssertEqual(label("permissionExplainerFallback"), "If you don't allow it, the Camera visual shows the spectrum only.")

        app.buttons["permissionExplainerNotNow"].tap()
        XCTAssertTrue(explainer("camera").disappears(within: 5))
        XCTAssertFalse(app.visualRow("Camera").isSelected, "Not now keeps the previous visual")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no permission prompt")

        tapVisualRow("Camera")
        XCTAssertTrue(explainer("camera").appears(within: 5), "the next pick explains again (R4)")
        app.buttons["permissionExplainerContinue"].tap()
        XCTAssertTrue(explainer("camera").disappears(within: 5))
        closeSettings()
        XCTAssertTrue(app.otherElements["cameraNotice"].appears(within: 10), "the stand-in denied: the notice")
        XCTAssertEqual(app.staticTexts["cameraNoticeText"].label, Self.cameraDenied, "CAM-001's text unchanged")
        XCTAssertEqual(app.staticTexts["cameraNoticeFallback"].label, Self.cameraFallback, "what still works (R7)")

        openSettings()
        tapVisualRow("Circular Spectrum")
        tapVisualRow("Camera")
        XCTAssertFalse(explainer("camera").appears(within: 1), "explained once: never again (R6)")
        closeSettings()
        XCTAssertTrue(app.otherElements["cameraNotice"].appears(within: 10), "the new attempt shows the notice")
    }

    /// R6, R7: denied already: no explainer; the notice names the fallback and offers Dismiss; a
    /// dismissed notice stays hidden through Settings; a new pick shows it once more.
    func testCameraDeniedHasFallbackAndDismissPerAttempt() {
        launchVisualizer(["-uitestCamera", "denied"])
        openSettings()
        tapVisualRow("Camera")
        XCTAssertFalse(explainer("camera").appears(within: 1), "denied: no explainer")
        closeSettings()
        let notice = app.otherElements["cameraNotice"]
        XCTAssertTrue(notice.appears(within: 10))
        XCTAssertEqual(app.staticTexts["cameraNoticeFallback"].label, Self.cameraFallback)
        XCTAssertTrue(app.buttons["cameraOpenSettings"].exists, "Open Settings stays")
        app.buttons["cameraDismiss"].tap()
        XCTAssertTrue(notice.disappears(within: 5), "dismissed for this attempt")
        let visual = app.descendants(matching: .any)["cameraVisual"].firstMatch
        XCTAssertEqual(visual.value as? String, "Camera access off", "the visual still says why, the spectrum runs")

        openSettings()
        closeSettings()
        XCTAssertFalse(notice.appears(within: 1), "not back after Settings: no nagging")

        openSettings()
        tapVisualRow("Circular Spectrum")
        tapVisualRow("Camera")
        closeSettings()
        XCTAssertTrue(notice.appears(within: 10), "a new attempt shows it once more")
    }

    /// R12, S4: at the largest accessibility text size the explainer's text and both buttons can be reached.
    func testCameraExplainerAtLargestAccessibilitySize() {
        launchVisualizer(["-uitestCamera", "notDeterminedGrant",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openSettings()
        tapVisualRow("Camera")
        XCTAssertTrue(explainer("camera").appears(within: 5))
        XCTAssertTrue(app.staticTexts["permissionExplainerText"].exists)
        let notNow = app.buttons["permissionExplainerNotNow"], go = app.buttons["permissionExplainerContinue"]
        XCTAssertTrue(app.reveal(go), "Continue can be reached")
        XCTAssertTrue(app.reveal(notNow), "Not now can be reached")
        XCTAssertGreaterThanOrEqual(notNow.frame.minY, go.frame.maxY - 1, "the buttons stack at accessibility sizes")
        notNow.tap()
        XCTAssertTrue(explainer("camera").disappears(within: 5))
    }

    // MARK: Local Network

    /// R2, R3, R4, R6, R8: turning OSC on explains first; Not now leaves OSC off; Continue turns it on,
    /// the denial shows the notice with the fallback; off and on again shows no explainer.
    func testLocalNetworkExplainerThenDeniedNoticeWithoutNagging() {
        launchVisualizer(["-settings.osc.enabled", "NO", "-settings.osc.port", "47128",
                          "-uitestOSCFailure", "localNetworkDenied", "-uitestSettingsSection", "osc"])   // Settings opens at OSC (owner rule 7)
        openSettings()
        tapOSCToggle()
        XCTAssertTrue(explainer("localNetwork").appears(within: 5), "the explainer before iOS's prompt")
        XCTAssertEqual(label("permissionExplainerTitle"), "Local Network")
        app.buttons["permissionExplainerNotNow"].tap()
        XCTAssertTrue(explainer("localNetwork").disappears(within: 5))
        let toggle = app.switches["oscReceiverToggle"]
        XCTAssertEqual(toggle.value as? String, "0", "Not now leaves OSC off")
        XCTAssertFalse(app.staticTexts["localNetworkNoticeText"].exists, "nothing was started")

        tapOSCToggle()
        XCTAssertTrue(explainer("localNetwork").appears(within: 5), "the next try explains again (R4)")
        app.buttons["permissionExplainerContinue"].tap()
        XCTAssertTrue(explainer("localNetwork").disappears(within: 5))
        let text = app.staticTexts["localNetworkNoticeText"]
        XCTAssertTrue(text.appears(within: 10), "the denial's notice")
        app.reveal(text)
        XCTAssertEqual(text.label, Self.networkDenied)
        XCTAssertEqual(app.staticTexts["localNetworkNoticeFallback"].label, Self.networkFallback, "what still works (R8)")

        tapOSCToggle()   // off
        XCTAssertTrue(text.disappears(within: 10))
        tapOSCToggle()   // on again
        XCTAssertFalse(explainer("localNetwork").appears(within: 1), "explained once: never again (R6)")
        XCTAssertTrue(text.appears(within: 10), "the notice again, inline in Settings only")
    }

    // MARK: Microphone (FR-005, unchanged)

    /// R9, S3: the microphone's FR-005 explainer; Cancel asks nothing; the next pick explains again.
    func testMicrophoneExplainerCancelAsksNothing() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestPermissionExplainers"] + Self.noStore
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.appears(within: 15))
        acknowledge.tap()
        let row = app.buttons["Microphone"]
        XCTAssertTrue(row.appears(within: 10))
        row.tap()
        let explainer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                             "Microphone mode listens to sound in the room")).firstMatch
        XCTAssertTrue(explainer.appears(within: 5), "FR-005's explainer before iOS's prompt")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(explainer.disappears(within: 5))
        XCTAssertFalse(springboard.alerts.firstMatch.appears(within: 1), "Cancel: no permission prompt")
        XCTAssertTrue(row.exists, "still on the chooser")
        row.tap()
        XCTAssertTrue(explainer.appears(within: 5), "the next pick explains again while iOS has not asked")
        app.buttons["Cancel"].tap()
    }
}
