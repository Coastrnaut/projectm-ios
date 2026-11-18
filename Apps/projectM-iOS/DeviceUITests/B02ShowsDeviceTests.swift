// B02ShowsDeviceTests.swift — QA-011 owner session B02 ("Shows, presets, scenes and everyday controls"), the parts
// the existing simulator UI tests do not cover, automated on the device. VIS-001-T36: the Circular Spectrum with the
// reference track through rotation, background and return, and Reduce flashing: the overlay frame rate, the visual
// drawing and moving, no crash, and the native-visual fallback never shown. Lock and unlock (a person's step)
// stays with the owner.
import UIKit
import XCTest

@MainActor
final class B02ShowsDeviceTests: DeviceAcceptanceCase {
    private var circular: XCUIElement { app.descendants(matching: .any)["circularSpectrum"].firstMatch }
    private var fallbackShown: Bool { app.staticTexts["nativeVisualUnavailable"].exists }

    private func assertStillCircular(_ step: String) {
        XCTAssertTrue(wait(10) { self.circular.exists }, "\(step): the Circular Spectrum is shown")
        XCTAssertFalse(fallbackShown, "\(step): the fallback notice never shows")
        XCTAssertEqual(app.state, .runningForeground, "\(step): no crash")
    }

    /// PERF-011-T22 (automatable part): background, rotate while away, return: the visual draws again in the new
    /// orientation, timed from the return to the overlay's first non-zero frame rate. The app switcher card and Control
    /// Center: testPERF011SwitcherCardAndControlCenter; lock and unlock stay a person's step.
    func testPERF011ReturnAfterRotationWhileAway() {
        let task = "PERF-011-T22"
        launch(visual: "circularSpectrum")
        assertFrameRate(task, "before")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(wait(10) { self.app.state != .runningForeground }, "in the background")
        XCUIDevice.shared.orientation = .landscapeLeft   // rotated while away
        pause(3)
        let t0 = Date()
        app.activate()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground }, "back")
        let drawing = wait(10) { (self.overlayFPS() ?? 0) > 0 }
        let seconds = Date().timeIntervalSince(t0)
        let window = app.windows.firstMatch.frame
        report(task, "return", ["secondsToFirstFrameReading": seconds, "landscape": window.width > window.height ? 1 : 0])
        XCTAssertTrue(drawing, "the visual draws again after the return")
        XCTAssertGreaterThan(window.width, window.height, "the window follows the rotation made while away")
        assertStillCircular("after the return")
        assertFrameRate(task, "after the return")
        assertDrawingAndMoving(task, "after the return")
    }

    /// PERF-011-T22 (QA-011 Batch 1, SystemUI): the app switcher card shows the picture (not black), the return from
    /// the switcher draws again (timed to the first non-zero overlay reading), and Control Center over the running
    /// app costs nothing once dismissed. Lock and unlock stay a person's step (no API).
    func testPERF011SwitcherCardAndControlCenter() {
        let task = "PERF-011-T22"
        let system = SystemUI(app: app)
        launch(visual: "circularSpectrum")
        assertFrameRate(task, "before")

        system.openAppSwitcher()
        let (card, _) = screen(task, "app switcher")
        let cardListed = system.appSwitcherCard.exists
        report(task, "switcher", ["cardNonBlack": card.nonBlack, "cardListed": cardListed ? 1 : 0,
                                  "appState": Double(app.state.rawValue)])
        XCTAssertGreaterThan(card.nonBlack, 0.05, "the switcher shows the app's card with its picture, not black")
        let t0 = Date()
        system.returnFromAppSwitcher()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground }, "back from the switcher")
        let drawing = wait(10) { (self.overlayFPS() ?? 0) > 0 }
        report(task, "switcher return", ["secondsToFirstFrameReading": Date().timeIntervalSince(t0)])
        XCTAssertTrue(drawing, "the visual draws again after the switcher")
        assertStillCircular("after the switcher")
        assertDrawingAndMoving(task, "after the switcher")

        XCTAssertTrue(system.openControlCenter(), "Control Center opens over the app")
        pause(2)
        _ = screen(task, "control center")
        system.closeControlCenter()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground }, "back from Control Center")
        assertStillCircular("after Control Center")
        assertFrameRate(task, "after Control Center")
        assertDrawingAndMoving(task, "after Control Center")
    }

    /// VIS-001-T36: rotate, background/return, Reduce flashing; overlay frame rate; no crash, no fallback.
    func testVIS001CircularSpectrumRotationBackgroundReduceFlashing() {
        let task = "VIS-001-T36"
        launch(visual: "circularSpectrum")
        assertStillCircular("portrait")
        assertFrameRate(task, "portrait")
        assertDrawingAndMoving(task, "portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertStillCircular("landscape")
        assertFrameRate(task, "landscape")
        assertDrawingAndMoving(task, "landscape")
        XCUIDevice.shared.orientation = .portrait
        pause(2)

        // Background and return, as from the Home Screen.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(wait(10) { self.app.state != .runningForeground }, "the app went to the background")
        pause(3)
        app.activate()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground }, "back in the foreground")
        assertStillCircular("after background")
        // Playing In-App Playback is paused while away and resumes on a real return (AUD-006-R22, AUD-015-R5); the
        // visual moves with the music only once audio is active again. The overlay's status line is live state.
        let returned = Date()
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        let resumed = wait(15) { overlay.label.contains("Active audio") }
        report(task, "audio after background", ["resumed": resumed ? 1 : 0, "seconds": Date().timeIntervalSince(returned)])
        print("VIS001-OVERLAY \(overlay.label.prefix(300))")
        XCTAssertTrue(resumed, "playback resumes after the return: \(overlay.label.prefix(160))")
        _ = wait(8) { !self.app.otherElements["controls"].exists }   // screenshots need the controls hidden
        assertFrameRate(task, "after background")
        // Three motion samples over about 15 s: a slow recovery and a frozen visual look different.
        var motions: [Double] = []
        for i in 0..<3 {
            let (_, a) = screen(task, "after background \(i) a")
            pause(1)
            let (_, b) = screen(task, "after background \(i) b")
            motions.append(Self.change(a, b))
            if i < 2 { pause(4) }
        }
        report(task, "after background motion", ["first": motions[0], "second": motions[1], "third": motions[2],
                                                 "controlsShown": app.otherElements["controls"].exists ? 1 : 0])
        XCTAssertGreaterThan(motions.max() ?? 0, 0.002, "after background: the visual moves with the music \(motions)")
        report(task, "background", ["returned": app.state == .runningForeground ? 1 : 0,
                                    "fallbackShown": fallbackShown ? 1 : 0])
        app.terminate()

        launch(visual: "circularSpectrum", settings: ["settings.reduceFlashing": true])
        assertStillCircular("Reduce flashing")
        assertFrameRate(task, "Reduce flashing on")
        assertDrawingAndMoving(task, "Reduce flashing on")
    }
}

