// EffectQualityOverlayUITests.swift — PERF-003-T13 (PERF-003-R10, R11) on the iOS Simulator: with the circular
// spectrum's glow on, the performance overlay on and the DEBUG thermal state "serious" (`-uitestThermalState
// serious`, which replaces only the ladder's and the governor's input), the overlay names the reduced effect level.
// Simulator numbers are never evidence (Constitution X); only the text is checked. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class EffectQualityOverlayUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testOverlayNamesTheReducedLevelUnderThermalStress() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.performanceOverlay", "YES",
                               "-settings.circularSpectrum.glow", "YES", "-uitestThermalState", "serious"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["circularSpectrum"].firstMatch.appears(within: 15))
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(overlay.appears(within: 10))
        XCTAssertTrue(poll(8) { overlay.label.contains("effect quality reduced (thermal)") },
                      "the overlay names the reduced level: \(overlay.label)")
        XCTAssertTrue(overlay.label.contains(" fps, limit "), "the budget lines are still there: \(overlay.label)")
        print("PERF-003 overlay (simulator, not evidence): \(overlay.label)")
    }
}
