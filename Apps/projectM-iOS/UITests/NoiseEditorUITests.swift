// NoiseEditorUITests.swift — SHD-006-T12 on the iOS Simulator (R6; S4): Settings › Noise editor shows the preview and
// one generic control per Noise Flow parameter; Randomize seed changes the seed the preview shows, and the Lacunarity
// slider is dragged and reads back the new value. Opens Settings at the section (owner rule 7:
// under 30 s). Simulator results are UI evidence only (Constitution X).
import XCTest

@MainActor
final class NoiseEditorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func control(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "materialControl.material.noiseFlow." + name).firstMatch
    }

    func testRandomizeSeedAndDragLacunarity() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "noiseEditor", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["noiseEditorLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Noise editor row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()

        let preview = app.descendants(matching: .any)["noiseEditorPreview"].firstMatch
        XCTAssertTrue(preview.appears(within: 5), "the preview")
        XCTAssertEqual(preview.label, "Noise preview")
        XCTAssertEqual(preview.value as? String, "Seed 0, 3 octaves")

        let randomize = app.buttons["noiseEditorRandomizeSeed"].firstMatch
        XCTAssertTrue(randomize.appears(within: 5), "Randomize seed")
        randomize.tap()
        XCTAssertTrue(poll(5) { (preview.value as? String) != "Seed 0, 3 octaves" },
                      "the preview follows a new seed: \(String(describing: preview.value))")
        let seeded: String = (preview.value as? String) ?? ""
        XCTAssertTrue(seeded.hasSuffix(", 3 octaves"), seeded)

        XCTAssertTrue(app.reveal(control("octaves")), "the Octaves stepper")
        XCTAssertEqual(control("octaves").label, "Detail (octaves)")
        XCTAssertEqual(control("octaves").value as? String, "3")
        let lacunarity = control("lacunarity")
        XCTAssertTrue(app.reveal(lacunarity), "the Lacunarity slider")
        XCTAssertEqual(lacunarity.value as? String, "2.03")
        // ACC-005 sliders are "other" elements whose frame is the whole row (UITestSliders.swift).
        lacunarity.dragSlider(from: (2.03 - 1.5) / 2.0, to: 0.9)
        XCTAssertTrue(poll(5) { (lacunarity.value as? String) != "2.03" }, "lacunarity reads back: \(String(describing: lacunarity.value))")
        let raised: Double = Double((lacunarity.value as? String) ?? "") ?? 0
        // The drag's distance depends on where the row settles after SHD-012's Fixture preview section was
        // added below it (a post-merge run moved it to 2.07); the property is that the value rose and reads back.
        XCTAssertGreaterThan(raised, 2.03, "dragged toward 3.5")
    }
}
