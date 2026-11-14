// BulkPresetImportUITests.swift — PRE-013-T16 (specs/174-pre-013-bulk-import; S5): a bulk import on
// the iOS Simulator. The test writes a small fixture folder (its own preset text): 1 valid preset, 1
// copy of it, 1 file without a header and 1 text file. `-uitestBulkImportFolder <path>` (DEBUG) imports it as
// if picked in "Import Folder or Archive…" (the system picker itself is not driven). The summary sheet
// is shown in My Presets. Launched with the fixed fake entitlement (`-uitestUnlocked NO`). Simulator
// only (the app reads the test's folder from the host); never device evidence.
import XCTest

@MainActor
final class BulkPresetImportUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func preset(_ tag: Int) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=1.0\(tag)",
         "per_frame_1=rot = 0.0\(tag)*sin(time);", ""].joined(separator: "\n")
    }

    func testImportAFolderShowsTheSummary() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pre013-ui-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("UI Pack", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        for tag in 1...1 { try Data(preset(tag).utf8).write(to: folder.appendingPathComponent("Bulk \(tag).milk")) }
        try Data(preset(1).utf8).write(to: folder.appendingPathComponent("Bulk copy.milk"))
        try Data("zoom=1.5\n".utf8).write(to: folder.appendingPathComponent("Broken.milk"))
        try Data("notes\n".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO",
                               "-uitestBulkImportFolder", folder.path, "-autostart", "inAppPlayback"]
        app.launch()
        XCTAssertTrue(app.staticTexts["scopeLine"].appears(within: 30))   // a ceiling for a loaded Mac

        // Open My Presets: the summary sheet of the finished import is presented there.
        app.tapFreshControl("presets")
        let node = app.buttons["node:myPresets"]
        let summary = app.staticTexts["bulkImportSummary"]
        for _ in 0..<4 where !summary.exists {
            _ = app.reveal(node)
            if node.exists && node.isHittable { node.tap() }
            _ = summary.appears(within: 5)
        }
        XCTAssertTrue(summary.exists, "the summary sheet is shown")
        XCTAssertEqual(summary.label, "Added 1. Skipped 3: 1 duplicate, 1 invalid, 1 not a preset. Failed 0.")
        let added = app.descendants(matching: .any)["bulkCount:added"]
        XCTAssertTrue(added.appears(within: 3))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "bulk import summary"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["bulkImportDone"].tap()
        XCTAssertTrue(summary.disappears(within: 5), "the sheet closed")
        let again = app.buttons["bulkImport"]
        if !again.appears(within: 3) { _ = app.reveal(again) }
        XCTAssertTrue(again.exists, "Import Folder or Archive… is offered again")
        #endif
    }
}
