// ModulationMatrixUITests.swift — MOD-012-T08 on the iOS Simulator: with the acceptance routes seeded
// (`-uitestSeedModulationMatrix`: kick → glow intensity, LFO 1 → glow intensity as a second layer, band 4 → glow
// radius, constant ranges), Settings → Modulation lists them; turning the LFO layer off changes the probe's
// intensity only (MOD-012-S5, roadmap acceptance). One short test (owner rule 7: under 30 s). The exact values are
// proven by ModulationMatrixTests and ModulationMatrixAppTests. Simulator results are never device evidence.
import XCTest

@MainActor
final class ModulationMatrixUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                "-uitestSeedModulationMatrix", "-uitestSettingsSection", "modulation"]   // owner rule 7
        app.launchArguments = common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openModulation() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let link = app.buttons["modulationLink"]
        XCTAssertTrue(link.appears(within: 5) && link.settles(), "Settings opened at Modulation")
        XCTAssertTrue(app.reveal(link), "the Modulation row is in Settings")
        link.tap()
        XCTAssertTrue(app.navigationBars["Modulation"].appears(within: 5))
    }

    private var probe: XCUIElement { app.staticTexts["modulationProbe"] }

    func testTurningOneRowOffChangesOnlyItsDestination() {
        launch()
        openModulation()
        XCTAssertTrue(probe.appears(within: 5))
        let before: String = probe.label
        XCTAssertEqual(before, "effect.bloom.intensity=0.3000 effect.bloom.radius=0.0400")
        XCTAssertTrue(app.buttons["modulationRoute.effect.bloom.intensity.0"].exists, "layer 1 listed")
        XCTAssertTrue(app.buttons["modulationRoute.effect.bloom.radius.0"].exists, "the radius route listed")
        let lfo = app.switches["modulationRouteEnabled.effect.bloom.intensity.1"]
        XCTAssertTrue(lfo.exists)
        XCTAssertEqual(lfo.value as? String, "1")
        lfo.switches.firstMatch.tap()
        XCTAssertTrue(poll(5) { (self.lfo(at: 1).value as? String) == "0" }, "the LFO layer is off")
        XCTAssertTrue(poll(5) { self.probe.label == "effect.bloom.intensity=0.6000 effect.bloom.radius=0.0400" },
                      "intensity follows the kick alone; the radius is unchanged: \(probe.label)")
        XCTAssertTrue(app.navigationBars["Modulation"].exists, "the switch did not open the route")
    }

    private func lfo(at layer: Int) -> XCUIElement { app.switches["modulationRouteEnabled.effect.bloom.intensity.\(layer)"] }
}
