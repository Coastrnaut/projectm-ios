// CameraProbeReachUITests.swift — QA-011 D1 r16 (2026-11-24, CAM-002-T22): the DEBUG camera device probes
// (`-uitestCameraDeviceProbes`, Debug/UITestCameraDeviceProbes.swift) must never cover the controls. Their invisible
// readouts (opacity 0.01) wrapped at the window's width; once Save Frame wrote a file, `cameraOrientationGrid` held a
// 384-digit hex grid, the readouts grew several lines over the iPhone's controls card, and Record and Save Frame read
// "not hittable" (the accessibility hit test finds invisible text too). Rehearsed here with Circular Spectrum (no
// camera on the simulator; the probes and the grid of the saved frame do not need one) on an iPhone simulator.
// Simulator results are never device evidence (Constitution X). Owner rule 7: under 30 s.
import XCTest

@MainActor
final class CameraProbeReachUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    func testRecordAndSaveFrameStayHittableAfterTheGridFills() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-settings.visual", "circularSpectrum", "-uitestCameraDeviceProbes",
                               "-uitestCaptureDirectory", "CameraProbeReachUITests"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.tapFreshControl("saveFrame")
        let png = app.buttons["PNG"].firstMatch
        XCTAssertTrue(png.appears(within: 5), "the format choice")
        png.tap()
        // The probe refreshes by itself once the new file appears (checked every second).
        let grid = app.staticTexts["cameraOrientationGrid"]
        XCTAssertTrue(poll(10) { ((grid.value as? String) ?? "").contains("files=") && !((grid.value as? String) ?? "").hasPrefix("frame=none") },
                      "the grid of the saved frame: \(String(describing: grid.value))")
        showControls()
        for id in ["record", "saveFrame", "settings"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.appears(within: 3), "\(id) exists")
            XCTAssertTrue(button.isHittable, "\(id) is hittable with the grid filled (frame \(button.frame), grid \(grid.frame))")
        }
    }
}
