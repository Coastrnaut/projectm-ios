// ParameterMacroUITests.swift — MOD-010-T08 on the iOS Simulator: with the acceptance macro seeded
// (`-uitestSeedMacro`, at 0), Settings → Macros shows the "Glow sweep" slider and its three targets read-only;
// moving the slider changes every target's value label (MOD-010-R10, S5). One short test (owner rule 7: under 30 s).
// The values themselves are proven by ParameterMacroAppTests. Simulator results are never device evidence.
import XCTest

@MainActor
final class ParameterMacroUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        let common: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestSeedMacro",
                                "-uitestSettingsSection", "macros"]   // Settings opens at Macros (owner rule 7)
        app.launchArguments = common + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private func openSettings() {
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    private var slider: XCUIElement { app.slider("macro.0") }
    private func target(_ id: String) -> XCUIElement { app.staticTexts["macroTarget.0." + id] }

    func testMovingTheMacroChangesEveryTargetLabel() {
        launch()
        openSettings()
        // Settings opens scrolled to Macros; let that scroll land before revealing (a drag during it overshoots).
        XCTAssertTrue(slider.appears(within: 5) && slider.settles(), "Settings opened at Macros")
        XCTAssertTrue(app.reveal(slider), "the macro slider is in Settings → Macros")
        XCTAssertEqual(slider.label, "Glow sweep")
        let ids: [String] = ["effect.bloom.intensity", "effect.bloom.radius", "visual.circularSpectrum.barCount"]
        for id in ids { XCTAssertTrue(target(id).exists, "\(id) is listed") }
        XCTAssertTrue(target(ids[0]).label.hasSuffix(": 10%"), target(ids[0]).label)
        XCTAssertTrue(target(ids[2]).label.hasSuffix(": 16"), target(ids[2]).label)
        let before: [String] = ids.map { (id: String) -> String in target(id).label }
        slider.dragSlider(from: 0.02, to: 0.98)
        XCTAssertTrue(poll(5) { self.target(ids[2]).label.hasSuffix(": 128") }, "bars: \(target(ids[2]).label)")
        for (id, old) in zip(ids, before) {
            XCTAssertNotEqual(target(id).label, old, "\(id) changed")
        }
    }
}
