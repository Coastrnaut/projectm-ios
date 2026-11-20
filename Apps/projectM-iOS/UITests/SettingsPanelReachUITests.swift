// SettingsPanelReachUITests.swift — QA-011 pass 6 D2 regression guard (iPadOS 27.2, 2026-11-19). REC-001's Files
// exporter moved to a host view in VisualizerView's `.background`; at the host's full size that view lay in front of
// the split editor for accessibility ({{0, 32}, {1032, 1324}} on a 13-inch iPad), so no control in the Settings pane
// was hittable and about 20 device UI tests could not reach Settings rows (visual rows, Storage, Camera, OSC). Here
// the pane's rows must be hittable as soon as Settings opens, a tap must choose one, and Storage's link must be
// hittable after the DEBUG jump. iPad only (the split editor; iPhone keeps the sheet). Simulator results are never
// device evidence. Owner rule 7: < 30 s.
import XCTest

@MainActor
final class SettingsPanelReachUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testSplitEditorRowsAreHittableAndStorageIsReachable() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback",
                               "-uitestSettingsJump", "storage"] + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap() }
        if !controls.appears(within: 2) { area.tap() }
        XCTAssertTrue(controls.appears(within: 5), "the controls are shown")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].appears(within: 5))
        guard app.descendants(matching: .any)["splitEditorPane"].firstMatch.appears(within: 3) else {
            throw XCTSkip("compact width: Settings is a sheet, not the split editor")
        }

        let linear = app.buttons["visual.linearSpectrum"].firstMatch
        XCTAssertTrue(linear.appears(within: 3), "the Linear Spectrum row is built")
        XCTAssertTrue(linear.isHittable, "nothing lies in front of the Settings pane (frame \(linear.frame))")
        XCTAssertTrue(app.buttons["visual.circularSpectrum"].firstMatch.isHittable)
        linear.tap()
        XCTAssertTrue(poll(3) { linear.isSelected }, "a tap on a pane row chooses it")

        let jump = app.navigationBars["Settings"].buttons["uitestSettingsJump.storage"].firstMatch
        XCTAssertTrue(jump.appears(within: 3), "the DEBUG jump")
        jump.tap()
        let storage = app.buttons["storageLink"].firstMatch
        XCTAssertTrue(poll(5) { storage.exists && storage.isHittable }, "Storage's link is hittable in the pane")
    }
}
