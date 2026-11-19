// B08ShareDeviceTests.swift — QA-011 Batch 6 (2026-11-18): the recording and still-frame steps of owner session B08
// that go through iOS's own UI (the Files exporter and mover, the share sheet, the Files app), driven with SystemUI.
// Nothing here raises a permission prompt (Save to Files and the share sheet ask none; a prompt fails the test).
// * REC-001-T19: Save Frame as PNG and as HEIF to On My iPhone/iPad › projectM; the Mac pulls both and `sips` reads
//   them (format, size). iCloud Drive stays a person's (needs iCloud signed in on the device).
// * REC-003-T25: a recording saved through Save… to On My iPad › projectM; the Mac reads it as HEVC (hvc1); the Files
//   app opens it and Quick Look shows a player. iCloud Drive stays a person's.
// * REC-012-T13: the share sheet for a frame and a recording lists AirDrop, Save to Files (and Messages on the iPhone),
//   no Save Image/Save Video/Assign to Contact; a cancel keeps the panel; Messages' compose opens and is cancelled
//   (nothing is sent); Save to Files completes ("Shared."); on an iPad the sheet is a popover at Share…. An AirDrop
//   transfer needs a receiver who accepts: a person's.
// * REC-010-T13: record, Keep, Settings › Storage › Recordings, play (the player's picture changes), Share… › Save to
//   Files, rename, delete; the Mac confirms the renamed file is gone from the library folder.
// Files the Mac checks are named by RECORDING-CHECK lines: python3 scripts/recording_frame_check.py run --log <log>
// --device D1. The Files app and picker layouts differ by release: check the first run's screenshots and fix
// SystemUI.swift (not these tests) where they do.
import UIKit
import XCTest

@MainActor
final class B08ShareDeviceTests: DeviceAcceptanceCase {
    private lazy var system = SystemUI(app: app)

    override func tearDown() async throws {
        system.restore()
        try await super.tearDown()
    }

    private var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var place: String { pad ? "On My iPad" : "On My iPhone" }

    private func launchPhoto(_ extra: [String] = []) {
        launch(visual: "photo", extra: ["-uitestSeedPhoto", "pattern"] + extra)
    }

    private func noPrompt(_ step: String) {
        XCTAssertFalse(SystemUI.springboard.alerts.firstMatch.exists, "\(step): no system prompt")
    }

    private func notice(_ id: String) -> String {
        let text = app.staticTexts[id]
        return text.exists ? text.label : ""
    }

    /// Save Frame in `format` ("PNG" or "HEIF"): the "Frame ready" panel.
    private func saveFrame(_ format: String) -> Bool {
        revealRecordingControls()
        app.buttons["saveFrame"].tap()
        // firstMatch: iPadOS 26 lists each choice of the menu twice, a button inside a button (D3, 2026-11-19).
        let choice = app.buttons["saveFrame\(format)"].firstMatch
        guard wait(5, { choice.exists }) else {
            XCTFail("Save Frame offers no \(format)")
            return false
        }
        choice.tap()
        return wait(8) { self.app.buttons["frameResultSave"].exists }
    }

    /// Records about `seconds` (no recording folder: the file is offered in "Recording ready").
    private func recordOffered(_ seconds: Double) -> Date? {
        guard let began = startRecording("offered") else { return nil }
        pause(seconds)
        revealRecordingControls()
        app.buttons["record"].tap()
        return wait(20, { self.app.buttons["recordingResultShare"].exists }) ? began : nil
    }

    // MARK: REC-001-T19

    /// PNG and HEIF to On My iPhone/iPad › projectM through the Files exporter; the Mac reads both with `sips`.
    func testREC001PNGAndHEIFToOnMyDevice() {
        let task = "REC-001-T19"
        launchPhoto()
        for (format, ext, uti) in [("PNG", ".png", "png"), ("HEIF", ".heic", "heic")] {
            let began = Date()
            guard saveFrame(format) else { return XCTFail("\(format): no Frame ready panel") }
            app.buttons["frameResultSave"].tap()
            XCTAssertTrue(system.filesSave(), "\(format): saved in \(place) › projectM")
            XCTAssertTrue(wait(10) { self.notice("frameCaptureNoticeText") == "Frame saved." },
                          "\(format): \(notice("frameCaptureNoticeText"))")
            noPrompt(format)
            screen(task, "\(format) saved")
            RecordingCheck.emit(task: task, label: "\(format) in \(place)", dir: "Documents", prefix: "Visualizer Frame",
                                suffix: ext, notBefore: began, checks: ["image": ["format": uti, "minPixels": 500_000]])
        }
    }

