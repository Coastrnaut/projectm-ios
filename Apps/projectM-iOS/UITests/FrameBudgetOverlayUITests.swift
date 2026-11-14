// FrameBudgetOverlayUITests.swift — PERF-002-T09 (PERF-002-R8, R10, S5) on the iOS Simulator: with the
// performance overlay on and a DEBUG-injected slow render stage (`-uitestSlowStage render:40`, which changes
// only the reported figure, never the rendering), the overlay shows the budget and flags the render pass.
// Simulator numbers are never evidence (Constitution X); only the text is checked. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class FrameBudgetOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testOverlayFlagsTheSlowPass() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.performanceOverlay", "YES",
                               "-uitestSlowStage", "render:40"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15))
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.appears(within: 10))
        XCTAssertTrue(poll(8) { overlay.label.contains("over budget: render cpu 40.00 ms > ") },
                      "the overlay flags the render pass: \(overlay.label)")
        let label = overlay.label
        // 60 fps on the simulator, 30 if the host reports a serious thermal state (FR-049): the format, not the number.
        XCTAssertTrue(label.contains(" fps, limit ") && label.contains(" ms (80%)"), label)
        XCTAssertTrue(label.contains("estimate cpu "), label)
        XCTAssertFalse(label.contains("over budget: audio"), "only the slow pass is flagged: \(label)")
        print("PERF-002 overlay (simulator, not evidence): \(label)")
    }
}
