// LibraryCheckUITests.swift — PRE-018-T14 (specs/194-pre-018-integrity-scanner; S6): the library check on
// the iOS Simulator. `-uitestBrokenLibrary` (DEBUG, with `-uitestResetNotice`) seeds one issue of every
// kind and every reference store. My Presets › Check Library › Check Library lists them; Fix All Safe
// removes the five broken references and the three issues that need the user stay. Launched with the fixed
// fake entitlement (`-uitestUnlocked NO`). Simulator only; never device evidence. Budget: under 30 s.
import XCTest

@MainActor
final class LibraryCheckUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testCheckLibraryListsTheBrokenSeedAndFixAllSafeRemovesTheBrokenReferences() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestBrokenLibrary",
                               "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac

        app.tapFreshControl("presets")
        let node = app.buttons["node:myPresets"]
        _ = app.reveal(node)
        node.tap()
        let link = app.buttons["libraryCheckLink"]
        XCTAssertTrue(link.appears(within: 5) || app.reveal(link), "Check Library is offered in My Presets")
        _ = app.reveal(link)
        link.tap()

        let result = app.descendants(matching: .any)["libraryCheckResult"]
        XCTAssertTrue(result.appears(within: 5))
        XCTAssertEqual(result.label, "Not checked yet.")
        app.buttons["checkLibrary"].tap()
        XCTAssertTrue(waitFor(result, label: "Found 8 problems."), result.label)
        // The first section is on screen without scrolling; the count covers the rest (owner rule 7).
        XCTAssertTrue(app.descendants(matching: .any)["integrityIssue:missingTexture:user/00000000-0000-4000-8000-000000000010"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "library check issues"
        attachment.lifetime = .keepAlways
        add(attachment)

        let fixAll = app.buttons["fixAllSafe"]
        if !fixAll.isHittable { _ = app.reveal(fixAll, down: true) }
        fixAll.tap()
        let fixed = "Removed 5 broken references. Found 3 problems."
        XCTAssertTrue(waitFor(result, label: fixed), result.label)
        XCTAssertFalse(app.buttons["fixAllSafe"].exists, "no broken reference is left")
        let missingFile = app.descendants(matching: .any)["integrityIssue:missingFile:user/00000000-0000-4000-8000-000000000011"]
        XCTAssertTrue(missingFile.exists || app.reveal(missingFile), "a missing file stays until the user acts")
        #endif
    }

    /// Polls a combined element's label (the result line holds a progress view while checking).
    private func waitFor(_ element: XCUIElement, label: String, within timeout: TimeInterval = 10) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if element.exists, element.label.contains(label) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }
}
