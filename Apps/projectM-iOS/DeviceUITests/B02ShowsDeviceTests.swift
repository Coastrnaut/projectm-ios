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
        // In-App Playback paused while away resumes on the return (AUD-006-R22, AUD-015-R5); the visual moves with the
        // music only once audio is active again (as VIS-001-T36 after background).
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(wait(15) { overlay.label.contains("Active audio") }, "playback resumes: \(overlay.label.prefix(160))")
        assertFrameRate(task, "after the return")
        // D1 2026-11-18: one pair 1 s apart measured 0.00185 against 0.002 (a quiet passage): three pairs, the largest.
        let (first, _) = screen(task, "after the return")
        XCTAssertGreaterThan(first.nonBlack, 0.02, "\(task) after the return: the visual draws")
        assertMovingSampled(task, "after the return")
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
        let (afterSwitcher, _) = screen(task, "after the switcher")
        XCTAssertGreaterThan(afterSwitcher.nonBlack, 0.02, "\(task) after the switcher: the visual draws")
        assertMovingSampled(task, "after the switcher")

        XCTAssertTrue(system.openControlCenter(), "Control Center opens over the app")
        pause(2)
        _ = screen(task, "control center")
        system.closeControlCenter()
        XCTAssertTrue(wait(10) { self.app.state == .runningForeground }, "back from Control Center")
        assertStillCircular("after Control Center")
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(wait(15) { overlay.label.contains("Active audio") }, "playback after Control Center: \(overlay.label.prefix(160))")
        assertFrameRate(task, "after Control Center")
        // D3 2026-11-18 (two runs): one pair 1 s apart read 0.0012 and 0.0017 against 0.002 at 60 fps, while D1, D2 and
        // the other returns passed: a quiet passage. Three pairs, the largest (autotester "Motion checks need several
        // samples"), as after the return from the background.
        let (first, _) = screen(task, "after Control Center")
        XCTAssertGreaterThan(first.nonBlack, 0.02, "\(task) after Control Center: the visual draws")
        assertMovingSampled(task, "after Control Center")
    }

    /// VIS-001-T36: the visual draws (non-black over 2 %) and moves over three pairs (largest change over 0.002).
    private func assertDrawsAndMovesSampled(_ label: String) {
        let task = "VIS-001-T36"
        let (first, _) = screen(task, label)
        XCTAssertGreaterThan(first.nonBlack, 0.02, "\(task) \(label): the visual draws")
        assertMovingSampled(task, label)
    }

    /// VIS-001-T36: rotate, background/return, Reduce flashing; overlay frame rate; no crash, no fallback.
    func testVIS001CircularSpectrumRotationBackgroundReduceFlashing() {
        let task = "VIS-001-T36"
        // Portrait and landscape motion over three pairs (largest change), as after the return below: on D1 (2026-11-22,
        // full run 1) one pair 1 s apart read 0.0011 in landscape and 0.002 in portrait while three pairs after the
        // return read 0.007, 0.005 and 0.017. The iPhone's spectrum covers fewer pixels and one quiet second of the
        // music decided a single pair; the iPads read 0.012-0.053 from one pair.
        launch(visual: "circularSpectrum")
        assertStillCircular("portrait")
        assertFrameRate(task, "portrait")
        assertDrawsAndMovesSampled("portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertStillCircular("landscape")
        assertFrameRate(task, "landscape")
        assertDrawsAndMovesSampled("landscape")
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
    /// 2026-11-19 (pass 3, D2): the bright glow pixels were compared with every coloured pixel without the glow (10.6°
    /// on D2, overall shift 3.1°), but a luma cut picks the spectrum's light hues (yellow, cyan) whatever the glow does.
    /// They are now compared with the same cut without the glow (its brightest fifth when fewer than 20 pass 0.85).
    func testFX002GlowKeepsTheSpectrumHue() {
        let task = "FX-002-T18"
        var hues: [Bool: [Double]] = [:], bright: [Double] = [], offLit: [(hue: Double, luma: Double)] = []
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
                            let luma = 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2
                            if glow { if luma > 0.85 { bright.append(h) } } else { offLit.append((h, luma)) }
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
        // The same luma cut without the glow; its brightest fifth when the cut leaves fewer than 20.
        var offBright = offLit.filter { $0.luma > 0.85 }.map(\.hue)
        if offBright.count < 20 {
            offBright = offLit.sorted { $0.luma > $1.luma }.prefix(max(offLit.count / 5, 1)).map(\.hue)
        }
        let offBrightMean = Self.circularMean(offBright)
        let difference = Self.angleDifference(off, on), brightDifference = Self.angleDifference(offBrightMean, brightMean)
        report(task, "hue", ["offHue": off, "onHue": on, "difference": difference, "brightSamples": Double(bright.count),
                             "offBrightHue": offBrightMean, "offBrightSamples": Double(offBright.count),
                             "brightToAllOff": Self.angleDifference(off, brightMean),
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
    /// The ordinary preset is ACC-002's calm fixture (`fixture:calm`), played the same way, counted from 3 s after it
    /// starts (the blend from the launch preset is over) for 6 s. 2026-11-18: the launch's first library preset ("EoS -
    /// dark side of the moon (plus a few more hits and a pill)") was clamped now and then on D1 and D3 (gain 0.50,
    /// 0.90), which is the envelope's job for third-party content, not "ordinary"; and the strobe read recentMin 1.000
    /// everywhere because the probe sampled every sixth frame, always the same phase of the fixture's 2-frame strobe
    /// (now every seventh, ANGLERenderer.recordDebugFlashGain). Clamps are counted as the rise of the cumulative count.
    /// 2026-11-19 (pass 3, D2 and D3): still no clamp after the Strobe fixture started (clampedSinceStart 0 in 18 s; the
    /// earlier clamps were the launch preset's): that fixture only strobes hard on bass above 1.2 and its gamma pump
    /// on a dark scene is under WCAG's step. The strobing preset is now `fixture:flicker` ("Flicker", a whole-frame
    /// inversion two frames in four, UITestVisualProbes.flickerPreset), which strobes whatever the music does.
    func testFX019StrobeClampedOrdinaryUnchanged() {
        let task = "FX-019-T23"
        func clampedCount() -> Double { Self.number(probe("flashGuardProbe"), "clamped") ?? -1 }

        launchProbed(visual: "projectM", settings: ["settings.reduceFlashing": false], extra: ["-uitestImportPreset", "fixture:calm"])
        XCTAssertTrue(playImportedFixture("Calm"), "the calm fixture plays: \(probe("presetFlashProbe"))")
        _ = wait(8) { !self.controls.exists }
        pause(3)
        let calmStart = clampedCount()
        let ordinaryFPS = assertFrameRate(task, "ordinary preset (probe on)", seconds: 6, minimum: 0)
        let ordinary = probe("flashGuardProbe")
        report(task, "ordinary", ["clampedIn6s": (Self.number(ordinary, "clamped") ?? -1) - calmStart,
                                  "recentSampled": Self.number(ordinary, "recentSampled") ?? -1,
                                  "recentMin": Self.number(ordinary, "recentMin") ?? -1, "fps": ordinaryFPS])
        print("FX019-ORDINARY \(probe("presetFlashProbe")) \(ordinary)")
        XCTAssertTrue(ordinary.contains("source=projectM"), "\(task): projectM's envelope is sampled: \(ordinary)")
        XCTAssertGreaterThan(Self.number(ordinary, "recentSampled") ?? 0, 5, "\(task): gains sampled")
        XCTAssertGreaterThanOrEqual(calmStart, 0, "\(task): the probe reads")
        XCTAssertEqual(Self.number(ordinary, "clamped"), calmStart, "\(task): the ordinary preset is not clamped: \(ordinary)")
        app.terminate()

        launchProbed(visual: "projectM", settings: ["settings.reduceFlashing": false], extra: ["-uitestImportPreset", "fixture:flicker"])
        XCTAssertTrue(playImportedFixture("Flicker"), "the fixture plays: \(probe("presetFlashProbe"))")
        _ = wait(8) { !self.controls.exists }
        pause(1)   // the blend from the launch preset is over, as for the calm fixture
        let strobeStart = clampedCount()
        var strobe = ""
        let clamped = wait(12) {
            strobe = self.probe("flashGuardProbe")
            return (Self.number(strobe, "clamped") ?? 0) > strobeStart && (Self.number(strobe, "recentMin") ?? 1) < 0.98
        }
        let strobeFPS = Self.median(sampleFPS(seconds: 6))
        screen(task, "strobe clamped")
        print("FX019-STROBE \(probe("presetFlashProbe")) \(strobe)")
        report(task, "strobe", ["clampedSinceStart": (Self.number(strobe, "clamped") ?? -1) - strobeStart,
                                "recentMin": Self.number(strobe, "recentMin") ?? -1, "fps": strobeFPS])
        XCTAssertTrue(clamped, "\(task): the envelope clamps the strobing preset with Reduce flashing off: \(strobe)")
        XCTAssertLessThan(Self.number(strobe, "recentMin") ?? 1, ANGLEDebugFlashStatsLimit.clampedBelow, "\(task): gain below 0.98")
    }

    /// SHOW-010-T12: four taps 500 ms apart (`-uitestTapInterval 500`: 120 BPM, tap tempo) on the SHOW-007 timeline
    /// seed (2:30): the drawn grid has a tick every 0.5 s (`showBeatGridProbe`), and while the show plays the readout's
    /// beat advances every 0.5 s and its bar every 2 s (readout sampled every 0.1 s for 9 s).
    /// 2026-11-18 (D1-D3): the probe was read once, before the row's next twice-a-second redraw had laid out the ticks
    /// ("ticks 0 bars 0"; it is polled now, as ShowBeatGridUITests does); and the timeline never moved: the seed makes
    /// cue 1 active without a cue start, so the playhead does not count down and Play (already "playing", Hold off) has
    /// nothing to resume, while the test's tap on it paused. A scrub seeks into cue 1, which starts the playhead
    /// (SHOW-007-R2), as a person scrubbing before playing does.
    /// 2026-11-19 (pass 3, D2 and D3): "ticks 75 bars 75" is the R2 density bound, not a missing beat: 300 beats over a
    /// ~726 pt track are 2.4 pt apart (< 4 pt), so only bars are drawn (stride 4, a line every 2 s). The expected stride
    /// is now derived from the track's width as `BeatGrid.stride` does. The readout redraws twice a second, so a beat's
    /// change is seen up to one redraw late; D3 saw alternate beats 0.23 s late (intervals 0.73/0.29, bars every 2.02 s,
    /// 18 beats in 9 s). The beat cadence is now the slope of the readout's beat count over time (a least-squares fit
    /// over every sample), which a late redraw does not bend; the per-interval median is still reported.
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
        let probeText = app.staticTexts["showBeatGridProbe"]
        var ticks = ""   // "ticks N bars M"
        _ = wait(3) {
            ticks = probeText.exists ? probeText.label : ""
            let parts = ticks.split(separator: " ")
            return parts.count == 4 && (Double(parts[1]) ?? 0) > 0
        }
        let parts = ticks.split(separator: " ")
        let tickCount = parts.count == 4 ? Double(parts[1]) ?? 0 : 0, barCount = parts.count == 4 ? Double(parts[3]) ?? 0 : 0
        let scrub = element("showTimelineScrub")
        XCTAssertTrue(appears(scrub, 3), "the timeline scrub bar")
        // R2: the drawing stride for 300 beats over the track (thumb inset 14 pt each side): 1, else 4, 8, 16 … until the
        // drawn ticks are at least 4 pt apart (BeatGrid.stride).
        let usable = max(Double(scrub.frame.width) - 28, 1)
        var stride = 1.0
        while usable * 0.5 * stride / 150 < 4 { stride = stride < 4 ? 4 : stride * 2 }
        dragSlider(scrub, from: 0, to: 0.05)   // one seek to about 0:07, inside cue 1
        // Seconds between drawn ticks over the 150 s timeline, per beat of the drawing stride.
        let spacing = 150 / max(tickCount, 1) / stride
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
        var samples: [(t: Double, beat: Double)] = []   // the readout's absolute beat (bar × 4 + beat) over time
        var last = position(value(readout))
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 9 {
            pause(0.1)
            guard let now = position(value(readout)) else { continue }
            let t = Date().timeIntervalSince(t0)
            samples.append((t, Double(now.bar * 4 + now.beat)))
            if let l = last, now.bar != l.bar || now.beat != l.beat { beatTimes.append(t) }
            if let l = last, now.bar != l.bar { barTimes.append(t) }
            last = now
        }
        let beatIntervals = zip(beatTimes, beatTimes.dropFirst()).map { $1 - $0 }
        let barIntervals = zip(barTimes, barTimes.dropFirst()).map { $1 - $0 }
        // Least-squares slope of beat count over time: beats per second.
        let n = Double(samples.count)
        let mt = samples.reduce(0) { $0 + $1.t } / max(n, 1), mb = samples.reduce(0) { $0 + $1.beat } / max(n, 1)
        let sxx = samples.reduce(0) { $0 + ($1.t - mt) * ($1.t - mt) }
        let sxy = samples.reduce(0) { $0 + ($1.t - mt) * ($1.beat - mb) }
        let beatsPerSecond = sxx > 0 ? sxy / sxx : 0
        let beatPeriod = beatsPerSecond > 0 ? 1 / beatsPerSecond : 0
        report(task, "grid", ["ticks": tickCount, "bars": barCount, "stride": stride, "trackWidth": usable + 28,
                              "tickSpacing": spacing, "beatPeriodFit": beatPeriod,
                              "beatMedian": Self.median(beatIntervals), "barMedian": Self.median(barIntervals),
                              "beats": Double(beatTimes.count), "barChanges": Double(barTimes.count)])
        XCTAssertEqual(spacing, 0.5, accuracy: 0.02, "\(task): a tick every 0.5 s per beat of stride \(stride) (\(ticks))")
        if stride >= 4 {
            XCTAssertEqual(barCount, tickCount, "\(task): only bars are drawn at stride \(stride) (\(ticks))")
        } else {
            XCTAssertEqual(barCount, tickCount / 4, accuracy: 1, "\(task): every fourth tick is a bar (\(ticks))")
        }
        XCTAssertGreaterThanOrEqual(beatTimes.count, 12, "\(task): the readout counts beats while the show plays")
        XCTAssertEqual(beatPeriod, 0.5, accuracy: 0.025, "\(task): a beat every 0.5 s (fit over \(samples.count) samples; intervals \(beatIntervals))")
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

    /// SHOW-013-T13 as the task reads ("120 BPM tapped, Rotate scenes on, Bars 4"): the five-scene show seed with scene 3
    /// disabled, 120 BPM tapped (four taps 500 ms apart, `-uitestTapInterval 500`), then Rotate scenes turned on in
    /// Settings: scenes change every 8 s (± 0.3 s, a multiple of the bar), never to the scene shown, never to the disabled
    /// scene; then Timer 15 s rotates every 15 s (rotation on at launch by `-uitestSceneRotation`, seed 1). Reduce
    /// flashing pinned off (its 15 s minimum gap would stretch 4 bars). 2026-11-18 (D1-D3): with ANL-006's scripted
    /// estimate (`-uitestTempoEstimate 120:0.9`, a tempo without beat phase) and rotation on from launch, bars mode fell
    /// back to the 60 s timer (SHOW-013-R3) and nothing changed in 34 s.
    func testSHOW013RotationOnTheBarAndTimer() {
        let task = "SHOW-013-T13"
        let disabled = Self.sceneID(3)
        launchPlain(["-uitestShowSeed", "-uitestKeepControls", "-uitestTapInterval", "500",
                     "-uitestSettingsSection", "sceneRotation", "-uitestSettingsSectionOnce"],
                    settings: ["settings.show.rotation": ["$json": ["mode": "bars", "bars": 4, "disabledSceneIDs": [disabled]]],
                               "settings.reduceFlashing": false])
        showControls()
        let tap = app.buttons["tapTempo"]
        XCTAssertTrue(appears(tap), "Tap tempo")
        for _ in 0..<4 { tap.tap() }
        XCTAssertTrue(wait(3) { self.value(tap).contains("120 BPM") }, "tapped 120 BPM: \(value(tap))")
        openSettings()
        let toggle = app.switches["sceneRotation.toggle"].firstMatch
        XCTAssertTrue(appears(toggle, 5) && reveal(toggle), "the Rotate scenes row")
        if value(toggle) != "1" { flip(toggle) }
        XCTAssertTrue(wait(3) { self.value(toggle) == "1" }, "Rotate scenes on: \(value(toggle))")
        closeSettings()
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
        tapFresh("presets")
        let chip = app.buttons["presetTagChip.Calm"]
        XCTAssertTrue(appears(chip, 10), "the Calm chip")
        if !chip.isSelected { chip.tap() }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset:'"))
        XCTAssertTrue(wait(5) { rows.count >= 3 }, "three Calm presets")
        // The playing preset's menu has no Compare… (D1-D3 2026-11-18: the first Calm row was the current preset; the
        // overlay's `currentPreset` text did not match its name). Its row label says "current preset".
        // A is the lowest of the two rows, B the higher one (D1 2026-11-22 rerun): after Compare… the compare bar sits
        // over the foot of the iPhone's sheet, and the short filtered list cannot scroll its last row above the bar
        // (twelve drags each bounced back), so B, pressed while the bar shows, must be the row nearer the top.
        let names = rows.allElementsBoundByIndex.filter { !$0.label.contains("current preset") }
            .sorted { $0.frame.minY > $1.frame.minY }
            .map { String($0.identifier.dropFirst("preset:".count)) }
        guard names.count >= 2 else { return XCTFail("\(task): two Calm presets to compare: \(names)") }
        func menu(_ name: String, _ title: String) {
            // D1 2026-11-22: after Compare… the compare bar (over the iPhone's floating search field) covered the last
            // Calm row, so the press met the bar and no menu opened. `reveal` scrolls the row clear of that chrome;
            // where the list is too short to scroll, the press goes to the part of the row above the chrome.
            let row = app.buttons["preset:\(name)"]
            if reveal(row, drags: 4) {
                row.press(forDuration: 0.7)
            } else {
                let top = max(row.frame.minY, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 0)
                let visible = min(row.frame.maxY, app.bottomChromeTop) - top
                XCTAssertGreaterThan(visible, 12, "\(task): part of the row \(name) shows above the bottom bars")
                row.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: row.frame.width * 0.4, dy: top - row.frame.minY + max(visible, 0) / 2))
                    .press(forDuration: 0.7)
            }
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
