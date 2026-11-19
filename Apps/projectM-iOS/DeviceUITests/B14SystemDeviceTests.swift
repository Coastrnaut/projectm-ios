// B14SystemDeviceTests.swift — QA-011 Batch 1: owner-session steps that need iOS's own Settings, driven by SystemUI
// on the device instead of a person. Nothing here raises a permission prompt (owner rule 14): every test runs in
// unattended batches. Each test restores the system settings it changed (SystemUI.restore in tearDown).
// * ACC-001-T12: Reduce Motion turned on in Settings while the app runs: the next controls transition is instant
//   without a relaunch (the `motionProbe`), labels unchanged.
// * ACC-003-T17: Color Filters (Grayscale) and Increase Contrast, quickstart D1 steps 1-3, 5, 6: the app sees
//   Increase Contrast (`statusAppearanceProbe`), every status keeps its words and symbol state, contrast audit.
//   Colour filters act on the display, after the screenshot; the assertions read the app's own state.
// * ACC-008-T16: the overlay text's contrast measured in screenshots over bright pictures (a near-white photo and
//   six projectM presets), standard and with Increase Contrast: at least 4.5:1.
// UIX-014-T12 (Help with Airplane Mode on) needs the USB cable: not required (owner ruling 2026-11-18).
import UIKit
import XCTest

@MainActor
final class B14SystemDeviceTests: DeviceAcceptanceCase {
    private lazy var system = SystemUI(app: app)

    override func tearDown() async throws {
        system.restore()
        try await super.tearDown()
    }

    // MARK: Helpers

