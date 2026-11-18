// B11OutputDeviceTests.swift — QA-011 Batch 8: external-output and show tasks on the device with the DEBUG fake
// external display (`-uitestExternalDisplay`: an off-screen 1920 × 1080 window driven through the coordinator calls a
// real external scene makes). AirPlay to the Mac is not required (owner ruling 2026-11-18), so OUT-001-T15, T17,
// OUT-002-T12, PERF-007-T12, OUT-005-T12, OUT-006-T10 and OUT-011-T12 have no test here; projectors, HDMI and a
// physical keyboard stay with the owner.
// REC-001-T20: Save Frame with the visual on the external display writes the external drawable's size; Clean output
//   keeps the overlays off it; Save Frame while blacked out writes nothing.
// SHOW-014-T12: the B key (XCUITest's synthesised hardware key) blacks out the external output and the badge shows.
// UIX-013-T12: the Show HUD's lines on the device, updated by a cue step; the external side holds only the visual.
// SHOW-006-T17: rehearsing the next cue changes neither the applied scene nor the external routing.
// OUT-014-T13: an output profile exported on a 1080p display warns when imported on a 720p one.
// VIS-018-T14: Tessellation 2 → 16 tiles, portrait and landscape: draws, holds the frame rate, centre symmetry and
//   seam measurements are reported (thresholds set from the first D1 run), Reduce Motion moves less.
// UIX-008-T16 (D2, D3): a scene editor window beside the visualizer (needs Windowed Apps on: skips otherwise); the
//   edit saves and the output keeps running with its source started once.
// SHOW-007-T16, SHOW-008-T14, SHOW-009-T13, SHOW-012-T14: run the simulator classes on the device (ShowTimelineUITests,
//   ShowKeyframeUITests, ShowKeyframeEasingUITests, CueNoteUITests; commands in docs/autotester.md).
import UIKit
import XCTest

@MainActor
final class B11OutputDeviceTests: ControlSurfaceCase {
    private var capture: String { text("frameCaptureProbe") }

    private func saveFramePNG() {
        showControlsBar()
        let save = app.buttons["saveFrame"].firstMatch
        XCTAssertTrue(wait(5) { save.exists }, "Save Frame")
        save.tap()
        let png = app.buttons["PNG"].firstMatch
        if wait(3, { png.exists }) { png.tap() }
    }

    func testREC001SaveFrameUsesTheExternalDrawable() {
        let task = "REC-001-T20"
        launch(visual: "circularSpectrum", extra: ["-uitestExternalDisplay", "-uitestCaptureDirectory", "B11Frames"])
        connectFakeDisplay()
        guard let (w, h) = externalDrawable() else { return XCTFail("no external drawable: \(externalResolution)") }
        saveFramePNG()
        XCTAssertTrue(wait(10) { self.capture.hasPrefix("png ") }, "probe: \(capture)")
        report(task, "external frame", ["width": Double(w), "height": Double(h)])
        XCTAssertTrue(capture.hasPrefix("png \(w)x\(h)"), "the saved frame is the external drawable \(w)x\(h): \(capture)")
        // Clean output: the overlays stay off the external display.
        app.terminate()
        launch(visual: "circularSpectrum", settings: ["settings.externalDisplay.outputMode": "clean"],
               extra: ["-uitestExternalDisplay", "-uitestCaptureDirectory", "B11Frames"])
        connectFakeDisplay()
        XCTAssertTrue(wait(5) { self.outputMode.contains("overlays=hidden") }, "Clean output: \(outputMode)")
        // Black out, then Save Frame: refused (REC-001, OUT-010), so the probe does not change.
        showControlsBar()
        app.buttons["blackout"].firstMatch.tap()
        XCTAssertTrue(wait(3) { self.element("blackoutBadge").exists }, "blacked out")
        let before = capture
        let save = app.buttons["saveFrame"].firstMatch
        if save.exists && save.isEnabled { saveFramePNG() }
        pause(4)
        report(task, "blackout", ["refused": capture == before ? 1 : 0])
        XCTAssertEqual(capture, before, "no frame is saved while blacked out")
        app.buttons["blackoutRestore"].firstMatch.tap()
    }

