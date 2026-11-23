// B07FilesDeviceTests.swift — QA-011 Batch 5 (files and presets): PRE-007, PRE-012, PRE-014, PRE-001, FILE-001,
// FILE-009 and FILE-010 on the device, with the real Files picker and share sheet (Batch 1's SystemUI.swift).
//
// Fixtures: `python3 scripts/install_test_fixtures.py --device <D> --media` (preset-small.milk, preset-512k.milk,
// not-a-preset.milk, photo-small.jpg, video-h264-1080p.mp4 …). The Debug device-test host shows the app's Documents in
// Files as On My iPhone/iPad › projectM, so pickers read the fixtures and Save to Files writes back into Documents,
// where the Mac reads the result: `scripts/mac_driver/files.py` (`files.pull`, `files.push`) through
// `python3 scripts/mac_device_driver.py follow --log <log> --device <D>` beside the run. A test that needs the Mac
// skips with the command when the run was started without it (`TEST_RUNNER_MAC_DRIVER=1`).
//
// Two-step tests run as separate xcodebuild invocations in name order (docs/autotester.md, Batch 5):
// * PRE-007: `testPRE007_A_…` seeds and reorders; the Mac installs the same build over the app
//   (`xcrun devicectl device install app …`, the update path); `testPRE007_B_…` checks the collections.
// * FILE-001: `testFILE001_A_ExportSceneArchive` on D1 (the Mac pulls the archive), then
//   `testFILE001_B_ImportSceneArchive` on D3 (the Mac pushes it into D3's Documents first).
// Person-only parts: VoiceOver speaking the Move Up / Move Down actions and a VoiceOver pass over My Presets and
// Quarantine (the tests use the same actions from the context menu and run accessibility audits); iCloud Drive;
// "offline" import (Airplane Mode is a USB-cable step, not required, owner ruling 2026-11-18).
import UIKit
import XCTest

@MainActor
final class B07FilesDeviceTests: B07Case {
    // MARK: Preset browser

    func openBrowser() {
        let opened = { self.app.buttons["node:myPresets"].exists || self.app.buttons["node:included"].exists }
        // The controls' 5 s auto-hide can run out between finding Presets and the tap: FILE-010 on D2 (pass 9,
        // 2026-11-19) closed Settings 4.7 s after showing the bar, and the bar faded under the tap ("Activation point
        // invalid", then no Presets button). The tap goes to the button's last frame (a coordinate tap never fails on
        // a vanished element; a miss only shows the bar again), and a missed open is retried once with a fresh bar.
        for attempt in 0..<2 where !opened() {
            showControlsBar()
            let presets = app.buttons["presets"].firstMatch
            XCTAssertTrue(wait(5) { presets.exists }, "the Presets control")
            guard presets.exists else { continue }
            let frame = presets.frame
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            _ = wait(attempt == 0 ? 5 : 10, opened)
        }
        XCTAssertTrue(opened(), "the preset browser opens")
    }

