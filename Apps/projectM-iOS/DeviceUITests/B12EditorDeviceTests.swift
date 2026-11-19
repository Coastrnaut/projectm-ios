// B12EditorDeviceTests.swift — QA-011 owner session B12 ("Editors and gestures"), the automatable parts on D1 and D2:
// UIX-006 gesture shortcuts (two-finger tap, one-finger tap, lock), UIX-007 the split editor on the iPad (output on the
// left, a layer change seen live, the divider's VoiceOver steps through the DEBUG action probe), UIX-012 the colour
// sampler on a live picture (the written colour against the screenshot, the announcement, escape through the
// accessibility action). Two-finger swipes, three-finger taps and VoiceOver's own gestures cannot be made from XCUITest
// on iOS (it offers taps, two-finger taps, pinch and rotate only) and stay a person's check.
import UIKit
import XCTest

@MainActor
final class B12EditorDeviceTests: B07DeviceCase {
    private func spoken() -> [String] { Array(probe("announcementsProbe").components(separatedBy: "‖").dropFirst()) }

    // MARK: UIX-006

    /// UIX-006-T14 (automated part, D1 and D2): Two-finger tap mapped to Tap tempo with the show seed: four two-finger
    /// taps run the shortcut four times (`gestureShortcutLast` tapTempo:4) without showing the controls and the scene HUD
    /// shows 120 BPM (`-uitestTapInterval 500`); a one-finger tap still shows the controls at once and hides them;
    /// with the scene locked the gesture still works and the Gesture shortcuts section is disabled.
    func testUIX006TwoFingerTapTempoOneFingerAndLock() {
        let task = "UIX-006-T14"
        let mapping = #"{"enabled":true,"mapping":{"twoFingerTap":"tapTempo"}}"#
        launchPlain(["-uitestShowSeed", "-uitestTapInterval", "500", "-uitestSettingsSection", "gestureShortcuts"],
                    settings: ["settings.gestures.shortcuts": mapping, "settings.visualizer.sceneHUD": true])
        hideControls()
        let last = app.staticTexts["gestureShortcutLast"]
        for _ in 0..<4 { tapArea.twoFingerTap(); pause(0.3) }
        XCTAssertTrue(wait(3) { self.value(last) == "tapTempo:4" }, "\(task): four shortcuts ran: \(value(last))")
        XCTAssertFalse(controls.exists, "\(task): the controls stay hidden")
        // The HUD is a container labelled "Show HUD"; its Tempo line (`hudTempo`) carries the reading (D1-D3 read the
        // container's empty value, 2026-11-18).
        let hud = element("hudTempo")
        XCTAssertTrue(wait(3) { hud.exists && (hud.label + " " + self.value(hud)).contains("120") },
                      "\(task): the HUD shows the tapped tempo: \(hud.exists ? hud.label + " " + value(hud) : "no hudTempo")")

        let t0 = Date()
        tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(appears(controls, 2), "\(task): a one-finger tap shows the controls")
        let shown = Date().timeIntervalSince(t0)
        tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(wait(2) { !self.controls.exists }, "\(task): and hides them")

        tapFresh("lockScene")
        XCTAssertTrue(appears(element("sceneLockBadge"), 3), "the scene is locked")
        hideControls()
        tapArea.twoFingerTap()
        XCTAssertTrue(wait(3) { self.value(last) == "tapTempo:5" }, "\(task): the gesture works while locked: \(value(last))")
        openSettings()
        let toggle = app.switches["gestureShortcutsToggle"]
        XCTAssertTrue(appears(toggle, 3) || reveal(toggle), "Settings → Gesture shortcuts")
        XCTAssertFalse(toggle.isEnabled, "\(task): the section is disabled while locked")
        report(task, "gestures", ["shortcutRuns": 5, "controlsShownSeconds": shown])
    }

    // MARK: UIX-007

