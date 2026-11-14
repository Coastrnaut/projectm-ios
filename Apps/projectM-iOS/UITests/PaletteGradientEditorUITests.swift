// PaletteGradientEditorUITests.swift — SHD-005-T11 on the iOS Simulator (R4, R7; S4): Settings › Palette › New Palette
// opens the editor; the Gradient Stops section names each stop ("Stop 2 of 2, …"), Stop 2's Position slider is moved
// and reads back the new value, and Step is chosen. Opens Settings at the palette row (owner rule 7: under 30 s).
// Simulator results are UI evidence only (Constitution X).
import XCTest

@MainActor
final class PaletteGradientEditorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testMoveAStopAndChooseStep() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "palettes", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["paletteLibraryLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Palette row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()
        let new = app.buttons["paletteNewButton"].firstMatch
        XCTAssertTrue(new.appears(within: 5), "New Palette")
        new.tap()

        XCTAssertTrue(app.descendants(matching: .any)["paletteSwatch.0"].firstMatch.appears(within: 5), "the editor")
        let slider = app.slider("paletteStop2.position")
        XCTAssertTrue(app.reveal(slider), "Stop 2's position slider")
        let heading = app.descendants(matching: .any)["paletteStop2.heading"].firstMatch
        XCTAssertTrue(heading.exists, "Stop 2's heading")
        XCTAssertTrue(heading.label.hasPrefix("Stop 2 of 2, "), heading.label)
        XCTAssertEqual(slider.value as? String, "100 percent")
        // ACC-005 sliders are "other" elements (UITestSliders.swift): drag the thumb from the right end along the line.
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        XCTAssertTrue(poll(5) { (slider.value as? String) != "100 percent" },
                      "the position reads back the new value: \(String(describing: slider.value))")
        let spoken: String = (slider.value as? String) ?? ""
        let percent: Int = Int(spoken.replacingOccurrences(of: " percent", with: "")) ?? -1
        XCTAssertTrue((15...45).contains(percent), spoken)

        let picker = app.descendants(matching: .any)["paletteInterpolationPicker"].firstMatch
        _ = app.reveal(picker, down: true)
        let step = picker.buttons["Step"].firstMatch
        XCTAssertTrue(step.appears(within: 5), "the Step segment")
        step.tap()
        XCTAssertTrue(step.isSelected, "Step chosen")
    }
}