/// FX-002-T18: a glowing spectrum over a bright photo. Tone mapping keeps colours above 1 in range: no broken pixels
/// (a non-finite colour maps to black, FX-002-R2, so black specks on a near-white photo are the failure) and the frame
/// rate as with the glow off. The screenshots are attached for the look (hue).
@MainActor
final class B02ToneMappingDeviceTests: DeviceAcceptanceCase {
    /// Fraction of near-black samples (luma below 0.05) in a fraction rectangle of the last screenshot.
    private func darkFraction(_ p: [UInt8], _ r: (Double, Double, Double, Double)) -> Double {
        1 - Self.region(p, width: lastSize.0, height: lastSize.1, r).nonBlack
    }

    func testFX002GlowingSpectrumOverABrightPhoto() {
        let task = "FX-002-T18"
        sampleStep = 2
        // Below the overlay (top) and above the status pill (bottom): the photo with the spectrum over it.
        let body = (0.0, 0.3, 1.0, 0.45)
        var results: [String: Double] = [:]
        for glow in [false, true] {
            launch(visual: "photo", settings: ["settings.circularSpectrum.glow": glow,
                                               "settings.circularSpectrum.glowRadius": 0.06],
                   extra: ["-uitestSeedPhoto", "bright"])
            let label = glow ? "glow on, maximum radius" : "glow off"
            let fps = assertFrameRate(task, label)
            var dark = 0.0
            for i in 0..<3 {
                let (_, p) = screen(task, "\(label) \(i)")
                dark = max(dark, darkFraction(p, body))
                pause(1)
            }
            report(task, label, ["darkFraction": dark])
            results[glow ? "fpsOn" : "fpsOff"] = fps
            results[glow ? "darkOn" : "darkOff"] = dark
            XCTAssertLessThan(dark, 0.01, "\(label): no broken (black) pixels over the bright photo")
            app.terminate()
        }
        report(task, "glow cost", ["offMinusOn": (results["fpsOff"] ?? 0) - (results["fpsOn"] ?? 0)])
        XCTAssertLessThanOrEqual((results["fpsOff"] ?? 0) - (results["fpsOn"] ?? 0), Self.effectToleranceFPS,
                                 "the frame rate with the glow is as before")
    }
}

