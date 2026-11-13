// SceneRepairUITests.swift — SCN-012-T10 on the iOS Simulator (SCN-012-S4): with the DEBUG seed
// (`-uitestShowRepairSeed`: "Opening" applied, "Broken" with a photo no store holds and a mapping to an
// unknown parameter, "Future" saved by format version 2), Next to "Broken" shows the repair report
// with Missing media and Invalid mappings and leaves the output on cue 1; Open with repairs
// applies the cue (the photo layer dropped, so the Circular Spectrum runs). Next to "Future" shows
// "Cannot open" with only Close, and Close leaves the output unchanged. Simulator results are never
// device evidence. Owner rule 7: under 30 s; UITestWaits' 0.1 s polling.
import XCTest

@MainActor
final class SceneRepairUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var controls: XCUIElement { app.otherElements["controls"] }
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    private func showControls() {
        if !controls.exists { area.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    func testABrokenCueShowsTheRepairReportAndOpensRepairedAndANewerSceneCannotOpen() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowRepairSeed", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        let opening = "\(Self.sceneID(1))|circularSpectrum"
        XCTAssertTrue(poll(3) { self.applied == opening }, "cue 1 applied: \(applied ?? "nil")")

        // Cue 2: the report, before anything is applied.
        showControls()
        app.buttons["showNextCue"].tap()
        let status = app.staticTexts["sceneRepairStatus"]
        XCTAssertTrue(status.appears(within: 5), "the repair report appears")
        XCTAssertEqual(status.label, "Opens with problems")
        let media = app.staticTexts["sceneRepairGroup.missingMedia"]
        let mappings = app.staticTexts["sceneRepairGroup.invalidMappings"]
        XCTAssertTrue(media.exists, "Missing media section")
        XCTAssertTrue(mappings.exists, "Invalid mappings section")
        XCTAssertTrue(app.buttons["sceneRepairOpenAsIs"].exists, "a scene without errors can open as is")
        XCTAssertEqual(applied, opening, "nothing is applied before the user chooses")
        app.buttons["sceneRepairOpenRepaired"].tap()
        XCTAssertTrue(status.disappears(within: 5), "the report closes")
        let repaired = "\(Self.sceneID(2))|circularSpectrum"
        XCTAssertTrue(poll(3) { self.applied == repaired }, "cue 2 applied with repairs: \(applied ?? "nil")")

        // Cue 3: a newer version cannot open; Close leaves the output on cue 2.
        showControls()
        app.buttons["showNextCue"].tap()
        XCTAssertTrue(status.appears(within: 5), "the report appears for the newer scene")
        XCTAssertEqual(status.label, "Cannot open")
        XCTAssertTrue(app.staticTexts["sceneRepairGroup.unsupportedVersion"].exists, "Unsupported version section")
        XCTAssertFalse(app.buttons["sceneRepairOpenRepaired"].exists)
        XCTAssertFalse(app.buttons["sceneRepairOpenAsIs"].exists)
        let close = app.buttons["sceneRepairCancel"]
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertTrue(status.disappears(within: 5))
        XCTAssertEqual(applied, repaired, "the output is unchanged")
        XCTAssertEqual(app.staticTexts["sourceStarts"].value as? String, "1", "the audio source was never restarted")
    }
}
