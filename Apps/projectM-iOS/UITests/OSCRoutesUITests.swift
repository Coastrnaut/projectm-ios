// OSC-003-T12: the OSC Routes list in Settings on the iOS Simulator (OSC-003-R6, R10). Settings opens at the OSC
// section (`-uitestSettingsSection osc`), OSC Routes lists the glow routes, and a route's toggle turns it off and on.
// OSC stays off: no listener and no network. Simulator results are never device evidence. Budget: under 30 s
// (owner rule 7).
import XCTest

@MainActor
final class OSCRoutesUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
    }

    func testOSCRoutesListsTheGlowRoutesAndARouteToggles() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.osc.enabled", "NO", "-uitestSettingsSection", "osc"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        openSettings()

        let link = app.buttons["oscRoutesLink"]
        XCTAssertTrue(app.reveal(link, long: true), "OSC Routes is in the OSC section")
        link.tap()
        XCTAssertTrue(app.navigationBars["OSC Routes"].appears(within: 5))

        let route = app.switches["oscRoute_projectm_param_glow_intensity"]
        XCTAssertTrue(app.reveal(route), "the glow intensity alias is listed")
        XCTAssertTrue(app.switches["oscRoute_projectm_param_effect_bloom_intensity"].exists, "the standard route is listed")
        XCTAssertEqual(route.value as? String, "1", "on by default")
        let control = route.switches.firstMatch.exists ? route.switches.firstMatch : route
        control.tap()
        XCTAssertTrue(poll(5) { route.value as? String == "0" }, "turned off")
        control.tap()
        XCTAssertTrue(poll(5) { route.value as? String == "1" }, "turned on again")
    }
}
