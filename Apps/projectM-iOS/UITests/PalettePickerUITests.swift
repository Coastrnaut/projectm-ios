// PalettePickerUITests.swift — UIX-011-T08 on the iOS Simulator (R3, R9; S3): Settings › Palette › New Palette opens
// the editor; colour 1 is changed through the named-colour menu and VoiceOver's description of the swatch follows
// ("Colour 1 of 2, teal, #008080"); Use for This Scene marks it in the list. Opens Settings at the palette row with
// `-uitestSettingsSection palettes` (owner rule 7: under 30 s). `-uitestResetNotice` removes the palette folder.
// Simulator results are UI evidence only (Constitution X).
import XCTest

@MainActor
final class PalettePickerUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testEditASwatchOfANewPaletteAndUseIt() {
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

        let swatch = app.descendants(matching: .any)["paletteSwatch.0"].firstMatch
        XCTAssertTrue(swatch.appears(within: 5), "the editor's first swatch")
        XCTAssertTrue(swatch.label.hasPrefix("Colour 1 of 2, "), swatch.label)
        app.buttons["paletteNamedMenu.0"].firstMatch.tap()
        let teal = app.buttons["Teal"].firstMatch
        XCTAssertTrue(teal.appears(within: 5), "the named colours")
        teal.tap()
        let edited = NSPredicate(format: "label == %@", "Colour 1 of 2, teal, #008080")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "paletteSwatch.0").matching(edited).firstMatch.appears(within: 5),
                      "VoiceOver reads the new colour: \(swatch.label)")

        app.buttons["paletteUseButton"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let used = NSPredicate(format: "value CONTAINS %@", "used by this scene")
        XCTAssertTrue(app.buttons.matching(used).matching(NSPredicate(format: "label == %@", "New Palette")).firstMatch.appears(within: 5),
                      "the list marks the scene's palette")
    }
}