    private func value(_ id: String) -> String { (app.staticTexts[id].value as? String) ?? "" }
    /// RenderPlaceholder.note.
    private static let placeholderNote = "Visual unavailable"
    private var area: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }
    private var controls: XCUIElement { app.otherElements["controls"] }

    private func showControls() {
        if controls.exists { return }
        area.tap()
        if !wait(2, { self.controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { self.controls.exists }, "the controls are shown")
    }

    private func hideControls() {
        if controls.exists { area.tap() }
        _ = wait(3) { !self.controls.exists }
    }

    /// Taps the picture once; returns the controls transition the probe reports for that change.
    private func toggleControlsTransition() -> String {
        let wasShown = controls.exists
        area.tap()
        XCTAssertTrue(wait(5) { self.controls.exists != wasShown }, "the controls toggled")
        pause(0.5)
        let probe = value("motionProbe")
        return probe.components(separatedBy: "controls=").last ?? ""
    }

    private func controlLabels() -> [String] {
        ["settings", "stop", "pauseResume"].map { app.buttons[$0].exists ? app.buttons[$0].label : "-" }
    }

    // MARK: ACC-001-T12

    /// Reduce Motion turned on in Settings while the app runs: the very next controls transition is instant
    /// (0.00 s; 0.20 s before), with no relaunch, and the controls' VoiceOver labels are the same before and after.
    func testACC001LiveReduceMotionToggle() {
        let task = "ACC-001-T12"
        // `-uitestReduceMotion system`: the real setting, with the probe panel (`motionProbe` exists only with the
        // argument; without it the test found no probe on D1-D3, 2026-11-18).
        launch(visual: "circularSpectrum", settings: ["settings.performanceOverlay": false],
               extra: ["-uitestReduceMotion", "system"], music: false)
        XCTAssertTrue(wait(10) { self.value("motionProbe").hasPrefix("reduce=") }, "the motion probe")
        if value("motionProbe").hasPrefix("reduce=on") {   // start from off
            system.toggleAccessibility(.reduceMotion, on: false)
            XCTAssertTrue(wait(5) { self.value("motionProbe").hasPrefix("reduce=off") }, value("motionProbe"))
        }
        let launches = app.state == .runningForeground ? 1 : 0
        showControls()
        let labelsBefore = controlLabels()
        hideControls()
        let before = toggleControlsTransition()
        XCTAssertEqual(before, "0.20", "Reduce Motion off: the controls fade")

        system.toggleAccessibility(.reduceMotion, on: true)
        XCTAssertTrue(wait(5) { self.value("motionProbe").hasPrefix("reduce=on") },
                      "the app follows the system change at once: \(value("motionProbe"))")
        hideControls()
        let after = toggleControlsTransition()
        XCTAssertEqual(after, "0.00", "Reduce Motion on: the next transition is instant")
        showControls()
        XCTAssertEqual(controlLabels(), labelsBefore, "VoiceOver labels unchanged")
        XCTAssertEqual((app.staticTexts["visualRunning"].value as? String), "yes", "the visual keeps drawing")
        report(task, "live toggle", ["beforeSeconds": Double(before) ?? -1, "afterSeconds": Double(after) ?? -1,
                                     "relaunched": launches == 1 ? 0 : 1])
    }

    // MARK: ACC-003-T17

    /// Grayscale and Increase Contrast on (quickstart D1 step 1), then steps 2, 3, 5 and 6: every status keeps its
    /// words and its symbol state; the badges use the opaque Increase Contrast background (the probe).
    /// 2026-11-19 (pass 3, D3): the step 6 audit ran while the controls faded out (they were hidden in the audit's
    /// screenshot) and reported the PERF-014 placeholder "Visual unavailable" behind the live visual plus three
    /// findings without an element. The controls stay up now (`-uitestKeepControls`, as VoiceOver keeps them), and the
    /// placeholder is filtered with the reason the simulator audits give (AccessibilityScreensUITests, "controls").
    func testACC003GrayscaleIncreaseContrast() throws {
        let task = "ACC-003-T17"
        system.toggleAccessibility(.grayscale, on: true)
        system.toggleAccessibility(.increaseContrast, on: true)
        launch(visual: "circularSpectrum", extra: ["-uitestAppearance", "dark", "-uitestKeepControls"])
        XCTAssertTrue(wait(5) { self.value("statusAppearanceProbe").hasPrefix("contrast:increased") },
                      "the app sees Increase Contrast: \(value("statusAppearanceProbe"))")
        XCTAssertTrue(wait(5) { self.value("overlaySurfaceProbe") == "scrim:1.00" }, "opaque overlays (ACC-008-R6)")
        let indicator = app.staticTexts["sourceIndicator"]
        XCTAssertTrue(indicator.exists, "the source indicator")
        let active = indicator.label
        XCTAssertTrue(active.hasPrefix("In-App Playback · "), "step 2: words: \(active)")
        _ = screen(task, "active")

        // Step 2: pause the track (the transport's play/pause; `pauseResume` freezes only the picture, so the source
        // kept "Active audio" on D1-D3, 2026-11-18): the indicator's words change (not only its colour).
        showControls()
        app.buttons["transportPlayPause"].tap()
        XCTAssertTrue(wait(8) { indicator.label != active }, "step 2: paused changes the words: \(indicator.label)")
        report(task, "pause", ["labelChanged": indicator.label != active ? 1 : 0])
        print("ACC003 indicator active=\(active) paused=\(indicator.label)")
        showControls()
        app.buttons["transportPlayPause"].tap()
        XCTAssertTrue(wait(8) { indicator.label.hasPrefix("In-App Playback · ") }, "resumed: \(indicator.label)")

        // Step 3: record a few seconds and stop.
        showControls()
        app.buttons["record"].tap()
        let recording = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(wait(5) { recording.exists && recording.label.hasPrefix("Recording") }, "step 3: \(recording.label)")
        pause(2)
        showControls()
        app.buttons["record"].tap()
        let discard = app.buttons["recordingResultDiscard"]
        XCTAssertTrue(wait(15) { discard.exists }, "step 3: the recording finished")
        _ = screen(task, "recording ready")
        discard.tap()

        // Step 5: black out and restore (the badge says so in words).
        showControls()
        app.buttons["blackout"].tap()
        let badge = app.staticTexts["blackoutBadgeText"]
        XCTAssertTrue(wait(5) { badge.exists }, "step 5: the blackout badge")
        _ = screen(task, "blackout")
        let restore = app.buttons["blackoutRestore"]
        if restore.exists { restore.tap() } else { showControls(); app.buttons["blackout"].tap() }
        XCTAssertTrue(wait(5) { !badge.exists }, "step 5: restored")

        // Step 6: the controls and badges with Increase Contrast pass the contrast audit.
        // Pass 4 (D2 2026-11-19): the audit ran while the 4 s "Output restored" caption (ACC-011) still sat under the
        // performance readout at the top, so the readout's "frame … ms" line was measured over the caption's text.
        // Audit once the caption is gone, and after the controls' fade has settled.
        let caption = app.staticTexts["statusCaption"]
        XCTAssertTrue(wait(8) { !caption.exists }, "the transient caption clears: \(caption.exists ? caption.label : "")")
        showControls()
        pause(1)
        // The PERF-014 placeholder: caught while fading (opacity < 1) or hidden behind the live visual; at full opacity
        // its grey 0.55 on black is about 6:1 (the simulator audits' documented filter).
        let issues = auditIssues(app, "acc003 controls", types: [.contrast])
            .filter { !$0.contains("label=\"\(Self.placeholderNote)\"") }
        report(task, "contrast audit", ["issues": Double(issues.count)])
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    // MARK: ACC-008-T16

    /// WCAG contrast of the brightest and the median luminance inside `element`'s frame (text over its backing),
    /// from a full-resolution screenshot.
    private func contrastRatio(_ element: XCUIElement, _ label: String) -> Double {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let cg = shot.image.cgImage, element.exists else { return 0 }
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(cg.width) / max(1, window.width)
        let frame = element.frame.insetBy(dx: -2, dy: -2)
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard !rect.isEmpty, let crop = cg.cropping(to: rect) else { return 0 }
        let pixels = Self.rgba(UIImage(cgImage: crop), step: 1)
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var luminance: [Double] = []
        luminance.reserveCapacity(pixels.count / 4)
        for i in stride(from: 0, to: pixels.count - 3, by: 4) {
            luminance.append(0.2126 * linear(pixels[i]) + 0.7152 * linear(pixels[i + 1]) + 0.0722 * linear(pixels[i + 2]))
        }
        guard !luminance.isEmpty else { return 0 }
        luminance.sort()
        let low = luminance[luminance.count * 3 / 100], mid = luminance[luminance.count / 2]
        let high = luminance[min(luminance.count - 1, luminance.count * 97 / 100)]
        // Text lighter than its backing (the overlays are dark, ACC-008-R4), or darker.
        return max((high + 0.05) / (mid + 0.05), (mid + 0.05) / (low + 0.05))
    }

    private func measureOverlays(_ task: String, _ step: String) -> Double {
        let indicator = app.staticTexts["sourceIndicator"]
        XCTAssertTrue(wait(5) { indicator.exists }, "\(step): the source indicator")
        // The indicator fades in (opacity transition) as the controls hide; measured mid-fade right after launch it
        // read 1.39 (D2) and 3.27 (D3) at preset 0 while every settled reading passed (2026-11-18). Measure it settled.
        pause(1)
        let ratio = contrastRatio(indicator, "\(task) \(step)")
        report(task, step, ["contrast": ratio])
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(step): the overlay text keeps 4.5:1 over the picture")
        return ratio
    }

    /// The overlay over a near-white photo and over six projectM presets, standard and with Increase Contrast.
    func testACC008OverlayContrastOverBrightPresets() {
        let task = "ACC-008-T16"
        for increased in [false, true] {
            if increased { system.toggleAccessibility(.increaseContrast, on: true) }
            let mode = increased ? "increased" : "standard"
            launch(visual: "photo", settings: ["settings.performanceOverlay": false], extra: ["-uitestSeedPhoto", "bright"],
                   music: false)
            XCTAssertTrue(wait(5) { self.value("overlaySurfaceProbe") == (increased ? "scrim:1.00" : "scrim:0.84") },
                          "\(mode): \(value("overlaySurfaceProbe"))")
            var worst = measureOverlays(task, "\(mode) bright photo")
            app.terminate()
            launch(visual: "projectM", settings: ["settings.performanceOverlay": false])
            for n in 0..<6 {
                if n > 0 {
                    showControls()
                    app.buttons["next"].tap()
                    hideControls()
                    pause(3)   // the preset's blend
                }
                worst = min(worst, measureOverlays(task, "\(mode) preset \(n)"))
            }
            report(task, "\(mode) worst", ["contrast": worst])
            app.terminate()
        }
    }
}
