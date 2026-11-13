// RenderFaultUITests.swift — PERF-014-T19 on the iOS Simulator: the roadmap acceptance "Fault injection
// preserves app responsiveness and records reason" (PERF-014-S6).
//
// `-uitestRenderFaults prepare:photo,preset:1` (DEBUG) arms projectM's first preset load to fail as a
// shader that does not compile, and the Photo visual's photo layer to fail its pipeline creation. The
// app's handling is real; only the faults are injected. Simulator results are never device evidence
// (Constitution X); the device run is PERF-014-T22. Waits are ceilings for a slow shared Mac.
import XCTest

@MainActor
final class RenderFaultUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func value(_ id: String) -> String { (app.staticTexts[id].value as? String) ?? "" }
    private func number(_ id: String) -> Int { Int(value(id)) ?? -1 }

    /// See CameraUITests.showControls.
    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Opens Settings, optionally picks a visual, closes it: each step must respond promptly.
    private func openAndCloseSettings(choosing title: String? = nil) {
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5), "Settings opens while a fault is active")
        if let title {
            let row = app.visualRow(title)
            XCTAssertTrue(row.appears(within: 5))
            row.tap()
        }
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5), "and closes")
    }

    private func assertTicksAdvance(_ message: String) {
        let first = number("renderTicks")
        XCTAssertTrue(poll(10) { self.number("renderTicks") > first }, "\(message): the frame loop keeps ticking (\(first) → \(number("renderTicks")))")
    }

    func testInjectedFaultsKeepTheAppResponsiveAndRecordTheReason() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestRenderFaults", "prepare:photo,preset:1",
                               "-uitestSeedPhoto", "solid", "-settings.performanceOverlay", "YES",
                               "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        // projectM: the first preset's shader "does not compile"; projectM keeps rendering (FR-045).
        XCTAssertTrue(poll(10) { self.value("renderHealth").contains("presetLoadFailed") },
                      "the reason is recorded: \(value("renderHealth"))")
        XCTAssertTrue(value("renderHealth").hasPrefix("healthy"), "a failed preset load keeps projectM healthy")
        assertTicksAdvance("projectM")

        // Photo: the photo layer's pipeline cannot be created; the spectrum keeps drawing.
        openAndCloseSettings(choosing: "Photo")
        XCTAssertTrue(app.descendants(matching: .any)["photoVisual"].firstMatch.appears(within: 10))
        XCTAssertTrue(poll(10) { self.value("renderHealth").contains("layerPrepareFailed") },
                      "the reason is recorded: \(value("renderHealth"))")
        assertTicksAdvance("Photo")
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(poll(5) { overlay.label.contains("render: recovering layerPrepareFailed") || overlay.label.contains("render: degraded layerPrepareFailed") },
                      "R14: the FR-048 overlay shows the render line: \(overlay.label)")
        openAndCloseSettings()   // responsive while the layer backs off
        XCTAssertEqual(value("renderPlaceholderShown"), "no", "a layer fault leaves the rest of the visual on screen")

        // Clearing the fault: the photo is back at its next retry (or at once after a loop restart).
        app.buttons["faults:clear"].tap()
        XCTAssertTrue(poll(12) { self.number("visualFrames") > 0 }, "the photo is shown again (\(value("renderHealth")))")
        XCTAssertTrue(poll(5) { self.value("renderHealth").hasPrefix("healthy") }, value("renderHealth"))
        XCTAssertEqual(value("sourceStarts"), "1", "the audio source was never restarted")
        print("PERF-014 evidence: Photo health after recovery: \(value("renderHealth")), ticks \(value("renderTicks"))")
    }
}
