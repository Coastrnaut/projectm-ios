// CameraExposureUITests.swift — CAM-004-T12 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted -uitestCameraExposureLock <list|none>`, DEBUG only): the roadmap acceptance
// "Supported device changes exposure state; unsupported device explains limit" in the app
// (CAM-004-R1 to R5, R11). Simulator results are never device evidence; a real lock is CAM-004-T08 on D1.
import XCTest

@MainActor
final class CameraExposureUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var positionPicker: XCUIElement { app.segmentedControls["cameraPositionPicker"] }
    private var lockSwitch: XCUIElement { app.switches["cameraExposureLock"] }
    private var note: XCUIElement { app.staticTexts["cameraExposureNote"] }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Launches with the stand-in camera, chooses Camera (it starts at once under the Settings sheet)
    /// and reveals the Lock exposure row.
    private func launchWithCamera(lockable: String?) {
        XCUIDevice.shared.orientation = .portrait
        var arguments: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                   "-uitestCamera", "granted", "-uitestCameraLenses", "wide,ultraWide"]
        if let lockable { arguments += ["-uitestCameraExposureLock", lockable] }
        app.launchArguments = arguments + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(app.reveal(row), "the Camera visual row")
        row.tap()
        XCTAssertTrue(app.reveal(positionPicker), "the Camera section appears")
        XCTAssertTrue(app.reveal(lockSwitch), "the Lock exposure row is shown")
    }

    private func toggleLock() {
        lockSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// US1, S1: a camera that can lock: on → locked, off → automatic, read back from the camera.
    func testSupportedCameraLocksAndReleasesExposure() {
        launchWithCamera(lockable: nil)
        XCTAssertTrue(poll(5) { self.lockSwitch.isEnabled }, "running and supported: enabled")
        XCTAssertEqual(lockSwitch.value as? String, "0")
        XCTAssertFalse(note.exists, "no note while the switch can be used")
        toggleLock()
        XCTAssertTrue(poll(3) { (self.lockSwitch.value as? String) == "1" }, "locked")
        toggleLock()
        XCTAssertTrue(poll(3) { (self.lockSwitch.value as? String) == "0" }, "released")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }

    /// US2, S2, R11: a camera that cannot lock: disabled, with the explanation.
    func testUnsupportedCameraExplainsTheLimit() {
        launchWithCamera(lockable: "none")
        XCTAssertFalse(lockSwitch.isEnabled, "disabled")
        XCTAssertEqual(lockSwitch.label, "Lock exposure")
        XCTAssertEqual(note.label, "This camera can't lock exposure.", "the limit is explained")
        toggleLock()
        XCTAssertEqual(lockSwitch.value as? String, "0", "nothing changes")
    }
}
