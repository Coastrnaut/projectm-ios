// CameraWhiteBalanceUITests.swift — CAM-006-T12 on the iOS Simulator with the stand-in camera
// (`-uitestCamera granted -uitestCameraWhiteBalanceLock <list|none>`, DEBUG only): lock and unlock read
// back from the camera without a restart; an unsupported camera explains the limit (CAM-006-R1 to R6,
// R13). Simulator results are never device evidence; a real lock is CAM-006-T09 on D1.
import XCTest

@MainActor
final class CameraWhiteBalanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var positionPicker: XCUIElement { app.segmentedControls["cameraPositionPicker"] }
    private var lockSwitch: XCUIElement { app.switches["cameraWhiteBalanceLock"] }
    private var note: XCUIElement { app.staticTexts["cameraWhiteBalanceNote"] }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Launches with the stand-in camera, chooses Camera (it starts at once under the Settings sheet)
    /// and reveals the Lock white balance row.
    private func launchWithCamera(lockable: String?) {
        XCUIDevice.shared.orientation = .portrait
        var arguments: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                                   "-uitestCamera", "granted", "-uitestCameraLenses", "wide,ultraWide"]
        if let lockable { arguments += ["-uitestCameraWhiteBalanceLock", lockable] }
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
        XCTAssertTrue(app.reveal(lockSwitch), "the Lock white balance row is shown")
    }

    private func toggleLock() {
        lockSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// US1, S1: a camera that can lock: on → locked, off → automatic, read back from the camera.
    func testSupportedCameraLocksAndReleasesWhiteBalance() {
        launchWithCamera(lockable: nil)
        XCTAssertTrue(poll(5) { self.lockSwitch.isEnabled }, "running and supported: enabled")
        XCTAssertEqual(lockSwitch.label, "Lock white balance")
        XCTAssertEqual(lockSwitch.value as? String, "0")
        XCTAssertFalse(note.exists, "no note while the switch can be used")
        toggleLock()
        XCTAssertTrue(poll(3) { (self.lockSwitch.value as? String) == "1" }, "locked")
        toggleLock()
        XCTAssertTrue(poll(3) { (self.lockSwitch.value as? String) == "0" }, "released")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }

    /// US3, R3, R13: a camera that cannot lock: disabled, with the explanation.
    func testUnsupportedCameraExplainsTheLimit() {
        launchWithCamera(lockable: "none")
        XCTAssertFalse(lockSwitch.isEnabled, "disabled")
        XCTAssertEqual(lockSwitch.label, "Lock white balance")
        XCTAssertEqual(note.label, "This camera can't lock white balance.", "the limit is explained")
        toggleLock()
        XCTAssertEqual(lockSwitch.value as? String, "0", "nothing changes")
    }
}
