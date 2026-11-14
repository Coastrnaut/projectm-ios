// OverlayContrastUITests.swift — ACC-008-T12 on the iOS Simulator (specs/119-acc-008-high-contrast-overlay;
// ACC-008-R6, S5; contract overlay-surface.md C4).
//
// The contrast numbers come from the unit-test fixtures (OverlayContrastTests). This suite proves the running
// app draws its overlays on the measured backing: the probe `overlaySurfaceProbe` (`-uitestDiagnostics`)
// reports the scrim the views use, standard normally and opaque with the Increase Contrast override
// (`-uitestIncreaseContrast YES`, ACC-003's trait override). Simulator results are never device evidence:
// D1 over bright presets is ACC-008-T16. Owner rule 7: each test < 30 s.
import XCTest

@MainActor
final class OverlayContrastUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["overlaySurfaceProbe"] }

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

    /// The standard scrim, and the source indicator still drawn with its words (layout unchanged).
    func testStandardScrim() {
        launch([])
        XCTAssertTrue(poll(5) { (self.probe.value as? String) == "scrim:0.84" }, "probe: \(probe.value ?? "nil")")
        let indicator = app.staticTexts["sourceIndicator"]
        XCTAssertTrue(indicator.appears(within: 5))
        XCTAssertTrue(indicator.label.hasPrefix("In-App Playback · "), "label unchanged: \(indicator.label)")
        attachScreenshot("acc008-standard")
    }

    /// ACC-008-R6: opaque with Increase Contrast; the controls still open on it.
    func testIncreaseContrastMakesTheScrimOpaque() {
        launch(["-uitestIncreaseContrast", "YES"])
        XCTAssertTrue(poll(5) { (self.probe.value as? String) == "scrim:1.00" }, "probe: \(probe.value ?? "nil")")
        let settings = app.buttons["settings"]
        if !settings.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(settings.appears(within: 5), "the controls are shown")
        attachScreenshot("acc008-increased-contrast")
    }
}