    // MARK: REC-003-T25

    /// A recording through Save… (the system mover) to On My iPad › projectM; the Mac reads hvc1; Files plays it.
    func testREC003SaveToOnMyDeviceAndPlayInFiles() {
        let task = "REC-003-T25"
        launchPhoto()
        guard let began = recordOffered(4) else { return XCTFail("no Recording ready panel") }
        app.buttons["recordingResultSave"].tap()
        XCTAssertTrue(system.filesSave(), "saved in \(place) › projectM")
        XCTAssertTrue(wait(10) { self.notice("videoRecordingNoticeText") == "Recording saved." },
                      "the mover finished: \(notice("videoRecordingNoticeText"))")
        noPrompt("Save…")
        RecordingCheck.emit(task: task, label: "HEVC in \(place)", dir: "Documents", notBefore: began,
                            checks: ["codec": "hvc1", "minDuration": 3, "audioTrack": true])
        // The Files app: Browse › On My iPad › projectM › the newest recording; Quick Look shows a player.
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        XCTAssertTrue(files.wait(for: .runningForeground, timeout: 10), "Files is in front")
        // iPadOS 26's floating tab bar nests a second Browse button; a second tap goes back to Browse's root. On iPadOS
        // 27.2 (D2, pass 4) the first tap already shows the root and Browse is gone: tap again only while it is there.
        let browse = files.buttons["Browse"].firstMatch
        if wait(5, { browse.exists }) {
            browse.tap()
            pause(1)
            if browse.exists && browse.isHittable { browse.tap() }
        }
        for item in [place, SystemUI.appDisplayName] {
            let row = files.descendants(matching: .any).matching(NSPredicate(format: "label == %@", item)).firstMatch
            XCTAssertTrue(wait(6) { row.exists }, "Files: \(item)")
            if row.exists { row.tap(); pause(1) }
        }
        // The folder is sorted by name and holds the test fixtures (about 50 on D3): "Visualizer Recording …" sits
        // below the first screen and the grid builds cells only near it (rerun 4, D3). Scroll until one is built.
        let recordings = files.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Visualizer Recording'"))
        var listed = wait(4) { recordings.count > 0 }
        for _ in 0..<12 where !listed {
            files.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: files.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)))
            listed = wait(1) { recordings.count > 0 }
        }
        XCTAssertTrue(listed, "Files lists the recording")
        let labels = recordings.allElementsBoundByIndex.map(\.label)
        if let newest = labels.max(),
           let index = labels.firstIndex(of: newest) {
            recordings.element(boundBy: index).tap()
            let player = files.descendants(matching: .any).matching(
                NSPredicate(format: "label IN {'Play', 'Pause', 'Video', 'Mute', 'Unmute'}")).firstMatch
            let shown = wait(10) { player.exists || files.sliders.firstMatch.exists }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "\(task) Files Quick Look"
            shot.lifetime = .keepAlways
            add(shot)
            report(task, "Files plays it", ["player": shown ? 1 : 0])
            XCTAssertTrue(shown, "Quick Look shows a player for \(newest)")
        }
        files.terminate()
        app.activate()
    }

    // MARK: REC-012-T13

    private var sheetMarker: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label IN {'Save to Files', 'AirDrop', 'Copy'}")).firstMatch
    }

    /// Every label the share sheet shows (its activities and actions), from one snapshot of the tree. Reading
    /// `allElementsBoundByIndex` element by element failed on D2 and D3 (rerun 4): the sheet was still building its
    /// rows, so "Element at index 35/36" was gone by the time its label was read.
    private func sheetLabels() -> Set<String> {
        guard let root = try? app.snapshot() else { return [] }
        let kinds: Set<XCUIElement.ElementType> = [.button, .cell, .staticText]
        var labels = Set<String>()
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if kinds.contains(node.elementType), !node.label.isEmpty { labels.insert(node.label) }
            stack += node.children
        }
        return labels
    }

    private func dismissSheet() {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists { region.tap(); return }
        for name in ["Close", "Cancel"] where app.buttons[name].firstMatch.exists && app.buttons[name].firstMatch.isHittable {
            app.buttons[name].firstMatch.tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
    }

    /// The share sheet for `kind` ("frame" or "recording"): activities, cancel, Messages, Save to Files.
    private func checkShareSheet(_ task: String, kind: String, prefix: String, suffix: String, began: Date) {
        let shareID = kind == "frame" ? "frameResultShare" : "recordingResultShare"
        let share = app.buttons[shareID]
        share.tap()
        XCTAssertTrue(wait(8) { self.sheetMarker.exists }, "\(kind): the share sheet")
        noPrompt("\(kind) share sheet")
        let labels = sheetLabels()
        let popover = app.otherElements["PopoverDismissRegion"].exists
        print("B08 \(task) \(kind) sheet: \(labels.sorted()) popover=\(popover)")
        screen(task, "\(kind) share sheet")
        for wanted in ["AirDrop", "Save to Files"] + (pad ? [] : ["Messages"]) {
            XCTAssertTrue(labels.contains(wanted), "\(kind): the sheet offers \(wanted)")
        }
        for unwanted in ["Save Image", "Save Video", "Assign to Contact", "Save to Camera Roll"] {
            XCTAssertFalse(labels.contains(unwanted), "\(kind): no \(unwanted) (REC-012-R7)")
        }
        if pad {
            // REC-012-R13: a popover pointing at Share…: the sheet sits next to the button, not across the screen.
            let sheet = sheetMarker.frame, button = share.frame
            let distance = hypot(sheet.midX - button.midX, sheet.midY - button.midY)
            report(task, "\(kind) popover", ["popover": popover ? 1 : 0, "distance": Double(distance)])
            XCTAssertTrue(popover, "\(kind): on an iPad the sheet is a popover")
        }
        // Cancel keeps the panel.
        dismissSheet()
        XCTAssertTrue(wait(5) { !self.sheetMarker.exists }, "\(kind): the sheet closes")
        XCTAssertTrue(share.exists, "\(kind): a cancel keeps the panel")
        XCTAssertFalse(app.descendants(matching: .any)["captureShareNotice"].firstMatch.exists, "\(kind): no notice on cancel")
        // Messages: the compose sheet opens and is cancelled (nothing is sent).
        if labels.contains("Messages") {
            share.tap()
            XCTAssertTrue(wait(8) { self.sheetMarker.exists }, "\(kind): the sheet again")
            XCTAssertTrue(system.shareSheet("Messages"), "\(kind): Messages")
            let cancel = app.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}")).firstMatch
            let composed = wait(10) { cancel.exists }
            screen(task, "\(kind) Messages compose")
            report(task, "\(kind) Messages compose", ["opened": composed ? 1 : 0])
            XCTAssertTrue(composed, "\(kind): the Messages compose sheet opens")
            if composed { cancel.tap() }
            let deleteDraft = app.buttons["Delete Draft"]
            if wait(2, { deleteDraft.exists }) { deleteDraft.tap() }
            XCTAssertTrue(wait(8) { share.exists && share.isHittable }, "\(kind): back at the panel after Messages")
            noPrompt("\(kind) Messages")
        }
        // Save to Files completes.
        share.tap()
        XCTAssertTrue(wait(8) { self.sheetMarker.exists }, "\(kind): the sheet for Save to Files")
        XCTAssertTrue(system.shareSheet("Save to Files"), "\(kind): Save to Files")
        XCTAssertTrue(system.filesSave(), "\(kind): saved in \(place) › projectM")
        XCTAssertTrue(wait(10) { self.notice("captureShareNoticeText") == "Shared." },
                      "\(kind): \(notice("captureShareNoticeText"))")
        noPrompt("\(kind) Save to Files")
        let checks: [String: Any] = kind == "frame" ? ["image": ["format": "png"]] : ["codec": "hvc1", "minDuration": 2]
        RecordingCheck.emit(task: task, label: "\(kind) via Save to Files", dir: "Documents", prefix: prefix, suffix: suffix,
                            notBefore: began, checks: checks)
        if app.buttons["captureShareNoticeDismiss"].exists { app.buttons["captureShareNoticeDismiss"].tap() }
    }

    func testREC012ShareSheetForAFrameAndARecording() {
        let task = "REC-012-T13"
        launchPhoto()
        let frameBegan = Date()
        XCTAssertTrue(saveFrame("PNG"), "Frame ready")
        checkShareSheet(task, kind: "frame", prefix: "Visualizer Frame", suffix: ".png", began: frameBegan)
        if app.buttons["frameResultDiscard"].exists { app.buttons["frameResultDiscard"].tap() }
        guard let began = recordOffered(3) else { return XCTFail("no Recording ready panel") }
        checkShareSheet(task, kind: "recording", prefix: "Visualizer Recording", suffix: ".mp4", began: began)
        if app.buttons["recordingResultDiscard"].exists { app.buttons["recordingResultDiscard"].tap() }
    }

    // MARK: REC-010-T13

    func testREC010RecordKeepPlayShareRenameDelete() {
        let task = "REC-010-T13"
        launchPhoto(["-uitestSettingsSection", "storage"])
        guard let began = recordOffered(4) else { return XCTFail("no Recording ready panel") }
        app.buttons["recordingResultKeep"].tap()
        XCTAssertTrue(wait(5) { self.notice("videoRecordingNoticeText") == "Recording kept in Recordings." },
                      "Keep: \(notice("videoRecordingNoticeText"))")
        // Settings › Storage › Recordings.
        revealRecordingControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings")
        let storage = app.buttons["storageLink"]
        for _ in 0..<6 where !(storage.exists && storage.isHittable) { app.swipeUp() }
        storage.tap()
        let link = app.buttons["storage.savedRecordings"]
        XCTAssertTrue(wait(8) { link.exists }, "Storage › Saved recordings")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Recordings"].exists }, "Recordings")
        let rows = app.descendants(matching: .any).matching(identifier: "recordingLibraryRow")
        XCTAssertTrue(wait(8) { rows.count > 0 }, "the kept recording is listed")
        let before = rows.count
        // Play (newest first): the player's picture changes over 2 s.
        app.buttons.matching(identifier: "recordingLibraryPlay").firstMatch.tap()
        let player = app.descendants(matching: .any)["recordingLibraryPlayer"].firstMatch
        XCTAssertTrue(wait(8) { player.exists }, "the player opens")
        pause(1)
        let (_, a) = screen(task, "player a")
        pause(2)
        let (_, b) = screen(task, "player b")
        let motion = Self.change(a, b)
        report(task, "player", ["motion": motion])
        XCTAssertGreaterThan(motion, 0.001, "the player plays (its picture changes)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        if !wait(5, { !player.exists }) {
            for name in ["Close", "Done"] where app.buttons[name].exists { app.buttons[name].tap(); break }
        }
        XCTAssertTrue(wait(5) { !player.exists }, "the player closes")
        // Share… › Save to Files.
        app.buttons.matching(identifier: "recordingLibraryShare").firstMatch.tap()
        XCTAssertTrue(system.shareSheet("Save to Files"), "Save to Files")
        XCTAssertTrue(system.filesSave(), "saved in \(place) › projectM")
        pause(2)
        noPrompt("library share")
        RecordingCheck.emit(task: task, label: "shared to Files", dir: "Documents", notBefore: began,
                            checks: ["codec": "hvc1", "minDuration": 3])
        // Rename.
        let stem = "QA011 REC010 \(Int(Date().timeIntervalSince1970) % 100_000)"
        app.buttons.matching(identifier: "recordingLibraryRename").firstMatch.tap()
        // A SwiftUI alert's TextField does not carry its accessibility identifier (D3, 2026-11-19: the "Rename
        // Recording" alert's field is an unnamed TextField, placeholder "Name"): the alert's first text field.
        let identified = app.textFields["recordingLibraryRenameField"].firstMatch
        let alertField = app.alerts["Rename Recording"].textFields.firstMatch
        XCTAssertTrue(wait(5) { identified.exists || alertField.exists }, "the rename field")
        let field = identified.exists ? identified : alertField
        // Put the cursor at the end before deleting: a tap in the middle of the field left the old name's tail after
        // the deletes on D2 (pass 4: "QA011 REC010 5258|11-19 at 11.20").
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let old = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + stem)
        XCTAssertEqual((field.value as? String) ?? "", stem, "the rename field holds only the new name")
        // On D2 (pass 4) the alert stayed up after one Rename tap: tap again while it is still shown.
        let renameAlert = app.alerts["Rename Recording"]
        for _ in 0..<3 where renameAlert.exists {
            app.alerts.buttons["Rename"].firstMatch.tap()
            _ = wait(3) { !renameAlert.exists }
        }
        let renamed = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'recordingLibraryRow' AND label CONTAINS %@", stem))
        XCTAssertTrue(wait(5) { renamed.count == 1 }, "the row shows the new name (alert still up: \(renameAlert.exists))")
        // Delete it (its row's Delete; rows are newest first, the renamed one is the first).
        app.buttons.matching(identifier: "recordingLibraryDelete").firstMatch.tap()
        let confirm = app.buttons["recordingLibraryConfirmDelete"].firstMatch
        XCTAssertTrue(wait(5) { confirm.exists }, "Delete asks first")
        confirm.tap()
        XCTAssertTrue(wait(5) { renamed.count == 0 && rows.count == before - 1 }, "the row is gone")
        RecordingCheck.emit(task: task, label: "renamed file deleted", dir: "Library/Application Support/RecordingLibrary",
                            name: "\(stem).mp4", absent: true)
    }
}
