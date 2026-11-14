// FrameDropOverlayUITests.swift — PERF-007-T08 (PERF-007-R7, R10) on the iOS Simulator: with the performance overlay
// on, the overlay shows the device display's "frames" line, counting submitted frames, and the presented values read
// "unavailable" (the simulator SDK reports no presented time). Simulator numbers are never evidence (Constitution X);
// only the labels are checked. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class FrameDropOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testOverlayShowsTheDeviceFramesLine() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.performanceOverlay", "YES"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15))
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.appears(within: 10))
        XCTAssertTrue(poll(8) { overlay.label.contains("frames device: ") && !overlay.label.contains("submitted 0,") },
                      "the overlay counts the device display's frames: \(overlay.label)")
        let label = overlay.label
        XCTAssertTrue(label.contains("presented unavailable, late unavailable"), "simulator: unavailable, never 0 — \(label)")
        XCTAssertFalse(label.contains("frames external"), "no external display")
        XCTAssertFalse(label.contains("frames recording"), "no recording")
        print("PERF-007 overlay (simulator, not evidence): \(label)")
    }
}