    private func outputFrame() -> CGRect? {
        let group = value(app.staticTexts["splitOutputFrame"]).split(separator: "|").first
        let parts = group?.split(separator: ",").compactMap { Double($0) } ?? []
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// UIX-007-T13 (D2): quickstart device steps 1, 3 and 5 (steps 2 and 4 are SplitEditorUITests on D2): in landscape
    /// Settings opens beside the output, which stays visible on the left; Layers › Circular Spectrum's opacity lowered to
    /// about 15 % dims the output live; the divider's accessibility increment and decrement (VoiceOver's swipes, through
    /// the DEBUG probe) step between the snap widths.
    func testUIX007SplitEditorOutputLayerLiveAndDividerSteps() throws {
        let task = "UIX-007-T13"
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the split editor is iPad only (UIX-007)") }
        launchPlain(["-uitestSplitEditorWidth", "400", "-uitestAccessibilityActions", "-uitestSeedPhoto", "solid",
                     "-uitestLayerInspectorSeed"], orientation: .landscapeLeft)
        openSettings()
        let pane = element("splitEditorPane")
        XCTAssertTrue(appears(pane, 5), "\(task): Settings in the split editor")
        guard let slot = wait(3, { self.outputFrame() != nil }) ? outputFrame() : nil else { return XCTFail("\(task): the output probe") }
        XCTAssertLessThan(slot.minX, 1, "\(task): the output is on the left: \(slot)")
        XCTAssertLessThanOrEqual(slot.maxX, pane.frame.minX + 1, "\(task): beside Settings, not under it")

        // Step 3: a layer change is visible live.
        func outputLuma(_ label: String) -> Double {
            var sum = 0.0
            for i in 0..<3 {
                let s = shot(task, "\(label) \(i)", step: 2)
                sum += lumaGrid(s, slot.insetBy(dx: slot.width * 0.1, dy: slot.height * 0.1), step: 6).values.reduce(0, +)
                pause(0.3)
            }
            return sum
        }
        // The photo layer (row 1, 80 %), whose picture holds still: the seeded spectrum (row 2, 60 % Screen) follows
        // the reference track, which is silent or quiet here, and lowering it moved the output's luma by 0.4 % on D2
        // and 0.8 % on D3 (2026-11-18) whether or not the change reached the output. Photo at 15 % over black must
        // darken the output by far more than the 2 % noise allowance.
        let before = outputLuma("opacity 80")
        let link = app.buttons["layersLink"]
        XCTAssertTrue(reveal(link), "Layers")
        link.tap()
        let row = app.buttons["layerRow.1"]
        XCTAssertTrue(appears(row, 5), "the Photo layer")
        row.tap()
        let opacity = element("layerControl.opacity")
        XCTAssertTrue(appears(opacity, 5), "the opacity slider")
        dragSlider(opacity, from: 0.8, to: 0.15)
        XCTAssertTrue(wait(5) { self.value(opacity) != "80 percent" }, "the opacity changed: \(value(opacity))")
        let after = outputLuma("opacity lowered")
        report(task, "layer live", ["lumaBefore": before, "lumaAfter": after])
        XCTAssertLessThan(after, before * 0.9, "\(task): the output darkens live with the photo's opacity (\(before) → \(after))")

        // Step 5: the divider's VoiceOver steps.
        let divider = element("splitEditorDivider")
        XCTAssertTrue(appears(divider), "the divider")
        let start = value(divider)
        XCTAssertTrue(accessibilityStep("splitEditorDivider", up: true), "the increment probe")
        XCTAssertTrue(wait(3) { self.value(divider) != start }, "\(task): an increment steps the width: \(value(divider))")
        let up = value(divider)
        XCTAssertTrue(up.contains(", "), "\(task): it lands on a named snap: \(up)")
        // D2 and D3 (2026-11-18): the decrement 0.5 s after the increment left "480 points, Wide". Let the new width
        // settle as a VoiceOver user's next swipe would, and keep the probe's answer (which element it stepped).
        pause(1)
        XCTAssertTrue(accessibilityStep("splitEditorDivider", up: false))
        let answer = value(app.buttons["splitEditorDivider.uitestDecrement"])
        XCTAssertTrue(wait(3) { self.value(divider) == start },
                      "\(task): a decrement steps back: \(value(divider)) (from \(start); probe: \(answer))")
        report(task, "divider", ["stepped": up != start ? 1 : 0])
    }

    // MARK: UIX-012

    /// "red 20%, green 40%, blue 60%" → (0.2, 0.4, 0.6).
    private static func colour(_ text: String) -> (Double, Double, Double)? {
        let n = text.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        guard n.count == 3 else { return nil }
        return (n[0] / 100, n[1] / 100, n[2] / 100)
    }

    /// UIX-012-T13 (automated part, D1; on D2 in the split editor): the eyedropper samples the live Text visual at a
    /// point whose colour holds still between two screenshots; the written colour matches the screenshot there within
    /// ΔE 3 (the readout rounds to whole percent); "<name> set to …" is announced once; a second sampling is cancelled
    /// by the escape accessibility action (VoiceOver's two-finger scrub, through the DEBUG probe) and changes nothing.
    func testUIX012SampleLiveVisualAnnounceAndEscape() {
        let task = "UIX-012-T13"
        launchPlain(["-uitestSeedText", "-uitestAccessibilityActions", "-uitestSettingsSection", "text",
                     "-uitestSettingsSectionOnce", "-uitestSplitEditorWidth", "400"],
                    settings: ["settings.visual": "text"])
        openSettings()
        let eyedropper = app.buttons["eyedropper.textColor"].firstMatch
        XCTAssertTrue(reveal(eyedropper), "the eyedropper by the text Color")
        eyedropper.tap()
        let banner = app.staticTexts["colorSamplingBanner"].firstMatch
        XCTAssertTrue(appears(banner, 5), "sampling mode")
        pause(0.8)   // the sheet's dismissal settles
        let window = app.windows.firstMatch.frame
        let area: CGRect = (UIDevice.current.userInterfaceIdiom == .pad ? outputFrame() : nil)
            ?? window.insetBy(dx: window.width * 0.1, dy: window.height * 0.2)
        let a = shot(task, "before sample a"), b = shot(task, "before sample b")
        var point: CGPoint?
        var y = area.minY + area.height * 0.2
        search: while y < area.maxY - area.height * 0.2 {
            var x = area.minX + area.width * 0.2
            while x < area.maxX - area.width * 0.2 {
                let p = CGPoint(x: x, y: y)
                let c = a.rgb(p)
                let neighbours = [CGPoint(x: x + 3, y: y), CGPoint(x: x, y: y + 3), CGPoint(x: x - 3, y: y)]
                if Self.deltaE(c, b.rgb(p)) < 1, neighbours.allSatisfy({ Self.deltaE(a.rgb($0), c) < 1 }), max(c.0, c.1, c.2) > 0.1 {
                    point = p
                    break search
                }
                x += 9
            }
            y += 9
        }
        guard let point else { return XCTFail("\(task): no still, non-black point in the picture") }
        let expected = b.rgb(point)
        tapPoint(point)
        XCTAssertTrue(appears(app.navigationBars["Settings"], 5), "Settings returns after the sample")
        let again = app.buttons["eyedropper.textColor"].firstMatch
        XCTAssertTrue(reveal(again))
        let written = Self.colour(value(again))
        let dE = written.map { Self.deltaE($0, expected) } ?? 99
        report(task, "sample", ["deltaE": dE, "x": Double(point.x), "y": Double(point.y)])
        XCTAssertLessThan(dE, 3, "\(task): the written colour \(value(again)) matches the picture \(expected)")

        // Escape: a second sampling cancelled by the accessibility action.
        let kept = value(again)
        again.tap()
        XCTAssertTrue(appears(banner, 5), "sampling mode again")
        let escape = app.buttons["colorSamplingLayer.uitestEscape"]
        XCTAssertTrue(appears(escape, 3), "the escape probe")
        escape.tap()
        // The probe leaves with sampling mode: reading its value after that failed the test with "no matches" (D1-D3,
        // 2026-11-18), so the banner is checked first and the probe only while it exists.
        XCTAssertTrue(wait(3) { !banner.exists || (escape.exists && self.value(escape).hasPrefix("performed escape")) },
                      "escape: \(escape.exists ? value(escape) : "probe gone")")
        XCTAssertTrue(wait(5) { !banner.exists }, "\(task): escape ends sampling mode")
        XCTAssertTrue(appears(app.navigationBars["Settings"], 5), "Settings returns")
        let unchanged = app.buttons["eyedropper.textColor"].firstMatch
        XCTAssertTrue(reveal(unchanged))
        XCTAssertEqual(value(unchanged), kept, "\(task): cancelling writes nothing")
        closeSettings()
        let sets = spoken().filter { $0.contains(" set to ") }
        print("UIX012-SPOKEN \(spoken())")
        report(task, "announcement", ["setToAnnouncements": Double(sets.count)])
        XCTAssertEqual(sets.count, 1, "\(task): \"<name> set to …\" announced once: \(spoken())")
    }
}
