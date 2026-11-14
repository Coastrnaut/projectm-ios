// FolderBackupUITests.swift — FILE-006-T13 (FILE-006-S5): Settings › Storage › Backup › Back Up to Folder…
// on the simulator. One launch: a reset library with a seeded fake video and photo (`-uitestMediaSeed`),
// backed up twice into a test folder (`-uitestBackupFolder`, DEBUG: no folder picker). The first backup
// copies the media; the second copies nothing and reports them unchanged. `-uitestStorageSheet` opens
// Storage at launch. Fixed fake entitlement. Simulator only; never device evidence.
import XCTest

@MainActor
final class FolderBackupUITests: XCTestCase {
    private lazy var app = XCUIApplication()

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    func testASecondFolderBackupReportsTheMediaUnchanged() throws {
        XCUIDevice.shared.orientation = .portrait
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("file006-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        app.launchArguments = ["-uitestResetNotice", "-uitestStorageSheet", "-uitestMediaSeed", "-uitestBackupFolder", folder.path] + Self.noStore
        app.launch()
        XCTAssertTrue(app.navigationBars["Storage"].appears(within: 20), "Storage opens at launch")
        let button = app.buttons["folderBackupButton"]
        XCTAssertTrue(app.reveal(button))
        button.tap()
        let message = app.staticTexts["folderBackupMessage"]
        XCTAssertTrue(message.appears(within: 10))
        XCTAssertTrue(poll(10) { message.label.hasPrefix("Backed up to the folder: ") && message.label.contains("2 copied") }, message.label)
        let manifest = folder.appendingPathComponent("projectM Backup/backup-manifest.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "the backup reached the test folder")

        button.tap()
        XCTAssertTrue(poll(10) { message.label.contains("0 copied") }, message.label)
        XCTAssertTrue(message.label.contains("2 unchanged"), message.label)
    }
}
