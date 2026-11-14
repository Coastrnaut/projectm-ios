// FrontCameraUITests.swift — CAM-002-T18 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted`, DEBUG only): Settings › Camera › Front shows the front camera with the
// "Front camera on" badge, and the Mirror switch changes its value (CAM-002-R1, R8, R11; S5). The pixel
// side of the mirror is checked by FrontCameraTests (the acceptance reads pixels, never the eye).
// Simulator results are never device evidence; the device stage covers the real front camera.
import XCTest

@MainActor
final class FrontCameraUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var cameraVisual: XCUIElement { app.descendants(matching: .any)["cameraVisual"].firstMatch }
    private var status: XCUIElement { app.descendants(matching: .any)["cameraIndicatorStatus"].firstMatch }
    private var picker: XCUIElement { app.segmentedControls["cameraPositionPicker"] }
    private var mirror: XCUIElement { app.switches["cameraMirrorToggle"] }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }

    /// S5: Camera › Front, the badge names the front camera, Mirror on by default and off after a tap.
    func testChooseFrontCameraAndToggleMirror() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))

        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        XCTAssertFalse(picker.exists, "no camera controls before Camera is chosen")
        let row = app.visualRow("Camera")
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        XCTAssertTrue(picker.appears(within: 3) || app.reveal(picker, down: true), "the Camera section appears")
        XCTAssertTrue(picker.buttons["Back"].isSelected, "Back by default")
        app.reveal(mirror, down: true)
        XCTAssertEqual(mirror.value as? String, "0", "the rear camera is not mirrored by default")
        picker.buttons["Front"].tap()
        XCTAssertTrue(poll(3) { self.picker.buttons["Front"].isSelected }, "Front chosen")
        XCTAssertTrue(poll(3) { (self.mirror.value as? String) == "1" }, "the front camera is mirrored by default")
        flip(mirror)
        XCTAssertTrue(poll(3) { (self.mirror.value as? String) == "0" }, "Mirror off: \(String(describing: mirror.value))")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))

        XCTAssertTrue(cameraVisual.appears(within: 10), "the Camera visual is shown")
        XCTAssertTrue(poll(5) { self.status.label == "Front camera on" }, "badge: \(status.label)")
        XCTAssertTrue(poll(5) { (self.status.value as? String) == "Live" })
        XCTAssertTrue(poll(5) { (self.cameraVisual.value as? String) == "Live" })
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
