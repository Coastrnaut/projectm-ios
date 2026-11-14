// LayerInspectorUITests.swift — CMP-015-T18 on the iOS Simulator: the roadmap acceptance "Selecting
// different layers shows correct parameters and undo restores prior value" (CMP-015-S1 to S3); CMP-008-T16 adds
// the gradient editor (CMP-008-S6: add, adjust and undo a stop).
// `-uitestLayerInspectorSeed` with `-uitestSeedPhoto solid` makes the three-layer Photo scene of
// contract L5 before the scene history starts. Inspector sliders are ACC-005 accessible elements
// (UITestSliders.swift). Simulator results are never device evidence (Constitution X). Waits are
// ceilings for a slow shared Mac, never frame budgets.
import XCTest

@MainActor
final class LayerInspectorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestSeedPhoto", "solid",
                               "-uitestLayerInspectorSeed"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
    }

    /// See CameraUITests.showControls.
    private func openLayers() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let link = app.buttons["layersLink"]
        XCTAssertTrue(app.reveal(link), "Settings offers Layers")
        XCTAssertTrue(link.label.contains("3 layers"), "the seeded scene has three layers: \(link.label)")
        link.tap()
        XCTAssertTrue(app.navigationBars["Layers"].appears(within: 5))
    }

    private func value(_ identifier: String) -> String? {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch.value as? String
    }

    private func open(_ instance: Int, title: String) {
        let row = app.buttons["layerRow.\(instance)"]
        XCTAssertTrue(row.appears(within: 5), "row \(instance)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].appears(within: 5), "the \(title) detail")
    }

    private func back() {
        app.navigationBars.buttons["Layers"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Layers"].appears(within: 5))
    }

    /// S1: each of the three layers shows its own values.
    func testSelectingEachLayerShowsItsParameters() {
        launch()
        openLayers()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'layerRow.'"))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(app.buttons["layerRow.3"].value as? String, "Layer 3 of 3, read only")

        open(3, title: "Material (plasma)")
        XCTAssertEqual(value("layerValue.opacity"), "50%")
        XCTAssertEqual(value("layerValue.blendMode"), "Add")
        XCTAssertTrue(app.descendants(matching: .any)["layerReadOnlyReason"].exists, "the reason is shown")
        app.buttons["layerHelp.blendMode"].tap()   // US3: contextual help
        let help = app.descendants(matching: .any)["layerHelpText"]
        XCTAssertTrue(help.appears(within: 5), "the help popover opens")
        XCTAssertTrue(help.label.hasPrefix("How the layer mixes"), help.label)
        let dismiss = app.otherElements["PopoverDismissRegion"]   // UIKit's tap-outside region
        if dismiss.exists { dismiss.tap() } else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap() }
        XCTAssertTrue(help.disappears(within: 5))
        back()

        open(2, title: "Circular Spectrum")
        XCTAssertEqual(app.slider("layerControl.opacity").value as? String, "60 percent")
        XCTAssertEqual(app.slider("layerControl.positionX").value as? String, "0.25")
        back()

        open(1, title: "Photo")
        XCTAssertEqual(app.slider("layerControl.opacity").value as? String, "80 percent")
        XCTAssertEqual(app.slider("layerControl.positionX").value as? String, "0.00")
    }

    /// S2, S3: one opacity drag on layer 2 is one undo step, and Undo restores the prior value.
    func testOpacityDragIsOneStepAndUndoRestoresIt() {
        launch()
        openLayers()
        open(2, title: "Circular Spectrum")
        let opacity = app.slider("layerControl.opacity")
        let undo = app.navigationBars["Circular Spectrum"].buttons["sceneUndo"]
        XCTAssertFalse(undo.isEnabled, "nothing to undo yet")
        opacity.dragSlider(from: 0.6, to: 0.15)
        XCTAssertTrue(poll(5) { (opacity.value as? String) != "60 percent" }, "the drag changed the opacity")
        XCTAssertTrue(poll(5) { undo.isEnabled })
        XCTAssertTrue(undo.label.hasPrefix("Undo Circular Spectrum Opacity"), undo.label)
        undo.tap()
        XCTAssertTrue(poll(5) { (opacity.value as? String) == "60 percent" }, "restored: \(String(describing: opacity.value))")
        XCTAssertTrue(poll(5) { !undo.isEnabled }, "the drag was one step")
    }

    /// CMP-008-S6: choose Linear, add a stop, drag stop 2's alpha up (one undo step), and undo it.
    func testGradientStopsCanBeAddedEditedAndUndone() {
        launch()
        openLayers()
        open(1, title: "Photo")
        let picker = app.buttons["layerControl.gradientKind"]
        XCTAssertTrue(app.reveal(picker, long: true), "the Gradient picker")
        picker.tap()
        let linear = app.buttons["Linear"].firstMatch
        XCTAssertTrue(linear.appears(within: 5), "the menu offers Linear")
        linear.tap()
        let add = app.buttons["layerGradientAddStop"]
        XCTAssertTrue(app.reveal(add), "Add Stop")
        add.tap()
        XCTAssertTrue(poll(5) { self.value("layerValue.gradientStops") == "3 stops" }, "a third stop")
        let alpha = app.slider("layerControl.gradientStop2.alpha")
        XCTAssertTrue(app.reveal(alpha), "stop 2's alpha")
        XCTAssertEqual(alpha.value as? String, "0.50", "the new stop takes the gradient's own alpha")
        // A quick drag along the slider's line (the element is the slider alone; `dragSlider`'s slow drag took 6 s).
        let line = alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        line.press(forDuration: 0.05, thenDragTo: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(poll(5) { (Double(alpha.value as? String ?? "") ?? 0) > 0.6 }, "raised: \(String(describing: alpha.value))")
        let undo = app.navigationBars["Photo"].buttons["sceneUndo"]
        XCTAssertTrue(poll(5) { undo.label.hasPrefix("Undo Photo Gradient Stop 2 Alpha") }, undo.label)
        undo.tap()
        XCTAssertTrue(poll(5) { (alpha.value as? String) == "0.50" }, "restored")
        XCTAssertTrue(poll(5) { undo.label.hasPrefix("Undo Photo Gradient Stops") }, "the add is the step before: \(undo.label)")
    }
}