/// QA-011 Batch 7: FX-002's hue part (a glowing spectrum over a bright photo keeps its colour where it clips).
@MainActor
final class B02ToneMappingHueDeviceTests: B07DeviceCase {
    /// FX-002-T18 (hue): the spectrum's coloured pixels (chroma over 0.15) in the photo body keep their hue with the glow
    /// at maximum radius: the circular mean hue moves by less than 10° against the glow off, also among the brightest
    /// (luma over 0.85) glow pixels, where hue-shifted clipping would show.
    func testFX002GlowKeepsTheSpectrumHue() {
        let task = "FX-002-T18"
        var hues: [Bool: [Double]] = [:], bright: [Double] = []
        for glow in [false, true] {
            launch(visual: "photo", settings: ["settings.circularSpectrum.glow": glow, "settings.circularSpectrum.glowRadius": 0.06],
                   extra: ["-uitestSeedPhoto", "bright"])
            assertFrameRate(task, glow ? "glow on" : "glow off", seconds: 6)
            var list: [Double] = []
            for i in 0..<3 {
                let s = shot(task, "\(glow ? "glow" : "plain") hue \(i)", step: 4)
                let w = app.windows.firstMatch.frame
                var y = w.height * 0.3
                while y < w.height * 0.75 {
                    var x: CGFloat = 0
                    while x < w.width {
                        let c = s.rgb(CGPoint(x: x, y: y))
                        let (h, chroma) = Self.hueChroma(c.0, c.1, c.2)
                        if chroma > 0.15 {
                            list.append(h)
                            if glow, 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 > 0.85 { bright.append(h) }
                        }
                        x += 3
                    }
                    y += 3
                }
                pause(1)
            }
            hues[glow] = list
            app.terminate()
        }
        let off = Self.circularMean(hues[false] ?? []), on = Self.circularMean(hues[true] ?? [])
        let brightMean = Self.circularMean(bright)
        let difference = Self.angleDifference(off, on), brightDifference = Self.angleDifference(off, brightMean)
        report(task, "hue", ["offHue": off, "onHue": on, "difference": difference, "brightSamples": Double(bright.count),
                             "brightDifference": brightDifference, "offSamples": Double(hues[false]?.count ?? 0)])
        XCTAssertGreaterThan(hues[false]?.count ?? 0, 50, "\(task): the spectrum's colours are on screen")
        XCTAssertLessThan(difference, 10, "\(task): the glow keeps the spectrum's hue")
        if bright.count >= 20 { XCTAssertLessThan(brightDifference, 10, "\(task): no hue shift where it clips") }
    }
}

/// QA-011 Batch 7: the strobe safety envelope on projectM (FX-019), the beat grid (SHOW-010), scene rotation
/// (SHOW-013) and the preset comparison (PRE-009) on the device. Probes: `-uitestVisualProbes` (UITestVisualProbes).
@MainActor
final class B02ShowsProbeDeviceTests: B07DeviceCase {
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    private func dismissImportAlert() {
        let alert = app.alerts["Import Preset"]
        if alert.exists { alert.buttons["OK"].firstMatch.tap() }
    }

