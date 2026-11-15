// MotionCalibrationUITests.swift — CAM-011-T11 (CAM-011-R5, R14, S4) on the iOS Simulator: Settings › Motion with
// the DEBUG stand-in motion source (`-uitestMotionStandIn`: tilted forward 0.3 rad; the simulator has no sensors) shows
// "Tilt forward" at 69 % (Medium range), and Calibrate brings every attitude value to 50 %. Settings opens at the
// section (owner rule 7: < 30 s).
import XCTest

@MainActor
final class MotionCalibrationUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testCalibrateBringsTheReadoutToTheMiddle() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestMotionStandIn", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsSection", "motion"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))

        let calibrate = app.buttons["motionCalibrateButton"]
        XCTAssertTrue(calibrate.appears(within: 3) || app.reveal(calibrate), "Settings › Motion › Calibrate")
        let pitch = app.descendants(matching: .any)["motionReadout.pitch"].firstMatch
        let roll = app.descendants(matching: .any)["motionReadout.roll"].firstMatch
        XCTAssertTrue(pitch.exists || app.reveal(pitch, down: true), "the readout")
        XCTAssertEqual(pitch.label, "Tilt forward")
        XCTAssertTrue(poll(3) { (pitch.value as? String) == "69 percent" }, "tilted forward: \(String(describing: pitch.value))")
        XCTAssertTrue(calibrate.isEnabled)

        calibrate.tap()
        XCTAssertTrue(poll(1) { (pitch.value as? String) == "50 percent" }, "calibrated: \(String(describing: pitch.value))")
        XCTAssertTrue(poll(1) { (roll.value as? String) == "50 percent" })
    }
}
