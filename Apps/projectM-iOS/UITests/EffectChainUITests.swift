// EffectChainUITests.swift — FX-020-T11 on the iOS Simulator: Settings → Effect order lists Trails then Color; in Edit
// mode Color is dragged above Trails, and the Settings row then reads "Color → Trails" (FX-020-R9, R12; S6). One short
// test (owner rule 7: under 30 s); persistence is proven by `EffectChainSettingTests`. Simulator results are never
// device evidence.
import XCTest

@MainActor
final class EffectChainUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "effects"] + Self.noStore   // Settings opens at Effect order (owner rule 7)
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    private var row: XCUIElement { app.buttons["settings.effectOrder"] }

    private func rowValue() -> String {
        let label: String = row.label
        return label
    }

    func testReorderEffects() {
        launch()
        app.tapFreshControl("settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(app.reveal(row), "Effect order is in Settings")
        XCTAssertTrue(rowValue().contains("Trails \u{2192} Color"), "standard order: \(rowValue())")
        row.tap()
        XCTAssertTrue(app.navigationBars["Effect order"].appears(within: 5))
        app.buttons["effectChain.edit"].tap()
        let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder' AND label CONTAINS 'Color'")).firstMatch
        let trails = app.switches["effectChain.row.fx.trails"]
        XCTAssertTrue(handle.appears(within: 5), "Color's reorder handle")
        XCTAssertTrue(trails.exists)
        handle.press(forDuration: 0.5, thenDragTo: trails)
        app.buttons["effectChain.edit"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertTrue(poll(5) { self.rowValue().contains("Color \u{2192} Trails") }, "reordered: \(rowValue())")
    }
}