    /// FX-019-T23: with Reduce flashing off, an ordinary preset is never clamped (gain 1: the picture is as without the
    /// envelope), and the strobing fixture (`-uitestImportPreset fixture:strobe`, ACC-002's high-flash preset) is: the
    /// envelope's sampled gain drops below 0.98 within a few seconds of it playing. D1 and D3.
    func testFX019StrobeClampedOrdinaryUnchanged() {
        let task = "FX-019-T23"
        launchProbed(visual: "projectM", settings: ["settings.reduceFlashing": false],
                     extra: ["-uitestImportPreset", "fixture:strobe"])
        dismissImportAlert()
        pause(4)
        let ordinary = probe("flashGuardProbe")
        let ordinaryPreset = probe("presetFlashProbe")
        let ordinaryFPS = assertFrameRate(task, "ordinary preset (probe on)", seconds: 6, minimum: 0)
        report(task, "ordinary", ["recentClamped": Self.number(ordinary, "recentClamped") ?? -1,
                                  "recentSampled": Self.number(ordinary, "recentSampled") ?? -1,
                                  "recentMin": Self.number(ordinary, "recentMin") ?? -1, "fps": ordinaryFPS])
        print("FX019-ORDINARY \(ordinaryPreset) \(ordinary)")
        XCTAssertTrue(ordinary.contains("source=projectM"), "\(task): projectM's envelope is sampled: \(ordinary)")
        XCTAssertGreaterThan(Self.number(ordinary, "recentSampled") ?? 0, 5, "\(task): gains sampled")
        XCTAssertEqual(Self.number(ordinary, "recentClamped"), 0, "\(task): the ordinary preset is not clamped: \(ordinary)")

        // Play the fixture from My Presets.
        tapFresh("presets")
        XCTAssertTrue(appears(app.buttons["node:included"], 10), "library home")
        let myPresets = app.buttons["node:myPresets"]
        XCTAssertTrue(reveal(myPresets), "My Presets")
        myPresets.tap()
        let row = app.buttons["preset:Strobe"]
        XCTAssertTrue(wait(30) { self.dismissImportAlert(); return row.exists }, "the imported fixture is listed")
        row.tap()
        let warning = app.alerts["May flash"]
        if appears(warning, 3) { warning.buttons["Load Anyway"].firstMatch.tap() }
        XCTAssertTrue(wait(15) { self.probe("presetFlashProbe").hasPrefix("name=Strobe|") }, "the fixture plays: \(probe("presetFlashProbe"))")
        _ = wait(8) { !self.controls.exists }
        var strobe = ""
        let clamped = wait(12) {
            strobe = self.probe("flashGuardProbe")
            return (Self.number(strobe, "recentClamped") ?? 0) > 0
        }
        let strobeFPS = Self.median(sampleFPS(seconds: 6))
        screen(task, "strobe clamped")
        print("FX019-STROBE \(probe("presetFlashProbe")) \(strobe)")
        report(task, "strobe", ["recentClamped": Self.number(strobe, "recentClamped") ?? -1,
                                "recentMin": Self.number(strobe, "recentMin") ?? -1, "fps": strobeFPS])
        XCTAssertTrue(clamped, "\(task): the envelope clamps the strobing preset with Reduce flashing off: \(strobe)")
        XCTAssertLessThan(Self.number(strobe, "minGain") ?? 1, ANGLEDebugFlashStatsLimit.clampedBelow, "\(task): gain below 0.98")
    }