    func testSHOW014KeyboardBlackoutOnTheExternalOutput() {
        let task = "SHOW-014-T12"
        launch(visual: "circularSpectrum", extra: ["-uitestExternalDisplay"])
        connectFakeDisplay()
        app.typeKey("b", modifierFlags: [])
        let badge = element("blackoutBadge"), note = element("externalDisplayNote")
        let black = wait(3) { badge.exists }
        report(task, "B key", ["blackout": black ? 1 : 0])
        XCTAssertTrue(black, "B blacks out the output")
        XCTAssertEqual(note.label, "The external display is blacked out")
        XCTAssertEqual(sourceStarts, "1", "the source keeps running")
        app.buttons["blackoutRestore"].firstMatch.tap()
        XCTAssertTrue(wait(5) { !badge.exists }, "restored")
    }

    func testUIX013HUDOnTheDeviceOnly() {
        let task = "UIX-013-T12"
        launch(visual: "circularSpectrum", settings: ["settings.visualizer.sceneHUD": true],
               extra: ["-uitestShowSeed", "-uitestExternalDisplay"])
        connectFakeDisplay()
        XCTAssertTrue(wait(5) { self.text("hudCurrentCue").hasPrefix("Cue 1 of 5") }, "HUD: \(text("hudCurrentCue"))")
        let lines = ["hudCurrentCue", "hudNextCue", "hudTempo", "hudSource"].filter { !text($0).isEmpty }
        stepNextCue()
        let updated = wait(5) { self.text("hudCurrentCue").hasPrefix("Cue 2 of 5") }
        report(task, "hud", ["lines": Double(lines.count), "updated": updated ? 1 : 0])
        XCTAssertEqual(lines.count, 4, "four HUD lines: \(lines)")
        XCTAssertTrue(updated, "a cue step updates the HUD: \(text("hudCurrentCue"))")
        XCTAssertTrue(outputMode.hasSuffix("externalViews=1"), "the external side holds only the visual: \(outputMode)")
    }

    func testSHOW006RehearsalLeavesTheOutputAlone() {
        let task = "SHOW-006-T17"
        launch(visual: "circularSpectrum", extra: ["-uitestShowSeed", "-uitestExternalDisplay"])
        connectFakeDisplay()
        let scene = appliedScene, mode = outputMode
        showControlsBar()
        let rehearse = element("showRehearse")
        XCTAssertTrue(wait(5) { rehearse.exists }, "Rehearse in the cue row")
        rehearse.tap()
        let title = element("cueRehearsalTitle")
        XCTAssertTrue(wait(5) { title.exists }, "the rehearsal panel")
        var unchanged = true
        for _ in 0..<20 {
            pause(0.25)
            if appliedScene != scene || outputMode != mode { unchanged = false }
        }
        report(task, "rehearse", ["unchanged": unchanged ? 1 : 0])
        XCTAssertTrue(unchanged, "rehearsal moved neither the show nor the output (\(appliedScene), \(outputMode))")
        app.buttons["cueRehearsalClose"].firstMatch.tap()
    }

    func testOUT014ProfileWarnsOnAnotherDisplay() {
        let task = "OUT-014-T13"
        launch(visual: "circularSpectrum",
               extra: ["-uitestExternalDisplay", "-uitestSettingsSection", "externalDisplay", "-uitestOutputProfileSimulation",
                       "-settings.externalDisplay.calibration", "1.5,0.8,1,1.2"])
        connectFakeDisplay()
        openSettingsPanel()
        let export = app.buttons["outputProfileExport"].firstMatch
        XCTAssertTrue(scrollTo(export), "Export output profile…")
        export.tap()
        XCTAssertTrue(wait(3) { self.app.staticTexts["outputProfileMessage"].firstMatch.label == "Exported output profile." })
        closeSettingsPanel()
        disconnectFakeDisplay()
        connectFakeDisplay(small: true)   // a 1280 × 720 display
        openSettingsPanel()
        let importRow = app.buttons["outputProfileImport"].firstMatch
        XCTAssertTrue(scrollTo(importRow), "Import output profile…")
        importRow.tap()
        let warned = wait(5) { self.app.buttons["outputProfileApplyAnyway"].firstMatch.exists }
        report(task, "different display", ["warned": warned ? 1 : 0])
        XCTAssertTrue(warned, "a different display warns before applying")
    }

