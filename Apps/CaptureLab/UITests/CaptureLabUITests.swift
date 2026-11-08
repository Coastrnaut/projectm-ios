// CaptureLabUITests.swift — simulator UI-flow tests for CaptureLab (tasks T034, T039, T048).
//
// These check UI flow only. Simulator runs are never capture evidence (Constitution X): the iOS
// Simulator SDK has no ScreenCaptureKit, so System/App Capture is always unavailable there. The
// tests are written for the simulator; if the scheme's tests are run on a device, the
// simulator-only assertions are skipped (see each test).
import XCTest

// XCUIApplication and XCUIElement are main-actor APIs, so the tests run on the main actor.
@MainActor
final class CaptureLabUITests: XCTestCase {
    private let explainerText = "Microphone mode listens to sound in the room through your device's microphone. It does not capture audio directly from other apps."
    private lazy var app = XCUIApplication()

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// T034 (FR-080): the chooser lists all three modes with their contract labels. Only on the
    /// simulator is System/App Capture known to be unavailable (no ScreenCaptureKit in the
    /// Simulator SDK); on a device its availability depends on the OS version, so there the test
    /// checks only that all three modes are listed.
    func testChooserShowsAllThreeModes() {
        app.launch()
        for label in ["System/App Capture", "Microphone", "In-App Playback"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 10), "missing mode: \(label)")
        }
        #if targetEnvironment(simulator)
        XCTAssertFalse(app.buttons["System/App Capture"].isEnabled,
                       "no ScreenCaptureKit in the Simulator SDK, so the mode must be unavailable (FR-004)")
        XCTAssertTrue(app.buttons["Microphone"].isEnabled)
        XCTAssertTrue(app.buttons["In-App Playback"].isEnabled)
        #endif
        attachScreenshot(named: "chooser")
    }

    /// T048 (FR-005, FR-019): the explainer appears before the system microphone prompt, and the
    /// prompt carries the same text (NSMicrophoneUsageDescription). Skipped on a device, because
    /// it resets and then grants CaptureLab's microphone permission, which would disturb the
    /// tester's permission scenarios (T049).
    func testMicrophoneExplainerAppearsBeforeSystemPrompt() throws {
        try XCTSkipUnless(Self.isSimulator, "resets the microphone permission; simulator only")
        app.resetAuthorizationStatus(for: .microphone)
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        XCTAssertTrue(app.buttons["Microphone"].waitForExistence(timeout: 10))
        app.buttons["Microphone"].tap()
        XCTAssertTrue(explainerLabel(in: app).waitForExistence(timeout: 5), "explainer not shown")
        XCTAssertEqual(springboard.alerts.count, 0, "system prompt appeared before the explainer was acknowledged")
        attachScreenshot(named: "explainer")

        app.buttons["Continue"].tap()
        let prompt = springboard.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "system microphone prompt did not appear after Continue")
        XCTAssertTrue(explainerLabel(in: prompt).exists, "prompt text differs from the explainer (FR-019)")
        attachScreenshot(named: "system-prompt")
        let allow = prompt.buttons["Allow"].firstMatch   // iOS 27.2 exposes more than one match
        (allow.exists ? allow : prompt.buttons.firstMatch).tap()
    }

    /// T039: drives background, foreground and Export. XCUITest cannot read the app's files, so
    /// this test does not check the exported JSON itself. Afterwards, run
    /// `python3 scripts/check_capturelab_export.py --udid <simulator UDID>`: it reads the newest
    /// CaptureLab-*.json from CaptureLab's tmp folder and checks that `background` comes before
    /// `foreground` with non-decreasing times. Lock/unlock cannot be driven with public APIs, so
    /// they are left to device runs (T041).
    func testBackgroundForegroundAreExported() {
        app.launch()
        XCTAssertTrue(app.buttons["In-App Playback"].waitForExistence(timeout: 10))
        app.buttons["In-App Playback"].tap()
        XCTAssertTrue(app.staticTexts["Active audio"].waitForExistence(timeout: 15),
                      "In-App Playback did not reach Active audio on the simulator")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // The window can still be animating back from the Home screen after activate(), when
        // the toolbar button has no hit point yet; wait until it can be tapped.
        tapWhenHittable(app.buttons["Export"])
        tapWhenHittable(app.buttons["Create export"])
        XCTAssertTrue(app.buttons["Share files"].waitForExistence(timeout: 10), "export was not created")
        attachScreenshot(named: "export")
    }

    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 10,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                              object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: timeout), .completed,
                       "\(element) is not hittable", file: file, line: line)
        element.tap()
    }

    /// String queries are limited to 128 characters, so the long explainer text is matched by label.
    private func explainerLabel(in element: XCUIElement) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "label == %@", explainerText)).firstMatch
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
