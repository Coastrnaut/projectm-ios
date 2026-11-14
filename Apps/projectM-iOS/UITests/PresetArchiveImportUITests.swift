// PresetArchiveImportUITests.swift — FILE-003-T11 (specs/105-file-003-import-dry-run; FILE-003-R1,
// R11, R13; S6): the preset archive preview on the iOS Simulator at the largest accessibility text
// size. The test first imports one preset of its own (`-uitestImportPreset`, PRE-012's path) so the
// library has files to compare. `-uitestPresetArchiveFixture` (DEBUG) then previews a two-preset fixture archive after the trials
// start, as if picked in "Import Preset…" (the system picker is not driven). The sheet shows the
// library's snapshot digest when it opened (`archiveDigestAtPreview`); after Cancel, My Presets shows
// the digest now (`libraryDigest`). Equal digests mean every file under the user preset and
// collection folders is byte-for-byte the same. Launched with the fixed fake entitlement
// (`-uitestUnlocked NO`). Simulator only; never device evidence.
import XCTest

@MainActor
final class PresetArchiveImportUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    /// SHA-256 of nothing: an empty library would make the comparison trivial.
    private let emptyDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    func testCancelLeavesTheLibraryUnchanged() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file003-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let preset = folder.appendingPathComponent("Seeded Lantern.milk")
        let lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=1.031",
                               "per_frame_1=rot = 0.03*sin(time);"]
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: preset)
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestImportPreset", preset.path,
                               "-uitestPresetArchiveFixture", "YES",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac

        // Open My Presets: the preview the fixture opened is presented there.
        app.tapFreshControl("presets")
        let node = app.buttons["node:myPresets"]
        let cancel = app.buttons["archiveCancel"]
        for _ in 0..<4 where !cancel.exists {
            let alert = app.alerts["Import Preset"]   // the seeded import's result, if it needs one
            if alert.exists { alert.buttons["OK"].tap() }
            _ = app.reveal(node)
            if node.exists { node.tap() }
            _ = cancel.appears(within: 5)
        }
        XCTAssertTrue(cancel.exists, "the import preview is shown")
        XCTAssertTrue(cancel.isHittable, "Cancel is reachable at the largest text size")
        let install = app.buttons["archiveInstall"]
        XCTAssertTrue(install.exists && install.isHittable && install.isEnabled, "Install is reachable")
        XCTAssertEqual(install.label, "Install 2")
        let newCount = app.descendants(matching: .any)["archiveCount:new"]
        XCTAssertTrue(newCount.appears(within: 5))
        XCTAssertEqual(newCount.label, "New: 2")

        let probe = app.staticTexts["archiveDigestAtPreview"]
        XCTAssertTrue(probe.appears(within: 5), "the digest at preview is shown (DEBUG)")
        XCTAssertTrue(probe.exists, "the digest at preview is shown (DEBUG)")
        let before = probe.label
        XCTAssertEqual(before.count, 64)
        XCTAssertNotEqual(before, emptyDigest, "the library has files (the seeded preset)")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "import preview, accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)

        cancel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["presetArchivePreview"].disappears(within: 5), "the preview closed")
        let digest = app.staticTexts["libraryDigest"]
        XCTAssertTrue(digest.appears(within: 5), "My Presets shows the digest now (DEBUG)")
        XCTAssertTrue(digest.exists, "My Presets shows the digest now (DEBUG)")
        XCTAssertEqual(digest.label, before, "Cancel left the library byte-for-byte unchanged")
        XCTAssertFalse(app.buttons["preset:Fixture Harbor"].exists)
        XCTAssertTrue(app.buttons["preset:Seeded Lantern"].exists, "the seeded preset is still listed")
        XCTAssertFalse(app.descendants(matching: .any)["pendingPreset:Fixture Harbor"].exists)
        #endif
    }
}
