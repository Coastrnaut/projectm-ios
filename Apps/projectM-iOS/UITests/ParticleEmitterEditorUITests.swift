// ParticleEmitterEditorUITests.swift — SHD-007-T11 on the iOS Simulator (R7; S4): Settings › Particle emitter shows
// the preview; the switch turns the emitter on; the Rate slider is dragged and reads back a higher value (Reset is
// ParticleEmitterEditorTests'). Opens Settings at the section (owner rule 7: under 30 s). Simulator results are UI evidence only
// (Constitution X).
import XCTest

@MainActor
final class ParticleEmitterEditorUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testSwitchAndRate() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum",
                               "-uitestSettingsSection", "particleEmitter", "-uitestSettingsSectionOnce"]
        app.launch()
        if !app.buttons["settings"].appears(within: 10) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()

        let link = app.buttons["particleEmitterLink"].firstMatch
        XCTAssertTrue(link.appears(within: 5), "the Particle emitter row")
        if !link.isHittable { _ = app.reveal(link, down: true) }
        link.tap()

        let preview = app.descendants(matching: .any)["particleEmitterPreview"].firstMatch
        XCTAssertTrue(preview.appears(within: 5), "the preview")
        XCTAssertEqual(preview.label, "Emitter preview")
        XCTAssertTrue(poll(5) { ((preview.value as? String) ?? "").contains("spawned") && (preview.value as? String) != "0 particles, 0 spawned" },
                      "the preview runs: \(String(describing: preview.value))")

        let toggle = app.switches["particleEmitterEnabled"].firstMatch
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(poll(5) { (toggle.value as? String) == "1" }, "the emitter is on")

        let rate = app.descendants(matching: .any).matching(identifier: "particleEmitterRate").firstMatch
        XCTAssertTrue(app.reveal(rate), "the Rate slider")
        XCTAssertEqual(rate.label, "Rate")
        XCTAssertEqual(rate.value as? String, "30")
        rate.dragSlider(from: 30.0 / 240.0, to: 0.8)
        XCTAssertTrue(poll(5) { (rate.value as? String) != "30" }, "rate reads back: \(String(describing: rate.value))")
        XCTAssertGreaterThan(Double((rate.value as? String) ?? "") ?? 0, 30, "dragged up")
    }
}
