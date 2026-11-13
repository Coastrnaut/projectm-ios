// PRE-014-T19: exporting presets from My Presets on the iOS Simulator with the real engine
// (specs/012-pre-014-bulk-preset-export; PRE-014-R1, R3, R5, R17). The test writes its own preset
// file; the app imports it through `-uitestImportPreset <path>` (PRE-012's path), and a DEBUG
// build copies the written archive to `-uitestExportPresetTo <path>` so the test can read it. The
// test stops at the system share sheet (it never shares anything). Launched with the fixed fake
// entitlement (`-uitestUnlocked NO`, no StoreKit). Simulator only; never device evidence.
import XCTest

@MainActor
final class UserPresetExportUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL!

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private func makeFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pre014-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        return url
    }

    private func writePreset(named name: String, in folder: URL) throws -> URL {
        let lines = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "PSVERSION_WARP=2", "PSVERSION_COMP=2", "[preset00]",
                     "// License: CC-BY 4.0, Example Author",
                     "fRating=3.000000", "fDecay=0.960000", "zoom=1.010000", "rot=0.010000", "nWaveMode=2", "fWaveAlpha=1.0",
                     "per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.3);", "per_frame_2=rot = 0.02*sin(time*0.4);",
                     "per_pixel_1=zoom = zoom + 0.02*sin(rad*5 + time);"]
        let url = folder.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    private func start(importing file: URL, exportTo target: URL, extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO",
                               "-uitestImportPreset", file.path, "-uitestExportPresetTo", target.path] + extra
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        let inApp = app.buttons["In-App Playback"]
        if !inApp.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(inApp.waitForExistence(timeout: 5))
        inApp.tap()
        XCTAssertTrue(app.staticTexts["scopeLine"].waitForExistence(timeout: 10))
    }

    /// The overlay's controls hide after 5 s; a tap on the picture shows them again.
    private func tapControl(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<3 {
            if button.waitForExistence(timeout: 2) { break }
            app.otherElements["visualizerTapArea"].firstMatch.tap()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 3), id)
        button.tap()
    }

    private func dismissImportAlert() {
        let alert = app.alerts["Import Preset"]
        if alert.waitForExistence(timeout: 3) { alert.buttons["OK"].tap() }
    }

    private func openMyPresets() {
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].waitForExistence(timeout: 10), "library home")
        let node = app.buttons["node:myPresets"]
        // At the largest text sizes the row can sit half under the bottom edge, where a tap lands
        // on the home indicator: scroll and retry until My Presets is open.
        for _ in 0..<4 {
            for _ in 0..<6 where !(node.exists && node.isHittable) { app.swipeUp() }
            if node.exists { node.tap() }
            dismissImportAlert()
            if app.buttons["exportPresets"].waitForExistence(timeout: 5) { return }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["exportPresets"].exists, "My Presets offers Export")
    }

    /// Waits until the imported preset was tried and is listed as playable.
    private func waitForPlayable(_ name: String) {
        let row = app.buttons["preset:\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "\(name) is playable")
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The system share sheet is on screen (its layout differs between iOS versions).
    private var shareSheetShown: Bool {
        let candidates: [XCUIElement] = [app.otherElements["ActivityListView"], app.navigationBars["UIActivityContentView"],
                                         app.buttons["Save to Files"], app.cells["Save to Files"], app.staticTexts["Save to Files"],
                                         app.otherElements["UIActivityContentView"]]
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if candidates.contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    func testExportSelectedPresetsToAnArchive() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads and writes the test's files on the host; simulator only")
        #else
        let folder = try makeFolder()
        let preset = try writePreset(named: "Example Author - Harbor Lights.milk", in: folder)
        let target = folder.appendingPathComponent("exported.zip")
        start(importing: preset, exportTo: target)
        openMyPresets()
        waitForPlayable("Harbor Lights")

        app.buttons["exportPresets"].tap()
        let row = app.buttons["exportRow:Harbor Lights"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the exportable preset is listed")
        XCTAssertEqual(row.label, "Harbor Lights, selected", "every exportable preset starts selected")
        let confirm = app.buttons["exportConfirm"]
        XCTAssertTrue(confirm.isEnabled)

        app.buttons["exportSelectNone"].tap()
        XCTAssertEqual(row.label, "Harbor Lights, not selected")
        XCTAssertFalse(confirm.isEnabled, "nothing selected: Export is disabled")
        app.buttons["exportSelectAll"].tap()
        XCTAssertEqual(row.label, "Harbor Lights, selected")
        XCTAssertTrue(confirm.isEnabled)
        keepScreenshot("export sheet")

        confirm.tap()
        XCTAssertTrue(shareSheetShown, "the system share sheet opens with the archive")
        keepScreenshot("share sheet")
        let summary = app.descendants(matching: .any)["exportSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5) || summary.exists, "the summary is shown")

        // The archive the app wrote (copied by the DEBUG hook): a stored ZIP with the manifest and
        // the preset's text in plain bytes.
        let data = try Data(contentsOf: target)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("manifest.json"))
        XCTAssertTrue(text.contains("org.projectmios.user-presets"))
        XCTAssertTrue(text.contains("\"name\":\"Harbor Lights\""))
        XCTAssertTrue(text.contains("License: CC-BY 4.0, Example Author"))
        XCTAssertTrue(text.contains("per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.3);"))
        #endif
    }

    /// PRE-014-R17: at the largest accessibility text size the sheet's row and Export button are
    /// still reachable.
    func testExportSheetAtTheLargestTextSize() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
        #else
        let folder = try makeFolder()
        let preset = try writePreset(named: "Large Type.milk", in: folder)
        start(importing: preset, exportTo: folder.appendingPathComponent("large.zip"),
              extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openMyPresets()
        waitForPlayable("Large Type")
        let export = app.buttons["exportPresets"]
        let exportable = NSPredicate(format: "isEnabled == true")
        let enabled = expectation(for: exportable, evaluatedWith: export)
        wait(for: [enabled], timeout: 20)
        export.tap()
        let row = app.buttons["exportRow:Large Type"]
        // Lists build rows only near the screen: scroll until the row is there.
        for _ in 0..<8 where !(row.waitForExistence(timeout: 2) && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertEqual(row.label, "Large Type, not selected")
        XCTAssertTrue(app.buttons["exportConfirm"].isHittable)
        keepScreenshot("export sheet, accessibility XXXL")
        #endif
    }
}
