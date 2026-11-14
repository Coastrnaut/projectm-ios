// CameraFocusUITests.swift — CAM-005-T13 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted [-uitestCameraFocusPoint none]`, DEBUG only): the roadmap acceptance "Tap
// maps view coordinates to camera focus point correctly" in the app (CAM-005-R1, R2, R5, R10). The
// stand-in picture is 64 × 48, upright (no rotation), drawn with Fill over the whole window.
// Simulator results are never device evidence; real focusing is CAM-005-T14 on D1.
import XCTest

@MainActor
final class CameraFocusUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var probe: XCUIElement { app.staticTexts["cameraFocusProbe"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    /// Launches with Camera as the visual and the stand-in camera running (no Settings round trip).
    private func launchWithCamera(focusable: String?) {
        XCUIDevice.shared.orientation = .portrait
        var arguments: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                   "-uitestCamera", "granted"]
        if let focusable { arguments += ["-uitestCameraFocusPoint", focusable] }
        app.launchArguments = arguments + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        chooseCamera()
    }

    private func chooseCamera() {
        let controls = app.otherElements["controls"]
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(app.reveal(row), "the Camera visual row")
        row.tap()
        XCTAssertTrue(app.reveal(app.staticTexts["cameraFocusNote"]), "the focus note is shown")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
    }

    private func probeValue() -> String { (probe.value as? String) ?? probe.label }

    /// US1, S1: a double-tap at a quarter of the width focuses at the camera point drawn there.
    func testDoubleTapFocusesAtTheMappedPoint() {
        launchWithCamera(focusable: nil)
        XCTAssertTrue(poll(5) { self.probeValue().hasSuffix("continuousAuto") }, "running, continuous focus")
        let window: CGRect = app.windows.firstMatch.frame
        let u: Double = 0.25
        area.coordinate(withNormalizedOffset: CGVector(dx: u, dy: 0.5)).doubleTap()
        // Fill: scale = max(W / 64, H / 48); the shown fraction of the width is W / (64 · scale), centred.
        let scale: Double = max(Double(window.width) / 64, Double(window.height) / 48)
        let visible: Double = Double(window.width) / (64 * scale)
        let expectedX: Double = 0.5 + (u - 0.5) * visible
        XCTAssertTrue(poll(3) { self.probeValue().hasSuffix("autoFocus") }, "focused: \(probeValue())")
        let parts: [Substring] = probeValue().split(separator: ",")
        XCTAssertEqual(Double(parts[0]) ?? -1, expectedX, accuracy: 0.01, "x")
        XCTAssertEqual(Double(parts[1]) ?? -1, 0.5, accuracy: 0.01, "y")
        let controls = app.otherElements["controls"]
        let shown: Bool = controls.exists
        area.tap()   // R10: the single tap still toggles the controls
        XCTAssertTrue(poll(3) { controls.exists != shown }, "the single tap toggled the controls")
    }

    /// US2, R5: a camera without a focus point explains its limit and is not focused.
    func testUnsupportedCameraExplainsTheLimit() {
        launchWithCamera(focusable: "none")
        XCTAssertEqual(app.staticTexts["cameraFocusNote"].exists, false, "Settings closed")
        area.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        XCTAssertTrue(app.staticTexts["cameraFocusMessage"].appears(within: 3))
        XCTAssertEqual(app.staticTexts["cameraFocusMessage"].label, "This camera can't focus on a point.")
        XCTAssertTrue(probeValue().hasSuffix("continuousAuto"), "not focused: \(probeValue())")
    }
}
