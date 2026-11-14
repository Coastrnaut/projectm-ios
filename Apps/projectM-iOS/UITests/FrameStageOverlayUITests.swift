// FrameStageOverlayUITests.swift — PERF-001-T12 (PERF-001-R9, S4) on the iOS Simulator: with the performance
// overlay on, the overlay lists the shown visual's stages. Simulator numbers are never evidence (Constitution X);
// only the labels are checked. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class FrameStageOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testOverlayShowsTheStageLabels() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.performanceOverlay", "YES"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15))
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.appears(within: 10))
        // The native spectrum's pipeline: audio, render, present (encode only while recording).
        XCTAssertTrue(poll(8) { overlay.label.contains("stages ms (median/p95)") && overlay.label.contains("present ") },
                      "the overlay lists the stages: \(overlay.label)")
        let label = overlay.label
        for stage in ["audio ", "render ", "present ", "gpu "] {
            XCTAssertTrue(label.contains(stage), "\(stage) in \(label)")
        }
        XCTAssertFalse(label.contains("encode "), "no recording: no encode stage")
        XCTAssertFalse(label.contains("composite "), "the native spectrum has no compositor stage")
        print("PERF-001 overlay (simulator, not evidence): \(label)")
    }
}
