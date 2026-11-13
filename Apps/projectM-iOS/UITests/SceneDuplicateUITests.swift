// SceneDuplicateUITests.swift — SCN-003-T12 on the iOS Simulator (SCN-003-S5): with the SHOW-001 DEBUG
// seed (`-uitestShowSeed`: five cues over five scenes, standing on cue 1), Settings → Show → cue 2's
// Duplicate Scene inserts cue 3 "Build copy"; Rename Scene… "Build B" shows the scene name under the
// cue; Next then applies cue 2's scene and the copy as two scenes with distinct IDs and the same
// visual. Simulator results are never device evidence. Owner rule 7: under 30 s; UITestWaits' 0.1 s
// polling.
import XCTest

@MainActor
final class SceneDuplicateUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var controls: XCUIElement { app.otherElements["controls"] }

    private func showControls() {
        if !controls.exists { app.otherElements["visualizerTapArea"].firstMatch.tap() }
        XCTAssertTrue(controls.appears(within: 3), "the controls are shown")
    }

    /// Swipes a cue row right (a short drag, so a full swipe never runs Go) and picks one of its
    /// leading actions — the same actions as the context menu, whose live blur over the visualizer
    /// kept XCUITest waiting 60 s for idle. Matched by identifier or by its short or VoiceOver title.
    private func swipeAction(_ row: XCUIElement, id: String, titles: [String]) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let predicate = NSPredicate(format: "identifier == %@ OR label IN %@", id, titles)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.appears(within: 3), "\(id) is offered")
        button.tap()
    }

    func testDuplicateAndRenameACueSceneThenStepThroughBoth() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-autostart", "inAppPlayback"]
            + Self.noStore
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(1))|circularSpectrum" }, "seed on cue 1")

        showControls()
        app.buttons["settings"].tap()
        let link = app.buttons["showEditorLink"]
        XCTAssertTrue(app.reveal(link), "the Show row is reachable")
        link.tap()

        // Duplicate Scene on cue 2 ("Build"): cue 3 "Build copy", six cues.
        let second = app.descendants(matching: .any)["showCue2"]
        XCTAssertTrue(second.appears(within: 5))
        swipeAction(second, id: "showDuplicateScene", titles: ["Duplicate", "Duplicate Scene"])
        let copy = app.descendants(matching: .any)["showCue3"]
        XCTAssertTrue(poll(3) { copy.exists && copy.label == "Build copy" }, "the copy's cue follows its source")
        XCTAssertEqual(copy.value as? String, "Cue 3 of 6")
        XCTAssertEqual(second.label, "Build", "the source cue is unchanged")

        // Rename Scene… "Build B": the cue label stays, the scene name shows.
        swipeAction(copy, id: "showRenameScene", titles: ["Name", "Rename Scene"])
        let alert = app.alerts["Rename Scene"]
        XCTAssertTrue(alert.appears(within: 3), "the Rename Scene alert")
        let field = alert.textFields.firstMatch   // SwiftUI alert fields do not carry their identifier
        XCTAssertTrue(field.appears(within: 2))
        XCTAssertEqual(field.value as? String, "Build copy", "prefilled with the scene name")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14) + "Build B")
        alert.buttons["Rename"].tap()
        XCTAssertTrue(poll(3) { (copy.value as? String) == "Cue 3 of 6, scene Build B" }, "renamed: \(copy.value ?? "nil")")
        XCTAssertEqual(copy.label, "Build copy", "the cue label is not the scene name")
        XCTAssertEqual(second.value as? String, "Cue 2 of 6", "the original scene keeps its name")

        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to Settings
        app.navigationBars["Settings"].buttons["Done"].tap()

        // Next: cue 2 shows the original scene, cue 3 the copy — distinct IDs, the same visual.
        let next = app.buttons["showNextCue"]
        showControls()
        next.tap()
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(2))|linearSpectrum" }, "cue 2: \(applied ?? "nil")")
        showControls()
        next.tap()
        XCTAssertTrue(poll(3) { self.applied?.hasSuffix("|linearSpectrum") == true && self.applied?.hasPrefix(Self.sceneID(2)) == false },
                      "cue 3 applies the copy: \(applied ?? "nil")")
        let copyID = String(applied?.split(separator: "|").first ?? "")
        XCTAssertNotEqual(copyID, "none")
        XCTAssertEqual(copyID.count, 36, "a scene ID")
        XCTAssertFalse((1...5).map(Self.sceneID).contains(copyID), "distinct from every seeded scene")
        XCTAssertTrue(poll(2) { (self.app.staticTexts["showCueStatus"].value as? String) == "Cue 3 of 6, Build copy" })
    }
}
