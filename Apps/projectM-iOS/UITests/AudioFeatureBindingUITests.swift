// AudioFeatureBindingUITests.swift — MOD-002-T12 on the iOS Simulator: the mean band level bound to
// the glow intensity moves the effective intensity while the reference track plays, and Unbind returns
// it to the manual intensity (roadmap acceptance on screen; MOD-002 User Story 3, MOD-002-S4).
// Settings come from launch-argument defaults (no Settings taps), so the test stays well under 30 s.
// Simulator results are never device evidence (Constitution X). Waits are ceilings, not budgets.
import XCTest

@MainActor
final class AudioFeatureBindingUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testBandLevelDrivesTheGlowAndUnbindRestoresTheManualIntensity() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-settings.circularSpectrum.glow", "YES",
                               "-uitestBindGlowToLevel"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let readout = app.staticTexts["glowModulation"]
        XCTAssertTrue(readout.appears(within: 10))

        var seen: Set<String> = []
        let moved = poll(15) {
            let text = readout.label
            if text.hasPrefix("bound, manual 0.50, effective ") { seen.insert(text) }
            return seen.count >= 2
        }
        XCTAssertTrue(moved, "the effective glow intensity follows the band level: saw \(seen), now \(readout.label)")

        app.buttons["glowModulationUnbind"].tap()
        XCTAssertTrue(poll(5) { readout.label == "unbound, manual 0.50, effective 0.50" },
                      "unbind restores the manual intensity: \(readout.label)")
    }
}