    /// SHOW-010-T12: four taps 500 ms apart (`-uitestTapInterval 500`: 120 BPM, tap tempo) on the SHOW-007 timeline
    /// seed (2:30): the drawn grid has a tick every 0.5 s (`showBeatGridProbe`), and while the show plays the readout's
    /// beat advances every 0.5 s and its bar every 2 s (readout sampled every 0.1 s for 9 s).
    func testSHOW010BeatGridTicks() {
        let task = "SHOW-010-T12"
        launchPlain(["-uitestShowSeed", "-uitestShowTimelineSeed", "-uitestKeepControls", "-uitestTapInterval", "500",
                     "-uitestBeatGridProbe"])
        showControls()
        let tap = app.buttons["tapTempo"]
        XCTAssertTrue(appears(tap), "Tap tempo")
        for _ in 0..<4 { tap.tap() }
        let readout = app.staticTexts["showBeatGridReadout"]
        XCTAssertTrue(appears(readout), "the beat grid readout")
        XCTAssertTrue(wait(5) { self.value(readout).hasPrefix("120 BPM, tap tempo") }, "tapped 120 BPM: \(value(readout))")
        let ticks = app.staticTexts["showBeatGridProbe"].label   // "ticks N bars M"
        let parts = ticks.split(separator: " ")
        let tickCount = parts.count == 4 ? Double(parts[1]) ?? 0 : 0, barCount = parts.count == 4 ? Double(parts[3]) ?? 0 : 0
        // Beats over the 150 s timeline: the ticks, or the ticks plus the bar lines when bars are drawn separately.
        let spacing = [150 / max(tickCount, 1), 150 / max(tickCount + barCount, 1)].min { abs($0 - 0.5) < abs($1 - 0.5) } ?? 0
        let play = app.buttons["showTimelinePlay"]
        func position(_ text: String) -> (bar: Int, beat: Int)? {
            guard let r = text.range(of: #"bar [0-9]+ beat [0-9]+"#, options: .regularExpression) else { return nil }
            let n = text[r].split(separator: " ")
            return (Int(n[1]) ?? 0, Int(n[3]) ?? 0)
        }
        let first = position(value(readout))
        pause(1)
        let moved: Bool = {
            guard let a = first, let b = position(value(readout)) else { return false }
            return a.bar != b.bar || a.beat != b.beat
        }()
        if !moved, play.exists { play.tap() }   // start the timeline
        var beatTimes: [Double] = [], barTimes: [Double] = []
        var last = position(value(readout))
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 9 {
            pause(0.1)
            guard let now = position(value(readout)) else { continue }
            let t = Date().timeIntervalSince(t0)
            if let l = last, now.bar != l.bar || now.beat != l.beat { beatTimes.append(t) }
            if let l = last, now.bar != l.bar { barTimes.append(t) }
            last = now
        }
        let beatIntervals = zip(beatTimes, beatTimes.dropFirst()).map { $1 - $0 }
        let barIntervals = zip(barTimes, barTimes.dropFirst()).map { $1 - $0 }
        report(task, "grid", ["ticks": tickCount, "bars": barCount, "tickSpacing": spacing,
                              "beatMedian": Self.median(beatIntervals), "barMedian": Self.median(barIntervals),
                              "beats": Double(beatTimes.count), "barChanges": Double(barTimes.count)])
        XCTAssertEqual(spacing, 0.5, accuracy: 0.02, "\(task): a tick every 0.5 s (\(ticks))")
        XCTAssertGreaterThanOrEqual(beatTimes.count, 12, "\(task): the readout counts beats while the show plays")
        XCTAssertEqual(Self.median(beatIntervals), 0.5, accuracy: 0.05, "\(task): a beat every 0.5 s \(beatIntervals)")
        XCTAssertEqual(Self.median(barIntervals), 2.0, accuracy: 0.15, "\(task): a bar every 2 s \(barIntervals)")
    }

    /// Scene changes (time, scene ID) of `showAppliedScene`, polled every 0.1 s for `seconds`.
    private func sceneChanges(seconds: Double) -> [(Double, String)] {
        var changes: [(Double, String)] = []
        var last = String(probeScene().prefix(36))
        let t0 = Date()
        while Date().timeIntervalSince(t0) < seconds {
            pause(0.1)
            let now = String(probeScene().prefix(36))
            if !now.isEmpty, now != last { changes.append((Date().timeIntervalSince(t0), now)); last = now }
        }
        return changes
    }

    private func probeScene() -> String { probe("showAppliedScene") }

    /// SHOW-013-T13: the five-scene show seed with scene 3 disabled, Bars 4 at 120 BPM (ANL-006's `-uitestTempoEstimate
    /// 120:0.9`; the music fixture is 120 BPM): scenes change every 8 s (± 0.3 s, a multiple of the bar), never to the
    /// scene shown, never to the disabled scene; then Timer 15 s rotates every 15 s. Rotation is switched on by
    /// `-uitestSceneRotation` (seed 1).
    func testSHOW013RotationOnTheBarAndTimer() {
        let task = "SHOW-013-T13"
        let disabled = Self.sceneID(3)
        launchPlain(["-uitestShowSeed", "-uitestTempoEstimate", "120:0.9", "-uitestSceneRotation", "15"],
                    settings: ["settings.show.rotation": ["$json": ["mode": "bars", "bars": 4, "disabledSceneIDs": [disabled]]]])
        let bars = sceneChanges(seconds: 34)
        let barIntervals = zip(bars, bars.dropFirst()).map { $1.0 - $0.0 }
        print("SHOW013-BARS \(bars)")
        report(task, "bars 4", ["changes": Double(bars.count), "intervalMedian": Self.median(barIntervals),
                                "intervalMin": barIntervals.min() ?? 0, "intervalMax": barIntervals.max() ?? 0])
        XCTAssertGreaterThanOrEqual(bars.count, 3, "\(task): rotation changes scenes on the bar")
        for interval in barIntervals { XCTAssertEqual(interval, 8, accuracy: 0.3, "\(task): every 4 bars (8 s): \(barIntervals)") }
        XCTAssertFalse(bars.contains { $0.1 == disabled }, "\(task): the disabled scene never shows")
        XCTAssertFalse(zip(bars, bars.dropFirst()).contains { $0.1 == $1.1 }, "\(task): never the scene already shown")
        app.terminate()

        launchPlain(["-uitestShowSeed", "-uitestSceneRotation", "15"],
                    settings: ["settings.show.rotation": ["$json": ["mode": "timer", "intervalSeconds": 15]]])
        let timer = sceneChanges(seconds: 33)
        let timerIntervals = zip(timer, timer.dropFirst()).map { $1.0 - $0.0 }
        report(task, "timer 15 s", ["changes": Double(timer.count), "intervalMedian": Self.median(timerIntervals)])
        XCTAssertGreaterThanOrEqual(timer.count, 2, "\(task): Timer 15 s rotates")
        for interval in timerIntervals { XCTAssertEqual(interval, 15, accuracy: 0.5, "\(task): every 15 s: \(timerIntervals)") }
    }

    /// PRE-009-T13: a 60 s comparison of two Calm presets with music: the previews run near their rate
    /// (`compareProbe`: at least 85 % of 30 frames/s, or of 15 under Low Power or a serious thermal state), the thermal
    /// state stays at fair or below, and after Close the main visual draws and moves again.
    func testPRE009SixtySecondComparison() {
        let task = "PRE-009-T13"
        launchProbed(visual: "projectM", extra: ["-uitestSeedPresetTags", "Calm:0,1,2"])
        let current = app.staticTexts["currentPreset"].exists ? app.staticTexts["currentPreset"].label : ""
        tapFresh("presets")
        let chip = app.buttons["presetTagChip.Calm"]
        XCTAssertTrue(appears(chip, 10), "the Calm chip")
        if !chip.isSelected { chip.tap() }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'"))
        XCTAssertTrue(wait(5) { rows.count >= 3 }, "three Calm presets")
        let names = rows.allElementsBoundByIndex.map { String($0.identifier.dropFirst("preset:".count)) }.filter { $0 != current }
        guard names.count >= 2 else { return XCTFail("\(task): two Calm presets to compare: \(names)") }
        func menu(_ name: String, _ title: String) {
            app.buttons["preset:\(name)"].press(forDuration: 0.7)
            let item = app.buttons[title]
            XCTAssertTrue(appears(item), "\(title) in the row's menu")
            item.tap()
        }
        menu(names[0], "Compare…")
        menu(names[1], "Compare with \(names[0])")
        let paneB = element("comparePaneB")
        XCTAssertTrue(wait(20) { paneB.label == "Preview B, \(names[1])" }, "the previews draw: \(paneB.label)")
        pause(60)
        app.buttons["compareClose"].firstMatch.tap()
        XCTAssertTrue(wait(5) { !self.element("presetCompare").exists }, "the sheet closed")
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        let line = probe("compareProbe")
        let rate = Self.number(line, "rate") ?? 0, thermal = Self.number(line, "maxThermal") ?? 9
        print("PRE009-COMPARE \(line)")
        report(task, "comparison", ["rate": rate, "seconds": Self.number(line, "seconds") ?? 0, "maxThermal": thermal])
        let expected: Double = thermal >= 2 || ProcessInfo.processInfo.isLowPowerModeEnabled ? 15 : 30
        XCTAssertGreaterThanOrEqual(Self.number(line, "seconds") ?? 0, 55, "\(task): a 60 s comparison: \(line)")
        XCTAssertGreaterThanOrEqual(rate, expected * 0.85, "\(task): previews near their rate: \(line)")
        XCTAssertLessThanOrEqual(thermal, 1, "\(task): thermal state not above fair")
        _ = wait(8) { !self.controls.exists }
        assertFrameRate(task, "main visual after Close")
        assertDrawingAndMoving(task, "main visual after Close")
    }
}

/// The clamp threshold `ANGLEDebugFlashStats.clampedBelow` (the app's DEBUG probe), restated for the test bundle,
/// which does not link ANGLERendering.
enum ANGLEDebugFlashStatsLimit {
    static let clampedBelow = 0.98
}