    func closeBrowser() {
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.buttons["node:included"].exists && !self.app.buttons["importPreset"].exists }
    }

    /// Opens the browser row `node:<id>` and waits until the list it opens shows (the row gone, or a navigation bar
    /// named like the row). QA-011 D1 rerun (2026-11-23, PRE-012-T31, PRE-014-T25): on the iPhone My Presets is the
    /// home's eighth row and sat under the floating search field (row 756-808 pt, field from 786 pt); the tap went to
    /// the field, the home stayed (failure dump) and Import Preset… never appeared. `scrollTo` now requires the row
    /// clear of that chrome, and a tap that left the row in place is repeated (as `openListRow`).
    func openNode(_ id: String, settle: Double = 0.8) {
        let node = app.buttons["node:\(id)"].firstMatch
        _ = wait(3) { node.exists }   // a push or pop animation still running
        XCTAssertTrue(scrollTo(node), "node:\(id) is listed")
        let title = node.exists ? node.label.components(separatedBy: ",").first ?? "" : ""
        let opened = { !node.exists || (!title.isEmpty && self.app.navigationBars[title].exists) }
        for attempt in 0..<3 {
            if attempt > 0 {
                print("DEVICE-ACCEPT-NOTE node:\(id) is still listed after tap \(attempt); tapping again")
                _ = scrollTo(node, swipes: 3)
            }
            guard node.exists else { break }
            node.tap()
            if wait(3, opened) { break }
        }
        XCTAssertTrue(opened(), "node:\(id) opens")
        pause(settle)
    }

    /// Rows whose identifier starts with `prefix`, top to bottom (names without the prefix).
    func rows(_ prefix: String = "preset:") -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { String($0.identifier.dropFirst(prefix.count)) }
    }

    /// Opens a row's context menu and taps `item` ("Move Up", "Add to Collection…", "Duplicate to My Presets").
    func contextMenu(_ row: XCUIElement, _ item: String, hold: Double = 1.0, settle: Double = 0.8) {
        row.press(forDuration: hold)
        var button = app.buttons[item].firstMatch
        if !wait(3, { button.exists }) {
            button = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", item)).firstMatch
        }
        XCTAssertTrue(wait(3) { button.exists }, "the menu offers \(item)")
        if button.exists { button.tap() }
        pause(settle)
    }

    /// The alert's title and message.
    func alertText(_ alert: XCUIElement) -> String {
        ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    /// Duplicates the first preset of the open folder into My Presets; returns its name.
    func duplicateFirstPreset() -> String? {
        if rows().isEmpty, let folder = rows("node:").first { openNode(folder) }   // a pack can open on folders
        guard let name = rows().first else { XCTFail("no preset row"); return nil }
        contextMenu(app.buttons["preset:\(name)"].firstMatch, "duplicatePreset", hold: 1.2)
        let alert = app.alerts["Duplicate to My Presets"].firstMatch
        if wait(10, { alert.exists }) {
            print("B07 duplicate: \(alertText(alert))")
            alert.buttons.firstMatch.tap()
        }
        return name
    }

    /// My Presets › Import Preset… › Files › `file`; returns the result and seconds from Open to the result.
    ///
    /// The app shows the "Import Preset" alert only for an outcome that needs attention (warnings, waiting, Quarantine,
    /// refused, a duplicate); a clean add is only announced and its row appears (PRE-012-R28, `needsAlert`). QA-011
    /// pass 5 (D3, 2026-11-19): preset-small.milk and preset-512k.milk were added cleanly (their rows appeared, and
    /// PRE-014's export listed both) while the test waited 30 s for an alert that never comes, then failed "no Import
    /// Preset alert" and PRE-012's 15 s timing. The result is now the alert, or the new playable row
    /// (`preset:<name>`, not there before the pick) reported as "Added … (announced, no alert)".
    func importPreset(_ file: String) -> (text: String, seconds: Double) {
        let button = app.buttons["importPreset"].firstMatch
        XCTAssertTrue(wait(5) { button.exists }, "Import Preset… (My Presets)")
        let name = (file as NSString).deletingPathExtension
        let row = app.buttons["preset:\(name)"].firstMatch
        let listedBefore = row.exists   // a re-run: the duplicate gets an alert ("already in My Presets")
        button.tap()
        XCTAssertTrue(ui.filesPick(name: file), "Files: \(file)")
        let picked = Date()
        let alert = app.alerts["Import Preset"].firstMatch
        let progress = element("importProgress")
        let done = wait(30) { alert.exists || (!listedBefore && row.exists && !progress.exists) }
        let seconds = Date().timeIntervalSince(picked)
        XCTAssertTrue(done, "the import result for \(file)")
        // Reading a missing alert's label fails the test at once and ended the run (PRE-012, PRE-014 on D2, 2026-11-19).
        guard alert.exists else {
            return (row.exists && !listedBefore ? "Added “\(name)” to My Presets (announced, no alert)" : "no import result", seconds)
        }
        let text = alertText(alert)
        if alert.exists { alert.buttons.firstMatch.tap() }
        pause(0.5)
        return (text, seconds)
    }

    // MARK: Files and the Mac

    /// Save to Files from a share sheet the app shows: the activity, then On My iPhone/iPad › projectM, Replace if asked.
    func saveSharedFileToDocuments(_ task: String) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(wait(5) { self.app.popovers.count > 0 }, "\(task): the iPad share sheet is a popover")
            report(task, "share sheet", ["popover": app.popovers.count > 0 ? 1 : 0])
            revealShareActivity("Save to Files")
        }
        XCTAssertTrue(ui.shareSheet("Save to Files"), "\(task): Save to Files")
        XCTAssertTrue(ui.filesSave(), "\(task): saved in On My … › projectM")
        let replace = app.buttons["Replace"].firstMatch
        if wait(3, { replace.exists }) { replace.tap() }
        pause(1)
    }

    /// Scrolls the share popover until `activity` is hittable. QA-011 pass 5 (D3, 2026-11-19): the popover was squeezed
    /// below the Export Presets sheet, showing only the file and a contact row; Save to Files sat below the screen
    /// (y 1274 of 1180) and could not be tapped. The app now anchors its share popover at the sheet's top
    /// (`ShareSheetPresenter.popoverAnchor`); this keeps the test working wherever the popover lands.
    func revealShareActivity(_ activity: String) {
        let target = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", activity)).firstMatch
        guard wait(5, { target.exists }) else { return }
        let popover = app.popovers.firstMatch
        for _ in 0..<4 where !target.isHittable && popover.exists {
            let scroller = popover.collectionViews.firstMatch.exists ? popover.collectionViews.firstMatch : popover
            scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.1, thenDragTo: scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            pause(0.5)
        }
        if !target.isHittable { print("DEVICE-ACCEPT-NOTE share sheet: \(activity) is not hittable at \(target.frame)") }
    }

    func requireMac(_ task: String) throws {
        guard MacDriver.isFollowing else {
            throw XCTSkip("\(task) needs the Mac: python3 scripts/mac_device_driver.py follow --log <log> --device <D> & and "
                          + "TEST_RUNNER_MAC_DRIVER=1 on the xcodebuild command")
        }
    }

    // MARK: Storage

    /// "Zero KB", "512 bytes", "12.3 MB" (ByteCountFormatter .file, decimal) → bytes; nil while calculating.
    static func bytes(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: ",", with: "")
        if t.hasPrefix("Zero") { return 0 }
        let parts = t.split(separator: " ")
        guard parts.count >= 2, let n = Double(parts[0]) else { return nil }
        let units = ["bytes": 1.0, "byte": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12]
        return units[String(parts[1])].map { n * $0 }
    }

    /// Launch arguments for tests that open Settings › Storage: a jump button to the Storage section
    /// (`-uitestSettingsJump`, DEBUG), since swiping never reached it on the iPad panel (D2, D3, 2026-11-19).
    static let storageJump = ["-uitestSettingsJump", "storage"]

    func openStorage() {
        openSettingsPanel()
        // A navigation bar button since pass 5: the faint overlay at the list's corner passed its tap to the row below.
        let jump = app.buttons["uitestSettingsJump.storage"].firstMatch
        if app.launchArguments.contains("-uitestSettingsJump") {
            XCTAssertTrue(wait(5) { jump.exists }, "the Storage jump button in Settings' navigation bar")
        }
        if jump.exists {
            jump.tap()
            if !wait(3, { self.app.buttons["storageLink"].exists }) {
                jump.tap()
                _ = wait(3) { self.app.buttons["storageLink"].exists }
            }
        }
        tapControl("storageLink")
        XCTAssertTrue(wait(10) { self.app.navigationBars["Storage"].exists }, "Settings › Storage")
        _ = wait(30) { !self.element("storageMeasuring").exists && Self.bytes(self.text("storage.total")) != nil }
    }

    func storage(_ id: String) -> Double {
        let row = element("storage.\(id)")
        return row.exists ? Self.bytes(row.value as? String ?? "") ?? -1 : -1   // a missing row reads -1, not a hard failure
    }

    func storageValues(_ ids: [String]) -> [String: Double] {
        var out: [String: Double] = [:]
        for id in ids {
            _ = scrollTo(element("storage.\(id)"))
            out[id] = storage(id)
        }
        return out
    }

    /// Clear Caches… › Clear; returns the result line ("Cleared X." or the nothing-to-clear text).
    func clearCaches() -> String {
        tapControl("storageClearCaches")
        let confirm = app.buttons["storageClearConfirm"].firstMatch
        if wait(5, { confirm.exists }) {
            print("B07 clear caches: \(alertText(app.alerts.firstMatch))")
            confirm.tap()
            let result = element("storageCleanupResult")
            _ = wait(20) { result.exists }
            return text("storageCleanupResult")
        }
        let alert = app.alerts.firstMatch
        let message = alert.exists ? alertText(alert) : "no alert"
        if alert.exists { alert.buttons.firstMatch.tap() }
        return message
    }

    /// Records `seconds` from the controls and waits for the "Recording ready" panel.
    func recordClip(_ task: String, seconds: Double) {
        showControlsBar()
        let record = app.buttons["record"].firstMatch
        XCTAssertTrue(wait(5) { record.exists }, "\(task): Record")
        record.tap()
        // A refused start names its reason in the notice (full run 12 on D2: the visual change had been refused).
        XCTAssertTrue(wait(10) { self.element("recordingIndicator").exists },
                      "\(task): recording; notice: \(text("videoRecordingNoticeText").isEmpty ? "none" : text("videoRecordingNoticeText"))")
        pause(seconds)
        showControlsBar()
        app.buttons["record"].firstMatch.tap()
        XCTAssertTrue(wait(30) { self.app.buttons["recordingResultKeep"].exists || self.app.buttons["recordingResultShare"].exists },
                      "\(task): the recording is ready")
    }

    // MARK: PRE-007 collections (D1, D2, D3)

    /// The first three Included presets (the seed's positions 0, 1, 2), as the browser lists them.
    private func includedTop3() -> [String] {
        openNode("included")
        let names = Array(rows().prefix(3))
        goBack()
        return names
    }

    /// PRE-007-T23 step A: seeds "Device set" (Included 0, 1, 2), times S8 (create a collection, add a preset, play it:
    /// under 30 s from the open browser), and moves the second preset up with the Move Up action (the context menu;
    /// VoiceOver's custom action of the same name calls the same move, VoiceOver speech stays a person's).
    func testPRE007_A_SeedCreateAndReorder() {
        let task = "PRE-007-T23"
        launch(visual: "projectM", extra: ["-uitestSeedCollections", "Device set:0,1,2"])
        openBrowser()
        let top = includedTop3()
        XCTAssertEqual(top.count, 3, "\(task): three Included presets")

        // S8 from the open browser. Inside the timed steps the test waits on what the next step needs, never on a
        // fixed pause: on D2 (pass 9, 2026-11-19) the 31.4 s held 6.2 s of the test's own settle pauses, a 1.1 s
        // XCUITest retry of Save while the keyboard still moved the sheet, and about 1 s per tap of XCUITest's event
        // synthesis and idle waits; the app answered every step at once (scopeLine read "S8 set" on the first check).
        let started = Date()
        let anyPreset = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "preset:")).firstMatch
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)   // goBack() without its settle pause
        openNode("collections", settle: 0)
        let new = app.buttons["newCollection"].firstMatch
        XCTAssertTrue(wait(5) { new.exists }, "\(task): New Collection")
        new.tap()
        let name = app.textFields["collectionName"].firstMatch
        XCTAssertTrue(wait(5) { name.exists }, "\(task): the name field")
        name.tap()
        name.typeText("S8 set")
        let save = app.buttons["saveCollectionName"].firstMatch
        _ = wait(3) { save.exists && save.isHittable }
        save.tap()
        XCTAssertTrue(wait(5) { self.app.buttons["collection:S8 set"].exists }, "\(task): S8 set is listed")
        back.tap()
        openNode("included", settle: 0)
        _ = wait(5) { anyPreset.exists }
        if let first = rows().first {
            contextMenu(app.buttons["preset:\(first)"].firstMatch, "Add to Collection…", settle: 0)
            let target = app.buttons["addTo:S8 set"].firstMatch
            XCTAssertTrue(wait(5) { target.exists }, "\(task): Add to S8 set")
            target.tap()
            _ = wait(5) { !target.exists }
        }
        back.tap()
        openNode("collections", settle: 0)
        let s8set = app.buttons["collection:S8 set"].firstMatch
        _ = wait(5) { s8set.exists }
        s8set.tap()
        _ = wait(5) { anyPreset.exists }
        if let only = rows().first { app.buttons["preset:\(only)"].firstMatch.tap() }
        let playing = wait(15) { self.text("scopeLine").hasPrefix("S8 set") }
        let s8 = Date().timeIntervalSince(started)
        XCTAssertTrue(playing, "\(task): S8 set plays: \(text("scopeLine"))")
        XCTAssertLessThan(s8, 30, "\(task) S8: create, add and play in under 30 s (\(s8) s)")

        openBrowser()
        openNode("collections")
        app.buttons["collection:Device set"].firstMatch.tap()
        pause(0.8)
        XCTAssertEqual(rows(), top, "\(task): the seeded order")
        if top.count == 3 {
            contextMenu(app.buttons["preset:\(top[1])"].firstMatch, "Move Up")
            XCTAssertEqual(rows(), [top[1], top[0], top[2]], "\(task): Move Up")
            contextMenu(app.buttons["preset:\(top[1])"].firstMatch, "Move Down")
            XCTAssertEqual(rows(), top, "\(task): Move Down")
            contextMenu(app.buttons["preset:\(top[1])"].firstMatch, "Move Up")   // left moved for step B
            XCTAssertEqual(rows(), [top[1], top[0], top[2]], "\(task): the order step B expects")
        }
        report(task, "S8 and reorder", ["s8Seconds": s8])
    }

    /// PRE-007-T23 step B, after the Mac installed the build over the app: both collections and the moved order.
    func testPRE007_B_CollectionsSurviveInstallOver() {
        let task = "PRE-007-T23"
        relaunch()
        openBrowser()
        let top = includedTop3()
        openNode("collections")
        XCTAssertTrue(wait(5) { self.app.buttons["collection:Device set"].exists }, "\(task): Device set survives")
        XCTAssertTrue(app.buttons["collection:S8 set"].exists, "\(task): S8 set survives")
        app.buttons["collection:Device set"].firstMatch.tap()
        pause(0.8)
        XCTAssertEqual(rows(), top.count == 3 ? [top[1], top[0], top[2]] : top, "\(task): the order survives")
        report(task, "after install over", ["collections": Double(rows("collection:").count)])
    }

    // MARK: PRE-012 import through Files (D1, D2, D3)

    /// PRE-012-T31: a preset and a JPEG renamed .milk through the real Files picker: the preset is added (time from
    /// Open to the result, the trial included), the JPEG is quarantined as "not text"; accessibility audits of My
    /// Presets and Quarantine (a VoiceOver listening pass stays a person's).
    func testPRE012ImportThroughFilesPicker() {
        let task = "PRE-012-T31"
        launch(visual: "projectM")
        openBrowser()
        openNode("myPresets")
        let preset = importPreset("preset-small.milk")
        XCTAssertTrue(preset.text.contains("Added") || preset.text.contains("already"), "\(task): \(preset.text)")
        XCTAssertLessThan(preset.seconds, 15, "\(task): the trial and import finish quickly (\(preset.seconds) s)")
        let jpeg = importPreset("not-a-preset.milk")
        XCTAssertTrue(jpeg.text.contains("was put in Quarantine") && jpeg.text.contains("not text"), "\(task): \(jpeg.text)")
        let myPresets = auditIssues(app, "My Presets", types: [.sufficientElementDescription, .hitRegion])
        let quarantine = app.buttons["quarantineLink"].firstMatch
        XCTAssertTrue(scrollTo(quarantine), "\(task): Quarantine is linked")
        quarantine.tap()
        let reason = element("quarantineReason:not-a-preset.milk")
        XCTAssertTrue(wait(5) { reason.exists }, "\(task): the JPEG is in Quarantine")
        let quarantined = auditIssues(app, "Quarantine", types: [.sufficientElementDescription, .hitRegion])
        (myPresets + quarantined).forEach { print("PRE-012-T31 audit: \($0)") }
        XCTAssertTrue(myPresets.isEmpty && quarantined.isEmpty, "\(task): audits: \(myPresets + quarantined)")
        let delete = app.buttons["deleteQuarantined:not-a-preset.milk"].firstMatch
        if delete.exists {   // leaves Quarantine empty for the next run
            delete.tap()
            let confirm = app.alerts.firstMatch
            if wait(2, { confirm.exists }) { confirm.buttons.allElementsBoundByIndex.last?.tap() }
        }
        report(task, "Files import", ["presetSeconds": preset.seconds, "jpegSeconds": jpeg.seconds,
                                      "auditIssues": Double(myPresets.count + quarantined.count)])
    }

    // MARK: PRE-014 export to Files (D1, D3)

    /// PRE-014-T25: two imports, an Included copy and a pack copy (unlocked library); Export selects all, the share
    /// sheet saves the ZIP in Files (a popover on D3), the summary names the excluded pack copy, and the Mac pulls the
    /// ZIP and checks its entries (`files.pull`: imports and the Included copy present, the pack copy absent).
    func testPRE014ExportZipToFiles() {
        let task = "PRE-014-T25"
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "YES"]
        app.launch()
        XCTAssertTrue(wait(20) { self.app.staticTexts["sourceStarts"].exists }, "\(task): launched (unlocked)")
        pause(2)
        openBrowser()
        openNode("myPresets")
        for file in ["preset-small.milk", "preset-512k.milk"] {
            let result = importPreset(file)
            XCTAssertTrue(result.text.contains("Added") || result.text.contains("already"), "\(task) \(file): \(result.text)")
        }
        goBack()
        openNode("included")
        let included = duplicateFirstPreset()
        goBack()
        openNode("en-d")
        let pack = duplicateFirstPreset()
        closeBrowser()
        openBrowser()
        openNode("myPresets")
        let export = app.buttons["exportPresets"].firstMatch
        XCTAssertTrue(wait(5) { export.exists }, "\(task): Export")
        export.tap()
        XCTAssertTrue(wait(5) { self.element("presetExportSheet").exists }, "\(task): the export sheet")
        app.buttons["exportSelectAll"].firstMatch.tap()
        let exclusions = text("exportExclusions")
        app.buttons["exportConfirm"].firstMatch.tap()
        saveSharedFileToDocuments(task)
        let summary = element("exportSummary")
        XCTAssertTrue(wait(15) { summary.exists }, "\(task): the export summary")
        // QA-011 pass 6 (D3, iPadOS 26.5, 2026-11-19), a test bug: the summary is a Label whose identifier its icon
        // shares; the first match was the icon (an Image), whose label is the symbol's own "Selected"
        // (checkmark.circle), so the check read "Selected" although the summary showed. Read the summary's text.
        let summaryText = app.staticTexts.matching(identifier: "exportSummary").firstMatch
        let line = summaryText.exists ? summaryText.label : text("exportSummary")
        XCTAssertTrue(line.hasPrefix("Exported"), "\(task): \(line)")
        XCTAssertTrue((line + " " + exclusions).contains("full library"), "\(task): the pack copy is named as excluded: \(line) \(exclusions)")
        var present = ["preset-small", "preset-512k"]
        if let included { present.append(included) }
        if !MacDriver.isFollowing { print("PRE-014-T25: no Mac driver; check the ZIP by hand (docs/autotester.md, Batch 5)") }
        MacDriver.request("files.pull", ["prefix": "projectM-iOS Presets ", "suffix": ".zip", "present": present,
                                         "absent": pack.map { ["\($0) copy"] } ?? []])
        print("PRE-014-T25 check the driver log's MAC-DONE line for the ZIP entries (pack copy \(pack ?? "?") copy absent)")
        report(task, "export", ["summaryShown": summary.exists ? 1 : 0])
    }

    // MARK: PRE-001 thumbnails (D1)

    /// The visualizer's presented frames (`visualFrames`, `-uitestMemoryPressure`) over a browser-open window, as fps.
    private func framesWhileBrowsing(_ task: String, seconds: Double) -> (fps: Double, thumbnails: Int, rows: Int) {
        let before = Int(text("visualFrames").filter(\.isNumber)) ?? -1, start = Date()   // "1,234" past 999
        openBrowser()
        openNode("included")
        pause(seconds)
        let thumbnails = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'thumbnail:'")).count
        let shownRows = rows().count   // preset rows laid out on screen (thumbnails are made only for rows shown)
        closeBrowser()
        let after = Int(text("visualFrames").filter(\.isNumber)) ?? -1   // "1,234" past 999
        let fps = Double(after - before) / Date().timeIntervalSince(start)
        report(task, "browser open", ["fps": fps, "thumbnails": Double(thumbnails), "rows": Double(shownRows)])
        return (fps, thumbnails, shownRows)
    }

    /// PRE-001-T14 (S7): the visualizer's frame rate while about 20 thumbnails generate behind the browser (cache
    /// cleared first with Clear Caches) is within 10 % of the same window with them cached.
    func testPRE001FPSWhileThumbnailsGenerate() {
        let task = "PRE-001-T14"
        launch(visual: "projectM", extra: ["-uitestMemoryPressure"] + Self.storageJump)
        openStorage()
        print("PRE-001-T14 \(clearCaches())")
        closeSettingsPanel()
        pause(3)
        let generating = framesWhileBrowsing(task, seconds: 10)
        pause(3)
        let cached = framesWhileBrowsing(task, seconds: 10)
        // At least 10, or every row on screen when fewer show: the iPad's browser sheet drew 8 thumbnails both with and
        // without the cache, all it had on screen (D3 2026-11-19; spec 132 Clarifications, QA-011 device run 2026-11-19).
        XCTAssertGreaterThan(generating.thumbnails, 0, "\(task): thumbnails were drawn")
        XCTAssertGreaterThanOrEqual(generating.thumbnails, min(10, generating.rows),
                                    "\(task): every row shown has its thumbnail (\(generating.thumbnails) of \(generating.rows) rows)")
        XCTAssertGreaterThan(cached.fps, 0, "\(task): frames counted")
        XCTAssertGreaterThanOrEqual(generating.fps, cached.fps * 0.9,
                                    "\(task): \(generating.fps) fps generating vs \(cached.fps) fps cached (within 10 %)")
    }

    // MARK: FILE-001 scene archive (D1 → D3)

    private func openSceneFolders(addCurrentScene: Bool) {
        openSettingsPanel()
        tapControl("showEditorLink")
        if addCurrentScene {
            let add = app.buttons["showAddCurrentScene"].firstMatch
            XCTAssertTrue(scrollTo(add), "Add Current Scene")
            add.tap()
            pause(1)
        }
        tapControl("showSceneFoldersLink")
        pause(1)
    }

    /// From Scene Folders: back to the Show Editor, then the last cue's leading swipe › Go (the row's "Go to Cue").
    private func goToLastCue(_ task: String) {
        let back = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        if back.exists { back.tap() }
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES 'showCue[0-9]+'"))
        XCTAssertTrue(wait(5) { rows.count > 0 }, "\(task): the show's cues are listed")
        // Every row's value starts "Cue n of N": N names the last row.
        let value = rows.firstMatch.value as? String ?? ""
        let total = value.split(separator: " ").dropFirst(3).first.map { String($0).trimmingCharacters(in: .punctuationCharacters) }
        guard let total, let count = Int(total) else { return XCTFail("\(task): cue count from \"\(value)\"") }
        let last = app.descendants(matching: .any)["showCue\(count)"].firstMatch
        XCTAssertTrue(scrollTo(last), "\(task): cue \(count) (the imported scene)")
        last.swipeRight()
        let go = app.buttons["Go"].firstMatch
        XCTAssertTrue(wait(3) { go.exists }, "\(task): Go on cue \(count)")
        go.tap()
        pause(1)
    }

    /// FILE-001-T19 on D1: a scene holding a photo and a video, exported as a .pmscene through the real share sheet
    /// into Documents; the Mac pulls it for D3. The scene is the DEBUG seed "Photo and Video" (`-uitestPhotoVideoScene`:
    /// the stored photo under the stored video, one cue): Add Current Scene records one visual's fixed stack, so under
    /// the Video visual it held the video only and D3's preview read "1 video" (D2, 2026-11-22; docs/autotester.md).
    func testFILE001_A_ExportSceneArchive() throws {
        let task = "FILE-001-T19"
        try requireMac(task)
        launch(visual: "video", extra: ["-uitestSeedPhoto", "pattern", "-uitestSeedVideo", "counter", "-uitestPhotoVideoScene",
                                        "-uitestSettingsSection", "show"])
        XCTAssertTrue(wait(30) { self.videoValue == "Video 64 × 48" }, "\(task): the seeded video plays: \(videoValue)")
        pause(1)   // the seed saves the scene once both media are stored (polled every 0.25 s)
        openSceneFolders(addCurrentScene: false)
        let row = app.descendants(matching: .any)["sceneFolderScene.Photo and Video"].firstMatch
        XCTAssertTrue(wait(5) { row.exists }, "\(task): the seeded scene \"Photo and Video\" is listed")
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)),
                    withVelocity: .fast, thenHoldForDuration: 0.05)
        let export = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "sceneFolderExportScene", "Export Scene")).firstMatch
        XCTAssertTrue(wait(3) { export.exists }, "\(task): Export Scene")
        export.tap()
        saveSharedFileToDocuments(task)
        XCTAssertTrue(wait(15) { self.text("scenePackStatus").hasPrefix("Exported") }, "\(task): \(text("scenePackStatus"))")
        MacDriver.request("files.pull", ["prefix": "projectM-iOS Scene ", "suffix": ".pmscene"])
        report(task, "export on \(deviceModel())", ["exported": text("scenePackStatus").hasPrefix("Exported") ? 1 : 0])
    }

    /// FILE-001-T19 on D3: the Mac pushes the other device's archive (D1, or `FILE001_FROM`) into Documents; Import Scene… picks it in Files, the preview
    /// lists the photo and the video, Import adds the cue, and applying it shows the imported photo (a scene with a photo
    /// layer applies the Photo visual, `ShowSceneSnapshot.apply`); the Video visual then plays the imported video.
    /// "Offline" (Airplane Mode) is a USB-cable step: not required (owner ruling 2026-11-18); nothing here uses the network.
    func testFILE001_B_ImportSceneArchive() throws {
        let task = "FILE-001-T19"
        try requireMac(task)
        // The exporting device (TEST_RUNNER_FILE001_FROM, default D1): D1 is not used in QA-011, so D2's archive (full
        // run 13, 2026-11-21) is imported on D3. Never the importing device itself: the check is a second device.
        let from = ProcessInfo.processInfo.environment["FILE001_FROM"] ?? "D1"
        MacDriver.request("files.push", ["from": from, "prefix": "projectM-iOS Scene ", "suffix": ".pmscene"])
        // Once: only the first Settings opens at Show; the later ones open at the top, where the photo summary and the
        // visual rows are (D3, 2026-11-23: reopened at Show, neither was found in 12 swipes each way).
        launch(visual: "projectM", extra: ["-uitestSettingsSection", "show", "-uitestSettingsSectionOnce"])
        pause(10)   // the push lands while the app launches (the log reaches the Mac a few seconds late)
        openSceneFolders(addCurrentScene: true)   // Scene Folders shows once the show has a cue
        tapControl("scenePackImportRow")
        XCTAssertTrue(ui.filesPick(name: "projectM-iOS Scene "), "\(task): Files: D1's archive")
        let media = element("scenePackMedia")
        XCTAssertTrue(wait(15) { media.exists }, "\(task): the preview")
        XCTAssertTrue(media.label.contains("1 photo") && media.label.contains("1 video"), "\(task): \(media.label)")
        app.buttons["scenePackImport"].firstMatch.tap()
        XCTAssertTrue(wait(15) { self.text("scenePackStatus").hasPrefix("Imported") }, "\(task): \(text("scenePackStatus"))")
        goToLastCue(task)   // the imported cue is appended; D3's show keeps earlier runs' cues, so Next Cue can miss it
        closeSettingsPanel()
        // The export seeds `-uitestSeedPhoto pattern` (UITestPhotoFixture.patternPNG: 256 × 192), not the 64 × 48 solid PNG.
        XCTAssertTrue(wait(30) { self.photoValue == "Photo 256 × 192" }, "\(task): the imported photo shows: \(photoValue)")
        openSettingsPanel()
        _ = scrollTo(element("photoSummary"))
        XCTAssertFalse(summary("photoSummary").contains("No photo"), "\(task): the imported photo is stored: \(summary("photoSummary"))")
        closeSettingsPanel()
        chooseVisual("video")
        XCTAssertTrue(wait(30) { self.videoValue == "Video 64 × 48" }, "\(task): the imported video plays: \(videoValue)")
        report(task, "import on \(deviceModel())", ["imported": 1])
    }

    // MARK: FILE-009 storage (D1)

    static let storageRows = ["photos", "videos", "scenes", "presets", "importedAudio", "recordings", "savedRecordings",
                              "sharesAndExports", "caches", "otherAppData", "total"]

    /// The Settings app's "Documents & Data" for the app (General › iPhone Storage › projectM), or nil.
    private func iPhoneStorageDocumentsAndData() -> Double? {
        let settings = ui.preferences
        ui.openSettings(path: ["General", UIDevice.current.userInterfaceIdiom == .pad ? "iPad Storage" : "iPhone Storage"])
        let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", SystemUI.appDisplayName)).firstMatch
        guard wait(40, { row.exists }) else { return nil }   // iOS measures every app first
        _ = ui.scrollTo(row, in: settings)
        row.tap()
        let cell = settings.cells.containing(NSPredicate(format: "label CONTAINS 'Documents'")).firstMatch
        guard wait(10, { cell.exists }) else { return nil }
        let labels = cell.staticTexts.allElementsBoundByIndex.map(\.label) + [cell.label]
        let value = labels.compactMap { Self.bytes($0) }.first
        settings.terminate()
        app.activate()
        return value
    }

    /// FILE-009-T12: a photo, a video and the imported music track, a kept recording; Settings › Storage shows each
    /// category above zero and a total at least their sum, and is compared with iOS's "Documents & Data" for the app
    /// (reported; iOS refreshes that figure lazily). The Mac's container size cross-check:
    /// `xcrun devicectl device info files --device <id> --domain-type appDataContainer --domain-identifier
    /// org.projectmios.ProjectMiOS --json-output f` (sum of sizes), in docs/autotester.md.
    func testFILE009StorageValuesWithRealMedia() {
        let task = "FILE-009-T12"
        launch(visual: "photo", extra: Self.storageJump)   // the music fixture is imported audio (-uitestImportAudio)
        pickFromFiles("choosePhotoFromFiles", "photo-small.jpg")
        _ = settledSummary("photoSummary")
        closeSettingsPanel()
        chooseVisual("video")   // Settings lists Choose from Files… for a video only under the Video visual
        pickFromFiles("chooseVideoFromFiles", "video-h264-1080p.mp4")
        _ = settledSummary("videoSummary", timeout: 90)
        closeSettingsPanel()
        recordClip(task, seconds: 4)
        let keep = app.buttons["recordingResultKeep"].firstMatch
        if keep.exists { keep.tap() }
        pause(1)
        openStorage()
        let values = storageValues(Self.storageRows)
        report(task, "Settings › Storage", values)
        for id in ["photos", "videos", "importedAudio"] {
            XCTAssertGreaterThan(values[id] ?? -1, 0, "\(task): \(id) counts the imported media")
        }
        XCTAssertGreaterThan(max(values["recordings"] ?? -1, values["savedRecordings"] ?? -1), 0, "\(task): the recording counts")
        let parts = Self.storageRows.dropLast().compactMap { values[$0] }.filter { $0 > 0 }.reduce(0, +)
        XCTAssertGreaterThanOrEqual((values["total"] ?? -1) * 1.06, parts, "\(task): the total covers the rows (rounding)")
        closeSettingsPanel()
        let documentsAndData = iPhoneStorageDocumentsAndData()
        let total = values["total"] ?? -1
        report(task, "iPhone Storage", ["documentsAndData": documentsAndData ?? -1, "appTotal": total,
                                        "ratio": total > 0 ? documentsAndData.map { $0 / total } ?? -1 : -1])
        print("FILE-009-T12 Documents & Data \(documentsAndData.map { String($0) } ?? "unread") vs Storage total \(values["total"] ?? -1)")
    }

    // MARK: FILE-010 Clear Caches (D1)

    /// FILE-010-T11: preset switches (thumbnails and engine caches), a recording shared to Files (a share copy), then
    /// Settings › Storage › Clear Caches frees the Caches and share copies; after a relaunch the app plays and the
    /// current scene and the show load as before (`showAppliedScene`: applied scene ID | visual). The Mac's
    /// cross-check of Library/Caches: `devicectl device info files … --subdirectory Library/Caches` (docs/autotester.md).
    func testFILE010ClearCaches() {
        let task = "FILE-010-T11"
        launch(visual: "projectM", extra: ["-uitestSeedPhoto", "pattern", "-uitestShowSeed"] + Self.storageJump)
        // The show seed stands on cue 1, a Circular Spectrum scene, and the preset controls are hidden under a native
        // visual (ControlsOverlay): back to projectM before browsing presets (D3, 2026-11-19: no Presets control).
        chooseVisual("projectM")
        for i in 0..<3 {   // three preset switches through the browser
            openBrowser()
            openNode("included")
            let names = rows()
            if names.count > i { app.buttons["preset:\(names[i])"].firstMatch.tap() }
            pause(2)
            closeBrowser()
        }
        chooseVisual("photo")
        recordClip(task, seconds: 3)
        let share = app.buttons["recordingResultShare"].firstMatch
        if wait(5, { share.exists }) {
            share.tap()
            saveSharedFileToDocuments(task)
        }
        openStorage()
        let before = storageValues(["caches", "sharesAndExports", "photos", "scenes", "total"])
        let result = clearCaches()
        pause(1)
        let refresh = app.buttons["storageRefresh"].firstMatch
        if refresh.exists { refresh.tap(); pause(2) }
        let after = storageValues(["caches", "sharesAndExports", "photos", "scenes", "total"])
        report(task, "before", before)
        report(task, "after", after)
        print("FILE-010-T11 \(result)")
        XCTAssertTrue(result.hasPrefix("Cleared"), "\(task): \(result)")
        XCTAssertLessThan(after["caches"] ?? -1, before["caches"] ?? -1, "\(task): the Caches size drops")
        XCTAssertLessThanOrEqual(after["sharesAndExports"] ?? -1, before["sharesAndExports"] ?? -1, "\(task): share copies go")
        XCTAssertEqual(after["photos"], before["photos"], "\(task): photos are kept")
        XCTAssertEqual(after["scenes"], before["scenes"], "\(task): scenes are kept")
        closeSettingsPanel()
        // `showAppliedScene` is "<scene applied by a step this launch>|<visual>": the step part is per launch (nil until
        // a cue is stepped, ShowCoordinator.appliedSceneID), so after a relaunch only the visual is compared, and the
        // show counts as loaded when its cue controls are back (D2 2026-11-19 read "none|photo" against
        // "5CE7…01|photo", the same scene state).
        let visual = text("showAppliedScene").split(separator: "|").last.map(String.init) ?? ""
        relaunch()
        XCTAssertTrue(wait(15) { self.text("showAppliedScene").hasSuffix("|\(visual)") },
                      "\(task): the scene's visual loads: \(text("showAppliedScene")) (was \(visual))")
        XCTAssertTrue(wait(20) { self.photoValue.hasPrefix("Photo ") }, "\(task): the current scene's photo: \(photoValue)")
        showControlsBar()
        XCTAssertTrue(wait(5) { self.app.buttons["showNextCue"].exists }, "\(task): the show loads (its cue controls)")
        // The music must be playing again before the spectrum over the photo can move; a stopped source is its own
        // failure, not a motion one (D2 2026-11-19: motion 0.0001 with nothing to say why).
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(wait(15) { overlay.exists && overlay.label.contains("Active audio") },
                      "\(task): music after relaunch: \(overlay.exists ? String(overlay.label.prefix(120)) : "no performance overlay")")
        _ = wait(8) { !self.app.otherElements["controls"].exists }
        assertMovingSampled(task, "after relaunch")
    }
}
