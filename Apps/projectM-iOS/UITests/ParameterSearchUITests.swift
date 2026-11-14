// ParameterSearchUITests.swift — UIX-009-T06, T07 on the iOS Simulator (S3, R5-R8): with the circular spectrum on
// screen, Settings › Search Parameters finds the Linear Spectrum's Orientation (another layer's parameter) and
// choosing it opens its UIX-003 inspector; a query with no match shows the empty state first. Opens Settings at the
// search row with `-uitestSettingsSection parameterSearch` (owner rule 7: under 30 s). Simulator results are UI
// evidence only (Constitution X).
import XCTest

@MainActor
final class ParameterSearchUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testSearchFindsAnotherLayersParameterAndOpensItsInspector() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "parameterSearch", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["parameterSearchLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Search Parameters row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.appears(within: 5), "the search field")
        field.tap()
        field.typeText("zzz")
        XCTAssertTrue(app.descendants(matching: .any)["parameterSearchEmpty"].appears(within: 5), "no match: the empty state")

        field.buttons.firstMatch.tap()   // clear
        field.typeText("orientation")
        let result = app.buttons["parameterSearchResult.visual.linearSpectrum.orientation"].firstMatch
        XCTAssertTrue(result.appears(within: 5), "the Linear Spectrum's Orientation is found with the circular spectrum on screen")
        XCTAssertEqual(result.label, "Orientation")
        XCTAssertTrue((result.value as? String)?.hasPrefix("Linear Spectrum, Vertical") ?? false, "group and value: \(String(describing: result.value))")
        XCTAssertFalse(app.buttons["parameterSearchResult.visual.circularSpectrum.barCount"].exists, "only matching parameters")
        result.tap()

        let inspector = app.collectionViews["parameterInspector"].firstMatch
        XCTAssertTrue(inspector.appears(within: 5), "the inspector opens over Settings")
        let id = inspector.descendants(matching: .any).matching(identifier: "parameterInspector.id").firstMatch
        XCTAssertTrue(id.appears(within: 3), "the inspector's ID row")
        let text: String = (id.value as? String) ?? id.label
        XCTAssertTrue(text.contains("visual.linearSpectrum.orientation"), "the inspector shows the chosen ID: \(text)")
    }
}