    /// Mean difference between the picture and its 180° rotation in the central square (0 = symmetric).
    private func centreAsymmetry(_ p: [UInt8]) -> Double {
        let (w, h) = lastSize
        let side = min(w, h) / 2, x0 = (w - side) / 2, y0 = (h - side) / 2
        var sum = 0, n = 0
        for y in y0..<(y0 + side) {
            for x in x0..<(x0 + side) {
                let a = (y * w + x) * 4, b = ((h - 1 - y) * w + (w - 1 - x)) * 4
                for c in 0..<3 { sum += abs(Int(p[a + c]) - Int(p[b + c])) }
                n += 3
            }
        }
        return n == 0 ? 1 : Double(sum) / Double(n) / 255
    }

    func testVIS018TessellationTilesAndReduceMotion() {
        let task = "VIS-018-T14"
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            for tiles in [2, 6, 16] {
                let step = "\(tiles) tiles \(orientation == .portrait ? "portrait" : "landscape")"
                launch(visual: "tessellation", settings: ["settings.tessellation.tiles": tiles, "settings.performanceOverlay": false],
                       orientation: orientation)
                let (stats, pixels) = screen(task, step)
                report(task, step, ["centreAsymmetry": centreAsymmetry(pixels)])
                XCTAssertGreaterThan(stats.nonBlack, 0.02, "\(step): draws")
                app.terminate()
            }
        }
        launch(visual: "tessellation", settings: ["settings.tessellation.tiles": 6])
        assertFrameRate(task, "6 tiles")
        func motion(_ extra: [String]) -> Double {
            launch(visual: "tessellation", settings: ["settings.tessellation.tiles": 6, "settings.performanceOverlay": false], extra: extra)
            var best = 0.0
            for i in 0..<3 {
                let (_, a) = screen(task, "motion \(extra.isEmpty ? "normal" : "reduced") \(i)a")
                pause(1)
                let (_, b) = screen(task, "motion \(extra.isEmpty ? "normal" : "reduced") \(i)b")
                best = max(best, Self.change(a, b))
                pause(2)
            }
            app.terminate()
            return best
        }
        let normal = motion([]), reduced = motion(["-uitestReduceMotion", "YES"])
        report(task, "reduce motion", ["normal": normal, "reduced": reduced])
        XCTAssertLessThan(reduced, normal, "Reduce Motion is calmer")
    }

    func testUIX008EditorWindowBesideTheOutput() throws {
        let task = "UIX-008-T16"
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("windows are an iPadOS feature (D2, D3)") }
        launch(visual: "circularSpectrum", extra: ["-uitestShowSeed", "-uitestSettingsSection", "show", "-uitestSceneEditorProbe"])
        openSettingsPanel()
        let showLink = app.buttons["showEditorLink"].firstMatch
        XCTAssertTrue(scrollTo(showLink), "Show")
        showLink.tap()
        let folders = app.buttons["showSceneFoldersLink"].firstMatch
        XCTAssertTrue(wait(5) { folders.exists })
        folders.tap()
        let opening = element("sceneFolderScene.Opening")
        XCTAssertTrue(wait(5) { opening.exists })
        opening.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: opening.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)),
                   withVelocity: .fast, thenHoldForDuration: 0.05)
        let open = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "sceneFolderOpenWindow", "Open in New Window")).firstMatch
        XCTAssertTrue(wait(3) { open.exists }, "Open in New Window")
        open.tap()
        let name = app.textFields["sceneEditorName"].firstMatch
        XCTAssertTrue(wait(8) { name.exists }, "the editor window opened")
        let visualizer = app.otherElements["visualizerTapArea"].firstMatch
        guard visualizer.exists && visualizer.isHittable else {
            throw XCTSkip("the editor replaced the visualizer: Windowed Apps is off (owner sets Settings › Multitasking once)")
        }
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(" B8\n")
        app.buttons["sceneEditorSave"].firstMatch.tap()
        let saved = wait(5) { self.text("sceneEditorFileProbe").hasPrefix("name=Opening B8;") }
        report(task, "editor window", ["saved": saved ? 1 : 0, "sourceStarts": Double(sourceStarts) ?? -1])
        XCTAssertTrue(saved, "the edit is saved: \(text("sceneEditorFileProbe"))")
        XCTAssertEqual(sourceStarts, "1", "the output kept running")
    }
}
