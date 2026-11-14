// ColorBlindControlsUITests.swift — ACC-003-T13 on the iOS Simulator
// (specs/110-acc-003-color-blind-friendly-controls; ACC-003-R4, R5, R9, R12; contract status-cues.md C3).
//
// The simulator cannot turn on iOS's colour filters, Increase Contrast or Differentiate Without Colour
// from a test, so DEBUG launch arguments force them (`-uitestIncreaseContrast YES` is a trait override on
// the window scenes, the same path as the real setting). The probe `statusAppearanceProbe`
// (`-uitestDiagnostics`) reads what the views see. The grayscale table itself is a unit test
// (ColorBlindControlsTests); this suite proves the overrides reach the running app and that the status
// elements keep their labels. Simulator results are never device evidence: D1 is ACC-003-T17.
// Owner rule 7: each test < 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class ColorBlindControlsUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["statusAppearanceProbe"] }
    private var indicator: XCUIElement { app.staticTexts["sourceIndicator"] }

    private func launch(_ extra: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + extra + Self.noStore
        app.launch()
        XCTAssertTrue(probe.appears(within: 15), "the visualizer and its probe are up")
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Without overrides the app reads the simulator's (default) settings.
    func testStandardAppearanceByDefault() {
        launch([])
        XCTAssertTrue(poll(5) { (self.probe.value as? String) == "contrast:standard dwc:off" }, "probe: \(probe.value ?? "nil")")
        XCTAssertTrue(indicator.appears(within: 5))
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), "the indicator's words are unchanged: \(indicator.label)")
    }

    /// R12: both overrides reach the views; R5: the indicator's label is unchanged; R9's opaque badges
    /// are drawn (screenshot for review).
    func testIncreaseContrastAndDifferentiateWithoutColourOverrides() {
        launch(["-uitestIncreaseContrast", "YES", "-uitestDifferentiateWithoutColor", "YES"])
        XCTAssertTrue(poll(5) { (self.probe.value as? String) == "contrast:increased dwc:on" }, "probe: \(probe.value ?? "nil")")
        XCTAssertTrue(indicator.appears(within: 5))
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), "label unchanged: \(indicator.label)")
        attachScreenshot("acc003-increased-contrast")
    }

    /// R4, R5: with Differentiate Without Colour the camera badge still reads "Camera on" with its
    /// state as the value (the visible words gain " · Live"; the catalog test checks the words).
    func testCameraBadgeWithDifferentiateWithoutColour() {
        launch(["-uitestDifferentiateWithoutColor", "YES", "-uitestCamera", "granted"])
        let settings = app.buttons["settings"]
        let area = app.otherElements["visualizerTapArea"].firstMatch
        if !settings.exists { area.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let status = app.descendants(matching: .any)["cameraIndicatorStatus"].firstMatch
        XCTAssertTrue(status.appears(within: 10), "the camera badge")
        XCTAssertEqual(status.label, "Camera on")
        XCTAssertTrue(poll(5) { (status.value as? String) == "Live" }, "value: \(String(describing: status.value))")
        attachScreenshot("acc003-camera-dwc")
    }
}
