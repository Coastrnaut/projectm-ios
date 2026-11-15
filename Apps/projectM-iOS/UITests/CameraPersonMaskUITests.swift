// CameraPersonMaskUITests.swift — CAM-008-T15 on the iOS Simulator with the stand-in camera and a fixture
// segmenter (`-uitestCamera granted -uitestPersonSegmenter fixture|unsupported`, DEBUG only): the Person
// mask picker is usable where segmentation is available and disabled with its explanation where it is
// not (CAM-008-R1, R5, R8). Simulator results are never device evidence; real masking is CAM-008-T16 on D1.
import XCTest

@MainActor
final class CameraPersonMaskUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var positionPicker: XCUIElement { app.segmentedControls["cameraPositionPicker"] }
    private var maskPicker: XCUIElement { app.segmentedControls["cameraPersonMaskPicker"] }
    private var note: XCUIElement { app.staticTexts["cameraPersonMaskNote"] }

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
    }

    /// Launches with the stand-in camera, chooses Camera and reveals the Person mask row.
    private func launchWithCamera(segmenter: String) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestCamera", "granted", "-uitestPersonSegmenter", segmenter] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        showControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.visualRow("Camera")
        XCTAssertTrue(app.reveal(row), "the Camera visual row")
        row.tap()
        XCTAssertTrue(app.reveal(positionPicker), "the Camera section appears")
        XCTAssertTrue(app.reveal(maskPicker), "the Person mask row is shown")
    }

    /// US1, R1, R8: available: Off by default, Person chosen without restarting the source.
    func testAvailableSegmentationOffersTheChoice() {
        launchWithCamera(segmenter: "fixture")
        XCTAssertTrue(maskPicker.isEnabled, "enabled")
        XCTAssertFalse(note.exists, "no note while the mask can be drawn")
        XCTAssertTrue(maskPicker.buttons["Off"].isSelected, "Off by default")
        maskPicker.buttons["Person"].tap()
        XCTAssertTrue(poll(3) { self.maskPicker.buttons["Person"].isSelected }, "Person chosen")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }

    /// US2, R5, R8: unsupported: disabled, with the explanation.
    func testUnsupportedSegmentationExplainsTheLimit() {
        launchWithCamera(segmenter: "unsupported")
        XCTAssertFalse(maskPicker.isEnabled, "disabled")
        XCTAssertEqual(note.label, "Person mask isn't supported on this device.", "the limit is explained")
    }
}
