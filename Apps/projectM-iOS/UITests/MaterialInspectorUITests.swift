// MaterialInspectorUITests.swift — SHD-003-T17 on the iOS Simulator (SHD-003-S5): the seeded scene's
// Plasma layer shows its "Material settings", one control per metadata parameter with the metadata's label
// and the formatted value, disabled while this version does not draw material layers. Same seed as
// LayerInspectorUITests (`-uitestLayerInspectorSeed`, contract L5). Simulator results are never device
// evidence (Constitution X). Waits are ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class MaterialInspectorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openMaterialLayer() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestSeedPhoto", "solid",
                               "-uitestLayerInspectorSeed"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        let link = app.buttons["layersLink"]
        XCTAssertTrue(app.reveal(link), "Settings offers Layers")
        link.tap()
        let row = app.buttons["layerRow.3"]
        XCTAssertTrue(row.appears(within: 5), "the material row")
        row.tap()
        XCTAssertTrue(app.navigationBars["Material (plasma)"].appears(within: 5))
    }

    private func control(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "materialControl.material.plasma." + name).firstMatch
    }

    /// S5: five generated controls with the metadata's labels and the formatted defaults, disabled.
    func testPlasmaLayerShowsItsGeneratedControls() {
        openMaterialLayer()
        let scale = control("scale")
        XCTAssertTrue(app.reveal(scale), "the Material settings section")
        XCTAssertEqual(scale.label, "Scale (waves across the shorter side)")
        XCTAssertEqual(scale.value as? String, "2.00")
        XCTAssertFalse(scale.isEnabled, "read-only until material layers are drawn")
        let brightness = control("brightness")
        XCTAssertTrue(app.reveal(brightness))
        XCTAssertEqual(brightness.label, "Brightness")
        XCTAssertEqual(brightness.value as? String, "45 percent")
        let last = control("audioReactivity")   // the fifth and last generated control
        XCTAssertTrue(app.reveal(last))
        XCTAssertEqual(last.label, "Audio reactivity")
        XCTAssertEqual(last.value as? String, "25 percent")
    }
}
