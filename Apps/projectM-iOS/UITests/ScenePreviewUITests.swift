// ScenePreviewUITests.swift — SCN-006-T10 on the iOS Simulator (SCN-006-S4, S5; contract P4). With the
// DEBUG show seed (`-uitestShowSeed`: five cues, standing on cue 1, whose look the seed set directly, so
// no picture yet) and the fixture capture (`-uitestScenePreviewFixture`: an instant fixed picture instead
// of the renderer's frame), choosing cue 2 in the switcher captures its preview after the 1 s settle; on
// reopening, row 2 shows the picture and row 3 the placeholder, with row 2's label and value unchanged.
// Simulator results are never device evidence. Owner rule 7: under 30 s.
import XCTest

@MainActor
final class ScenePreviewUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private var applied: String? { app.staticTexts["showAppliedScene"].value as? String }
    private var field: XCUIElement { app.textFields["sceneSwitcherField"] }
    private var card: XCUIElement { app.otherElements["sceneSwitcher"] }
    private func entry(_ n: Int) -> XCUIElement { app.buttons["sceneSwitcherEntry.\(n)"] }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openSwitcher() {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(field.appears(within: 3), "⌘K opens the switcher")
    }

    func testSwitcherRowShowsThePreviewOfAShownScene() {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestShowSeed", "-uitestScenePreviewFixture",
                               "-autostart", "inAppPlayback", "-uitestUnlocked", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].appears(within: 15))
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(1))|circularSpectrum" }, "cue 1: \(applied ?? "nil")")

        openSwitcher()
        XCTAssertTrue(element("scenePreviewPlaceholder:\(Self.sceneID(2))").appears(within: 3), "no preview before cue 2 is shown")
        let label = entry(2).label
        let value = entry(2).value as? String
        entry(2).tap()
        XCTAssertTrue(card.disappears(within: 3))
        XCTAssertTrue(poll(3) { self.applied == "\(Self.sceneID(2))|linearSpectrum" }, "cue 2: \(applied ?? "nil")")

        let picture = element("scenePreview:\(Self.sceneID(2))")
        var shown = false
        for _ in 0..<4 where !shown {   // the settle is 1 s; reopen until the row has its picture
            sleep(1)
            openSwitcher()
            shown = picture.appears(within: 2)
            if !shown { app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []); _ = card.disappears(within: 2) }
        }
        XCTAssertTrue(shown, "row 2 shows its preview")
        XCTAssertTrue(element("scenePreviewPlaceholder:\(Self.sceneID(3))").exists, "row 3 has none yet")
        XCTAssertEqual(entry(2).label, label, "the row's label is unchanged")
        XCTAssertEqual((entry(2).value as? String)?.replacingOccurrences(of: ", current", with: ""), value?.replacingOccurrences(of: ", current", with: ""),
                       "the row's value is unchanged (apart from becoming current)")
    }
}
