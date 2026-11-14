// PresetArchiveConflictUITests.swift — FILE-004-T09 (specs/111-file-004-import-conflict-resolver;
// FILE-004-R1, R8; S6): one conflict row's choice in the preset archive preview on the iOS Simulator at
// the largest accessibility text size. The test imports "Seeded Lantern" (`-uitestImportPreset`), then
// `-uitestPresetArchiveConflictFixture` (DEBUG) previews a two-preset archive whose first preset has
// that name with another text, as if picked. The row's choice goes Keep both (default) → Skip →
// Replace; the Install button and the row's outcome follow; Cancel leaves the library digest as it
// was. Launched with the fixed fake entitlement. Simulator only; never device evidence.
import XCTest

@MainActor
final class PresetArchiveConflictUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testARowChoiceChangesThePlanAndCancelChangesNothing() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file004-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let preset = folder.appendingPathComponent("Seeded Lantern.milk")
        let lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=1.031",
                               "per_frame_1=rot = 0.03*sin(time);"]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: preset)
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestImportPreset", preset.path,
                               "-uitestPresetArchiveConflictFixture", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac

        // Open My Presets: the preview the fixture opened is presented there.
        app.tapFreshControl("presets")
        let node = app.buttons["node:myPresets"]
        let cancel = app.buttons["archiveCancel"]
        for _ in 0..<4 where !cancel.exists {
            let alert = app.alerts["Import Preset"]
            if alert.exists { alert.buttons["OK"].tap() }
            _ = app.reveal(node)
            if node.exists { node.tap() }
            _ = cancel.appears(within: 5)
        }
        XCTAssertTrue(cancel.exists, "the import preview is shown")
        let install = app.buttons["archiveInstall"]
        XCTAssertEqual(install.label, "Install 2", "Keep both by default")
        let probe = app.staticTexts["archiveDigestAtPreview"]
        XCTAssertTrue(probe.appears(within: 5), "the digest at preview is shown (DEBUG)")
        let before = probe.label

        let skip = app.buttons["archiveChoice:Seeded Lantern:skip"]
        XCTAssertTrue(app.reveal(skip), "the row's choices are reachable at the largest text size")
        skip.tap()
        XCTAssertTrue(poll(5) { install.label == "Install 1" }, "Skip leaves it out: \(install.label)")
        XCTAssertTrue(poll(5) { skip.isSelected }, "Skip is marked selected")

        let replace = app.buttons["archiveChoice:Seeded Lantern:replace"]
        XCTAssertTrue(app.reveal(replace))
        replace.tap()
        XCTAssertTrue(poll(5) { install.label == "Install 2" }, "Replace installs it: \(install.label)")
        let row = app.descendants(matching: .any)["archiveConflict:Seeded Lantern"]
        XCTAssertTrue(poll(5) { row.label.contains("Replaces “Seeded Lantern”") }, "the row says what happens: \(row.label)")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "conflict row, Replace, accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)

        cancel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["presetArchivePreview"].disappears(within: 5), "the preview closed")
        let digest = app.staticTexts["libraryDigest"]
        XCTAssertTrue(digest.appears(within: 5), "My Presets shows the digest now (DEBUG)")
        XCTAssertEqual(digest.label, before, "Cancel left the library byte-for-byte unchanged")
        #endif
    }
}
