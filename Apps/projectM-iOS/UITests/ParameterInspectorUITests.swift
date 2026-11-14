// ParameterInspectorUITests.swift — UIX-003-T08 on the iOS Simulator (S2, R9): the inspector for the glow
// intensity shows its unit and range, the slider moves the value, and Reset restores the registry default
// ("50 percent"); at the AX5 text size Reset and Done stay reachable. Opened with the DEBUG launch argument
// `-uitestInspectParameter` when Settings appears (the context menu is the user's entry point). Each test
// stays under 30 s (owner rule 7). Simulator results are UI evidence only (Constitution X).
import XCTest

@MainActor
final class ParameterInspectorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launchIntoInspector(extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-uitestInspectParameter", "effect.bloom.intensity"] + extra
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(element("parameterInspector.unit").appears(within: 5), "the inspector opens over Settings")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func value(_ id: String) -> String? { element(id).value as? String }

    func testInspectorShowsUnitAndRangeAndResetRestoresTheDefault() {
        launchIntoInspector()
        XCTAssertEqual(element("parameterInspector.id").value as? String, "effect.bloom.intensity")
        XCTAssertEqual(value("parameterInspector.unit"), "Percent")
        XCTAssertEqual(value("parameterInspector.range"), "0 percent to 100 percent")
        XCTAssertEqual(value("parameterInspector.default"), "50 percent")
        XCTAssertEqual(value("parameterInspector.value"), "50 percent")
        XCTAssertEqual(value("parameterInspector.modulation") ?? element("parameterInspector.modulation").label, "Not modulated")

        let slider = app.slider("parameterInspector.slider")
        XCTAssertTrue(slider.appears(within: 2))
        slider.dragSlider(from: 0.5, to: 0.9)
        XCTAssertTrue(poll(5) { self.value("parameterInspector.value") != "50 percent" }, "the slider moved the value")

        let reset = element("parameterInspector.reset")
        XCTAssertTrue(reset.exists)
        reset.tap()
        XCTAssertTrue(poll(5) { self.value("parameterInspector.value") == "50 percent" }, "Reset restores the registry default")
        XCTAssertEqual(slider.value as? String, "50 percent")
        element("parameterInspector.done").tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testResetAndDoneStayReachableAtTheLargestTextSize() {
        launchIntoInspector(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let reset = element("parameterInspector.reset")
        if !reset.isHittable { _ = app.reveal(reset) }
        XCTAssertTrue(poll(5) { reset.isHittable }, "Reset is reachable at AX5")
        reset.tap()
        XCTAssertEqual(value("parameterInspector.value"), "50 percent")
        XCTAssertTrue(element("parameterInspector.done").isHittable)
    }
}
