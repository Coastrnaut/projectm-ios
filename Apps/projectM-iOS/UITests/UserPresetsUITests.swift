// PRE-012-T16, T21, T25: importing presets on the iOS Simulator with the real engine
// (specs/008-pre-012-preset-import-validation; PRE-012-S1, S3, S5). The test writes preset files
// (its own text, no third-party preset); the app imports one through `-uitestImportPreset <path>`,
// the same code path as the Files picker's result (the system picker itself is not driven here).
// Launched with the fixed fake entitlement (`-uitestUnlocked NO`, no StoreKit). Simulator only (the
// app reads the test's file from the host); never device evidence (Constitution X).
// Shortened 2026-11-13 under owner rule 7: `-autostart inAppPlayback` replaces the notice and chooser
// taps, waits poll every 0.1 s (UITestWaits.swift), and held drags (`app.reveal`) replace flinging
// swipes. testImportPlayStepAndRelaunch is split in two (its US4 information checks moved to
// testImportedPresetShowsWhatWasRecorded). Every assertion is unchanged.
import XCTest

@MainActor
final class UserPresetsUITests: XCTestCase {
    private lazy var app = XCUIApplication()
    private var folder: URL!

    nonisolated override func setUp() {
        continueAfterFailure = false
    }

    private func write(_ lines: [String], named name: String) throws -> URL {
        if folder == nil {
            folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pre012-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let url = folder.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    private func presetLines(perFrame: String = "rot = 0.02*sin(time*0.3) + 0.01*bass;") -> [String] {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "PSVERSION_WARP=2", "PSVERSION_COMP=2", "[preset00]",
         "// License: CC-BY 4.0, Example Author",
         "fRating=3.000000", "fDecay=0.960000", "zoom=1.010000", "rot=0.010000", "nWaveMode=2", "fWaveAlpha=1.0", "fWaveScale=1.5",
         "wave_r=0.6", "wave_g=0.6", "wave_b=0.9",
         "per_frame_1=wave_r = 0.5 + 0.5*sin(time*1.1);", "per_frame_2=\(perFrame)",
         "per_pixel_1=zoom = zoom + 0.02*sin(rad*6 + time);",
         "comp_1=`shader_body", "comp_2=`{",
         "comp_3=`ret = tex2D(sampler_main, uv).xyz*0.9 + 0.1*tex2D(sampler_mytexture, uv).xyz;", "comp_4=`}"]
    }

    private func start(reset: Bool, importing file: URL? = nil) {
        XCUIDevice.shared.orientation = .portrait
        // `-autostart inAppPlayback` (Debug) starts the reference track as the chooser's row does.
        app.launchArguments = (reset ? ["-uitestResetNotice"] : []) + ["-uitestDiagnostics", "-uitestUnlocked", "NO",
                                                                       "-autostart", "inAppPlayback"]
            + (file.map { ["-uitestImportPreset", $0.path] } ?? [])
        app.launch()
        XCTAssertTrue(scopeLine.appears(within: 15))
    }

    private var scopeLine: XCUIElement { app.staticTexts["scopeLine"] }
    private var current: XCUIElement { app.staticTexts["currentPreset"] }

    /// Taps a control of the overlay. The controls hide by themselves after 5 s, and a tap on the
    /// picture toggles them, so a tap that lands just as they hide is retried.
    private func tapControl(_ id: String) {
        app.tapFreshControl(id)
    }

    private func open(_ id: String) {
        let element = app.buttons[id]
        // Held drags only when needed: a flinging swipe waits seconds for the list to settle.
        if !(element.appears(within: 2) && element.isHittable) { app.reveal(element) }
        XCTAssertTrue(element.appears(within: 3), id)
        element.tap()
    }

    private func openMyPresets() {
        tapControl("presets")
        XCTAssertTrue(app.buttons["node:included"].appears(within: 10), "library home")
        // At the largest text sizes the row can sit half under the bottom edge: scroll and retry.
        for _ in 0..<3 {
            open("node:myPresets")
            // My Presets is open when its Import button is there, or the import result's alert covers it.
            if poll(3, { self.app.buttons["importPreset"].exists || self.app.alerts["Import Preset"].exists }) { return }
            app.reveal(app.buttons["node:myPresets"])
        }
        XCTAssertTrue(poll(5) { self.app.buttons["importPreset"].exists || self.app.alerts["Import Preset"].exists })
    }

    /// Scrolls until `element` exists (lists build rows only near the screen).
    private func scrollTo(_ element: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.appears(within: 2)
        app.reveal(element)
        XCTAssertTrue(element.exists, what, file: file, line: line)
    }

    private func waitForLabel(_ element: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        if !poll(8, { element.exists && element.label == text }) {
            XCTFail("expected “\(text)”, found “\(element.exists ? element.label : "<missing>")”", file: file, line: line)
        }
    }

    /// Keeps a screenshot with the test result (looked at for PRE-012-T27, also at the largest text size).
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The "Import Preset" alert's message; dismisses it.
    private func importAlertMessage() -> String {
        let alert = app.alerts["Import Preset"]
        XCTAssertTrue(alert.appears(within: 15), "the import result is shown")
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).first { $0 != "Import Preset" } ?? ""
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.disappears(within: 5))
        return message
    }

    /// Imports the valid preset and opens My Presets; returns its row (S5: listed within 5 s).
    private func importSunrise() throws -> XCUIElement {
        let file = try write(presetLines(), named: "Example Author - Sunrise.milk")
        start(reset: true, importing: file)
        let builtIn = current.label
        XCTAssertNotEqual(builtIn, "Sunrise", "importing does not switch the picture")
        openMyPresets()
        let row = app.buttons["preset:Sunrise"]
        XCTAssertTrue(row.appears(within: 5), "S5: listed within 5 s")
        XCTAssertEqual(importAlertMessage(), "Added “Sunrise” to My Presets with 1 warning. See its information for details.")
        XCTAssertEqual(row.label, "Sunrise, by Example Author")
        return row
    }

    // Owner rule 7 (2026-11-13): the former single test (35 s after the faster waits) is split in
    // two. testImportedPresetShowsWhatWasRecorded keeps the US4 information checks; both tests
    // import, list and check the import message and row label (S5).

    /// S5, US4: a valid preset is imported, tried by the real engine, listed, and shows what was
    /// recorded about it.
    func testImportedPresetShowsWhatWasRecorded() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        let row = try importSunrise()
        keepScreenshot("my presets")

        // US4: what the app recorded.
        row.swipeLeft()
        let info = app.buttons["userPresetInfo"]
        XCTAssertTrue(info.appears(within: 5))
        info.tap()
        XCTAssertTrue(app.staticTexts["Preset Information"].appears(within: 5) || app.navigationBars["Preset Information"].exists)
        keepScreenshot("preset information")
        scrollTo(app.staticTexts["presetRights"], "the rights sentence")
        XCTAssertEqual(app.staticTexts["presetRights"].label, "Imported by you. projectM-iOS has not verified any rights to this preset.")
        let license = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '// License: CC-BY 4.0, Example Author'")).firstMatch
        scrollTo(license, "the license line found in the file is shown verbatim")
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'mytexture'")).firstMatch
        scrollTo(warning, "the missing texture is listed")
        app.navigationBars["Preset Information"].buttons["Done"].tap()
        XCTAssertTrue(row.appears(within: 5))
        try? FileManager.default.removeItem(at: folder)
        #endif
    }

    /// S5, US1: the imported preset plays in its own scope, and is still there after the original
    /// file is deleted and the app is relaunched.
    func testImportPlayStepAndRelaunch() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        let row = try importSunrise()

        // US1: it plays, and My Presets is the scope.
        row.tap()
        waitForLabel(current, "Sunrise")
        waitForLabel(scopeLine, "My Presets · 1")
        tapControl("next")
        waitForLabel(current, "Sunrise")   // one member: Next wraps to it
        tapControl("random")
        waitForLabel(current, "Sunrise")

        // Let it draw for longer than the proving period (PRE-012-R18), then relaunch without the file.
        sleep(5)
        app.terminate()
        try FileManager.default.removeItem(at: folder)
        start(reset: false)
        waitForLabel(current, "Sunrise")   // restored as the last preset
        XCTAssertEqual(scopeLine.label, "My Presets · 1")
        openMyPresets()
        XCTAssertTrue(app.buttons["preset:Sunrise"].appears(within: 5))

        // R24: remove it; the list is empty again and the built-in library is what it was.
        app.buttons["preset:Sunrise"].swipeLeft()
        app.buttons["removeUserPreset"].tap()
        let confirm = app.alerts.buttons["Remove Preset"].firstMatch
        XCTAssertTrue(confirm.appears(within: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["userPresetsEmpty"].appears(within: 5))
        #endif
    }

    /// S1, S3, US2: a binary file fails the static check, a preset with broken equations fails
    /// the real engine's off-screen trial; both end in Quarantine with their reason, neither is
    /// playable, and the picture keeps showing the preset it was showing.
    func testInvalidFilesAreQuarantinedAndThePictureKeepsRunning() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("the app reads the test's file from the host; simulator only")
        #else
        if folder == nil { _ = try write([], named: "placeholder.txt") }
        let photo = folder.appendingPathComponent("photo.milk")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]).write(to: photo)
        start(reset: true, importing: photo)
        let playing = current.label
        XCTAssertFalse(playing.isEmpty)
        openMyPresets()
        XCTAssertEqual(importAlertMessage(),
                       "“photo.milk” was put in Quarantine. This file is not text. A Milkdrop preset is a plain text file.")
        XCTAssertTrue(app.staticTexts["userPresetsEmpty"].exists, "nothing became playable")
        open("quarantineLink")
        XCTAssertTrue(app.staticTexts["quarantineReason:photo.milk"].appears(within: 5))
        XCTAssertEqual(app.staticTexts["quarantineReason:photo.milk"].label, "This file is not text. A Milkdrop preset is a plain text file.")
        app.navigationBars["Quarantine"].buttons["Done"].tap()
        waitForLabel(current, playing)

        // Second launch: a preset that is valid text but whose equations the engine cannot compile.
        app.terminate()
        let broken = try write(presetLines(perFrame: "rot = = 3 +* ;"), named: "Broken Equations.milk")
        start(reset: false, importing: broken)
        waitForLabel(current, playing)
        openMyPresets()
        let message = importAlertMessage()
        XCTAssertTrue(message.hasPrefix("“Broken Equations.milk” was put in Quarantine. The visualizer could not load this preset."), message)
        XCTAssertTrue(message.contains("Could not compile per-frame code"), message)
        XCTAssertFalse(app.buttons["preset:Broken Equations"].exists)
        XCTAssertTrue(app.staticTexts["userPresetsEmpty"].exists)
        open("quarantineLink")
        XCTAssertTrue(app.staticTexts["quarantineReason:Broken Equations.milk"].appears(within: 5))
        keepScreenshot("quarantine")
        scrollTo(app.staticTexts["quarantineReason:photo.milk"], "the first file is still in Quarantine after the relaunch")

        // R24: delete one; the other stays.
        open("deleteQuarantined:photo.milk")
        XCTAssertTrue(app.staticTexts["quarantineReason:photo.milk"].disappears(within: 5))
        XCTAssertTrue(app.staticTexts["quarantineReason:Broken Equations.milk"].exists)
        app.navigationBars["Quarantine"].buttons["Done"].tap()

        // The picture never changed, and Next still plays built-in presets only.
        waitForLabel(current, playing)
        tapControl("next")
        XCTAssertNotEqual(current.label, "Broken Equations")
        try? FileManager.default.removeItem(at: folder)
        #endif
    }
}
