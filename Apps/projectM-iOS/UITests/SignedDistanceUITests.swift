// SignedDistanceUITests.swift — VIS-017-T11 on the iOS Simulator: choosing SDF Shapes in Settings, Quality offered at Medium,
// Bars not offered, choosing High, the visual shown with the quality in its value and the source started once (VIS-017 User
// Story 5; VIS-017-R8, R11; S5). One short test (owner rule 7: under 30 s); persistence across a relaunch is
// SignedDistanceAppTests' unit test. Simulator results are never device evidence (Constitution X).
import XCTest

@MainActor
final class SignedDistanceUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private var shapes: XCUIElement { app.descendants(matching: .any)["signedDistance"].firstMatch }
    private var value: String { shapes.value as? String ?? "" }

    func testChoosingSDFShapesAtHighQuality() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        if !app.buttons["settings"].appears(within: 1) { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["settings"].appears(within: 5))
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        let row = app.buttons["visual.signedDistance"]
        if !row.appears(within: 3) { app.reveal(row) }
        XCTAssertTrue(row.appears(within: 5))
        row.tap()
        let quality = app.segmentedControls["signedDistanceQualityPicker"]
        if !quality.appears(within: 2) { app.reveal(quality) }
        XCTAssertTrue(quality.appears(within: 5), "Quality offered")
        XCTAssertTrue(quality.buttons["Medium"].isSelected, "Medium by default")
        XCTAssertFalse(app.segmentedControls["barsPicker"].exists, "Bars does not apply")
        quality.buttons["High"].tap()
        XCTAssertTrue(quality.buttons["High"].isSelected)
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].disappears(within: 5))
        XCTAssertTrue(shapes.appears(within: 10), "the SDF shapes are shown")
        XCTAssertTrue(poll(10) { self.value.hasPrefix("High quality") }, "value: \(value)")
        XCTAssertFalse(app.descendants(matching: .any)["visualizer"].exists, "projectM's view is gone")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the source was not restarted")
    }
}
