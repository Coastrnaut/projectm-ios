// LibraryBackupUITests.swift — FILE-005-T16 (FILE-005-S6): Settings › Storage › Backup on the simulator.
// Launch 1 seeds a show (`-uitestShowSeed`) and an OSC port (argument domain), backs the library up to
// a test folder (`-uitestBackupTo`, DEBUG: no file mover) and reads the DEBUG records probe. Launch 2
// starts from a reset library, previews that file through Restore from Backup… (`-uitestRestoreFrom`,
// DEBUG: no picker) and taps Restore at Next Launch. Launch 3 starts from a reset library again: the
// restore runs before anything loads, the result is shown, and the probe (show, scenes and the port)
// equals launch 1's. `-uitestStorageSheet` opens
// Storage at launch (no audio, no scrolling through Settings). Fixed fake entitlement. Simulator only;
// never device evidence.
import XCTest

@MainActor
final class LibraryBackupUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) {
        app.launchArguments = ["-uitestResetNotice", "-uitestStorageSheet"] + Self.noStore + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 20), "Storage opens at launch")
    }

    private func probe() -> String {
        let element = app.staticTexts["libraryRecordsProbe"]
        XCTAssertTrue(app.reveal(element))
        XCTAssertTrue(poll(10) { element.label.contains("port") }, element.label)
        return element.label
    }

    func testBackUpThenRestoreAcrossARelaunchBringsTheRecordsBack() throws {
        XCUIDevice.shared.orientation = .portrait
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file005-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.pmbackup")

        // Launch 1: a seeded library, backed up.
        launch(["-uitestShowSeed", "-settings.osc.port", "9123", "-uitestBackupTo", file.path])
        let backUp = app.buttons["libraryBackupButton"]
        XCTAssertTrue(app.reveal(backUp))
        let original = probe()
        XCTAssertTrue(original.hasPrefix("6 "), "the show and its five scenes: \(original)")
        XCTAssertTrue(original.contains("9123"), original)
        backUp.tap()
        let message = app.staticTexts["libraryBackupMessage"]
        XCTAssertTrue(message.appears(within: 10))
        XCTAssertTrue(poll(10) { message.label.hasPrefix("Backed up 6 scenes") }, message.label)
        XCTAssertTrue(poll(5) { FileManager.default.fileExists(atPath: file.path) }, "the backup reached the test folder")

        // Launch 2: a reset library; preview the file and request its restore.
        app.terminate()
        launch(["-uitestRestoreFrom", file.path])
        let restore = app.buttons["libraryRestoreButton"]
        XCTAssertTrue(app.reveal(restore))
        restore.tap()
        let confirm = app.buttons["libraryRestoreConfirm"]
        XCTAssertTrue(confirm.appears(within: 10), "the preview opens")
        XCTAssertTrue(app.staticTexts["Scenes"].exists)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["libraryRestorePending"].appears(within: 5))

        // Launch 3: a reset library again; the restore runs at launch.
        app.terminate()
        launch([])
        let result = app.staticTexts["libraryBackupMessage"]
        XCTAssertTrue(app.reveal(result))
        XCTAssertTrue(result.label.hasPrefix("Restored from backup: 6 scenes"), result.label)
        XCTAssertEqual(probe(), original, "the restored records equal the backed-up ones")
        XCTAssertFalse(app.staticTexts["libraryRestorePending"].exists)
    }
}
