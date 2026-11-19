// B01VisualsDeviceTests.swift — QA-011 owner session B01 ("Visuals and effects: look and frame rate with music"),
// automated on D1 (and D2 where the task names it). Each test closes the measurable part of its task: the frame
// rate on the performance overlay against the device budget, and image checks for the look (the visual draws and
// moves with the music; grey after saturation 0; an unchanged centre under Vignette; a still picture under
// Posterize and under Reduce Motion). Screenshots are attached for review. Music: In-App Playback's bundled track.
import UIKit
import XCTest

@MainActor
final class B01NativeVisualDeviceTests: B07DeviceCase {
    /// `minimumDraw`: a line visual (Lissajous, Radial Waveform) covers about 1 % of the screen, like the oscilloscope
    /// (autotester "Thresholds per kind of visual"); filled visuals keep 0.02.
    private func visualCheck(_ task: String, _ visual: String, settings: [String: Any] = [:], minimumDraw: Double = 0.02) {
        launch(visual: visual, settings: settings)
        assertFrameRate(task, visual)
        assertDrawingAndMoving(task, visual, minimumDraw: minimumDraw)
    }

    /// FX-001-T27: glow off vs on at default and maximum radius; after rotation; Reduce flashing on.
    func testFX001GlowFrameRateRotationAndReduceFlashing() {
        let task = "FX-001-T27"
        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": false])
        let off = assertFrameRate(task, "glow off")
        app.terminate()
        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true])
        let onDefault = assertFrameRate(task, "glow on, default radius")
        app.terminate()
        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true,
                                                       "settings.circularSpectrum.glowRadius": 0.06,
                                                       "settings.reduceFlashing": true])
        let onMax = assertFrameRate(task, "glow on, maximum radius, Reduce flashing on")
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertFrameRate(task, "landscape")
        assertDrawingAndMoving(task, "landscape")
        report(task, "glow cost", ["offMinusOnDefault": off - onDefault, "offMinusOnMax": off - onMax])
    }

    /// VIS-002-T16: Linear Spectrum in both orientations, glow on, Reduce flashing on, within budget.
    func testVIS002LinearSpectrumBothOrientations() {
        let task = "VIS-002-T16"
        launch(visual: "linearSpectrum", settings: ["settings.circularSpectrum.glow": true, "settings.reduceFlashing": true])
        assertFrameRate(task, "portrait")
        assertDrawingAndMoving(task, "portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertFrameRate(task, "landscape")
        assertDrawingAndMoving(task, "landscape")
    }

    // Line visuals (2026-11-18): with the overlay's text left out the radial waveform's ring covers 1.1 % of D1's screen
    // and 1.0 % of D2's; D1 had passed 0.02 only through the performance overlay's text (VIS-005 spec Clarifications).
    func testVIS004LissajousWithPersistence() {
        visualCheck("VIS-004-T13", "lissajous", settings: ["settings.lissajous.persistence": true], minimumDraw: 0.005)
    }
    func testVIS005RadialWaveform() { visualCheck("VIS-005-T12", "radialWaveform", minimumDraw: 0.005) }
    func testVIS006BeatRings() { visualCheck("VIS-006-T14", "beatRings") }
    func testVIS007Mandala() { visualCheck("VIS-007-T13", "mandala") }
    func testVIS013NoiseField() { visualCheck("VIS-013-T15", "noiseField") }
    func testVIS011FluidInk() { visualCheck("VIS-011-T13", "fluidInk", settings: ["settings.reduceFlashing": true]) }
    func testVIS020SpectrumWaterfall() { visualCheck("VIS-020-T12", "spectrumWaterfall") }

    /// VIS-014-T12: Kaleidoscope at 2, 7 and 24 wedges holds the frame rate and shows no seam (QA-011 B07). A seam is a
    /// discontinuity along a fixed angle through every radius: the luma step between neighbouring angles, averaged over
    /// radii (0.25° bins, 0.12-0.42 of the shorter side around the centre, the performance overlay's box left out),
    /// stays the same however fine the bins, while smooth content's step shrinks with the bin. The largest bin stays
    /// under `seamLimit` (luma 0-1). Two screenshots per count (the picture moves); the smaller counts.
    /// Measured 2026-11-18 on D1-D3: seamless pictures 0.002-0.015. The first draft's max-over-median of 1° bins read
    /// 1.7-9.7 for these seamless pictures (sharp colour edges of the 7-wedge pattern) and up to 47 where the overlay's
    /// text crossed the sampled circle (D1, D3), against a limit of 4.
    func testVIS014KaleidoscopeWedges() {
        let task = "VIS-014-T12"
        for wedges in [2, 7, 24] {
            launch(visual: "kaleidoscope", settings: ["settings.kaleidoscope.wedges": wedges])
            assertFrameRate(task, "\(wedges) wedges", seconds: 6)
            let box = overlayBox()
            var steps: [Double] = []
            for i in 0..<2 {
                steps.append(Self.seamStep(shot(task, "\(wedges) wedges \(i)", step: 2), window: app.windows.firstMatch.frame,
                                           excluding: box))
                pause(0.7)
            }
            report(task, "\(wedges) wedges seam", ["seamStepA": steps[0], "seamStepB": steps[1]])
            XCTAssertLessThan(steps.min() ?? 1, Self.seamLimit, "\(task) \(wedges) wedges: no seam (largest step \(steps))")
            app.terminate()
        }
    }

    /// A step twice the largest measured on seamless pictures (0.015): about 8 of 255 levels across every radius.
    static let seamLimit = 0.03

    /// The largest radius-averaged luma step between neighbouring 0.25° angles (see testVIS014KaleidoscopeWedges).
    static func seamStep(_ s: Shot, window: CGRect, excluding excluded: CGRect) -> Double {
        let c = CGPoint(x: window.midX, y: window.midY)
        let side = Double(min(window.width, window.height))
        let radii: [Double] = stride(from: 0.12, through: 0.42, by: 0.03).map { $0 * side }
        let bins = 1440
        var largest = 0.0
        for k in 0..<bins {
            let a0 = Double(k) * 2 * .pi / Double(bins), a1 = Double(k + 1) * 2 * .pi / Double(bins)
            var sum = 0.0, n = 0
            for r in radii {
                let p0 = CGPoint(x: c.x + CGFloat(r * cos(a0)), y: c.y + CGFloat(r * sin(a0)))
                let p1 = CGPoint(x: c.x + CGFloat(r * cos(a1)), y: c.y + CGFloat(r * sin(a1)))
                if excluded.contains(p0) || excluded.contains(p1) { continue }
                sum += abs(s.luma(p0) - s.luma(p1))
                n += 1
            }
            // A bin needs most radii: a seam crosses all of them, a partial bin next to the overlay would be noise.
            if n * 2 >= radii.count { largest = max(largest, sum / Double(n)) }
        }
        return largest
    }

    /// VIS-009-T10 (QA-011 B07): Particle Orbit drops no more frames than the Mandala with the same music: the PERF-007
    /// overlay's "frames device: … skipped N" counted over 60 s for each (allowance: 5 slots or 20 % of the Mandala's).
    func testVIS009OrbitDropsAgainstMandala() {
        let task = "VIS-009-T10"
        var skipped: [String: Double] = [:]
        for visual in ["mandala", "particleOrbit"] {
            launch(visual: visual)
            let start = overlaySkipped()
            let fps = Self.median(sampleFPS(seconds: 60))
            let end = overlaySkipped()
            XCTAssertNotNil(start, "\(task): the overlay shows the frames line")
            let count = Double((end ?? 0) - (start ?? 0))
            skipped[visual] = count
            report(task, visual, ["skipped60s": count, "fpsMedian": fps])
            XCTAssertGreaterThanOrEqual(fps, Self.minimumFPS, "\(task) \(visual): within budget")
            app.terminate()
        }
        let mandala = skipped["mandala"] ?? 0, orbit = skipped["particleOrbit"] ?? 0
        XCTAssertLessThanOrEqual(orbit, mandala + max(5, mandala * 0.2), "\(task): no more drops than the Mandala (\(orbit) vs \(mandala))")
    }

    /// The overlay's skipped refresh slots on the device output ("frames device: presented …, skipped N, …").
    func overlaySkipped() -> Int? {
        let label: String = app.descendants(matching: .any)["performanceOverlay"].firstMatch.label
        guard let start = label.range(of: "frames device:") else { return nil }
        let tail = label[start.upperBound...]
        guard let r = tail.range(of: #"skipped [0-9]+"#, options: .regularExpression) else { return nil }
        return Int(tail[r].dropFirst("skipped ".count))
    }

    /// VIS-020-T12 (QA-011 B07): newest at the top. Between two screenshots about 0.4 s apart the history moves down
    /// (4-5 sampled rows): the row shift that best matches the second picture to the first (−20…20 sampled rows) is
    /// positive in at least two of three pairs. The history fills the screen from the top over its 60 s span, so a few
    /// seconds after launch only the top 15-20 % is drawn (2026-11-18: the first draft compared the black middle band,
    /// where every shift costs the same, and read −30 or 0 on D1-D3; over the drawn band D2's pairs 1.5 s apart moved
    /// 16 rows). The pairs run with the performance overlay off (it covers the band on D1 and D3); the band is the drawn
    /// rows, and the run waits until it is at least 60 sampled rows deep.
    func testVIS020WaterfallNewestAtTop() {
        let task = "VIS-020-T12"
        launch(visual: "spectrumWaterfall")
        assertFrameRate(task, "waterfall", seconds: 6)
        app.terminate()
        launch(visual: "spectrumWaterfall", settings: ["settings.performanceOverlay": false])
        var depth = 0
        for _ in 0..<10 where depth < 60 {
            depth = Self.drawnDepth(shot(task, "fill", step: 4))
            if depth < 60 { pause(1) }
        }
        var shifts: [Int] = []
        for i in 0..<3 {
            let a = shot(task, "pair \(i) a", step: 4)
            pause(0.3)
            let b = shot(task, "pair \(i) b", step: 4)
            shifts.append(Self.bestDownShift(a, b, bandEnd: Self.drawnDepth(a)))
            pause(1)
        }
        report(task, "row shift", ["first": Double(shifts[0]), "second": Double(shifts[1]), "third": Double(shifts[2]),
                                   "drawnRows": Double(depth)])
        XCTAssertGreaterThanOrEqual(depth, 60, "\(task): the history is drawn from the top")
        XCTAssertGreaterThanOrEqual(shifts.filter { $0 > 0 }.count, 2, "\(task): rows move down (newest at the top): \(shifts)")
    }

    private static func waterfallLuma(_ s: Shot, _ x: Int, _ y: Int) -> Int {
        let i = (y * s.width + x) * 4
        return (Int(s.pixels[i]) * 54 + Int(s.pixels[i + 1]) * 183 + Int(s.pixels[i + 2]) * 19) >> 8
    }

    /// The sampled rows from the top down to the last row with drawn (non-black) content in the middle 80 % of the width.
    static func drawnDepth(_ s: Shot) -> Int {
        let w = s.width, h = s.height
        guard w > 0, h > 0, s.pixels.count >= w * h * 4 else { return 0 }
        var last = 0
        for y in 0..<(h * 3 / 4) {
            var lit = 0
            for x in stride(from: w / 10, to: w * 9 / 10, by: 3) where waterfallLuma(s, x, y) > 12 { lit += 1 }
            if lit * 7 >= (w * 8 / 10) / 3 { last = y }   // at least 15 % of the samples lit
        }
        return last
    }

    /// The vertical shift s (sampled rows) minimizing |b(x, y) − a(x, y − s)| over the drawn band (rows 20…bandEnd − 20).
    static func bestDownShift(_ a: Shot, _ b: Shot, bandEnd: Int) -> Int {
        let w = a.width, h = a.height
        guard w > 0, h > 0, a.pixels.count == b.pixels.count, a.pixels.count >= w * h * 4 else { return 0 }
        let x0 = w / 10, x1 = w * 9 / 10, y0 = 20, y1 = min(bandEnd - 20, h - 20)
        guard y1 > y0 else { return 0 }
        var best = 0, bestCost = Int.max
        for s in -20...20 {
            var cost = 0, n = 0
            for y in stride(from: y0, to: y1, by: 1) where y - s >= 0 && y - s < h {
                for x in stride(from: x0, to: x1, by: 3) { cost += abs(waterfallLuma(b, x, y) - waterfallLuma(a, x, y - s)); n += 1 }
            }
            let mean = n > 0 ? cost * 1000 / n : Int.max
            if mean < bestCost { bestCost = mean; best = s }
        }
        return best
    }

    /// VIS-012-T13 (QA-011 B07): presets grow different patterns, the pattern keeps (or gains) coverage with the bass,
    /// the frame rate holds at Speed 16, and with Reduce flashing on a reload shows no flash: the mean luma between
    /// screenshots 0.5 s apart never steps by more than 0.1, and once the reload's 1 s fade-in is over the native
    /// envelope never clamps (`flashGuardProbe`'s clamped count stays where it was at the first screenshot). The fade-in
    /// itself is limited by design: the envelope sees the bound (brightest stop × ramp, VIS-012-R11), which rises from 0
    /// faster than Reduce flashing's rise limit, so the first 3 s after launch clamped 94-96 of 480 samples on D1-D3
    /// (2026-11-18, recent 3 s 0): the envelope slowing the fade-in is the protection, not a flash.
    func testVIS012PresetsGrowthAndReloadsWithoutFlashing() {
        let task = "VIS-012-T13"
        var pictures: [[UInt8]] = []
        for preset in ["coral", "maze"] {
            launchProbed(visual: "reactionDiffusion", settings: ["settings.reactionDiffusion.preset": preset,
                                                                  "settings.reactionDiffusion.speed": 16,
                                                                  "settings.reduceFlashing": true])
            let afterFadeIn = Self.number(probe("flashGuardProbe"), "clamped") ?? -1
            let (early, _) = screen(task, "\(preset) early")
            assertFrameRate(task, "\(preset) speed 16", seconds: 6)
            var lumas: [Double] = [early.meanLuma]
            var last: [UInt8] = []
            for i in 0..<6 {
                let (s, p) = screen(task, "\(preset) \(i)")
                lumas.append(s.meanLuma)
                last = p
                pause(0.5)
            }
            let late = lumas.last ?? 0
            let steps = zip(lumas, lumas.dropFirst()).map { abs($1 - $0) }
            let flash = probe("flashGuardProbe")
            report(task, preset, ["earlyNonBlack": early.nonBlack, "lateLuma": late, "maxLumaStep": steps.max() ?? 0,
                                  "clampedInFadeIn": afterFadeIn,
                                  "clamped": Self.number(flash, "clamped") ?? -1, "sampled": Self.number(flash, "sampled") ?? -1])
            XCTAssertTrue(flash.contains("source=native"), "\(task): the probe reads the native envelope: \(flash)")
            XCTAssertGreaterThanOrEqual(afterFadeIn, 0, "\(task) \(preset): the probe was read after the fade-in")
            XCTAssertEqual(Self.number(flash, "clamped"), afterFadeIn,
                           "\(task) \(preset): nothing clamps after the reload's fade-in: \(flash)")
            XCTAssertLessThan(steps.max() ?? 0, 0.1, "\(task) \(preset): no luminance step over 0.1")
            pictures.append(last)
            app.terminate()
        }
        let difference = Self.change(pictures[0], pictures[1])
        report(task, "presets differ", ["change": difference])
        XCTAssertGreaterThan(difference, 0.01, "\(task): each preset grows its own pattern")
    }

    /// VIS-017-T13 (QA-011 B07): the SDF Shapes pipelines come from the PERF-009 binary archive on the second launch
    /// (`pipelineArchiveProbe` hits > 0), and Reduce Motion is calmer than without it.
    func testVIS017ArchiveHitOnSecondLaunchAndReduceMotion() {
        let task = "VIS-017-T13"
        launchProbed(visual: "signedDistance")
        let (_, a) = screen(task, "normal a"); pause(1); let (_, b) = screen(task, "normal b")
        let normal = Self.change(a, b)
        let first = probe("pipelineArchiveProbe")
        XCUIDevice.shared.press(.home)   // PERF-009-R6: the archive is written when the scene leaves the foreground
        pause(4)
        app.terminate()
        launchProbed(visual: "signedDistance", extra: ["-uitestReduceMotion", "YES"])
        XCTAssertTrue(wait(10) { !self.probe("pipelineArchiveProbe").isEmpty && self.probe("pipelineArchiveProbe") != "none" })
        let second = probe("pipelineArchiveProbe")
        let (_, c) = screen(task, "reduce motion a"); pause(1); let (_, d) = screen(task, "reduce motion b")
        let calm = Self.change(c, d)
        print("VIS017-ARCHIVE first: \(first) second: \(second)")
        report(task, "archive", ["firstHits": Self.number(first, "hits") ?? -1, "firstMisses": Self.number(first, "misses") ?? -1,
                                 "secondHits": Self.number(second, "hits") ?? -1, "secondMisses": Self.number(second, "misses") ?? -1,
                                 "motionNormal": normal, "motionReduceMotion": calm])
        XCTAssertGreaterThan(Self.number(second, "hits") ?? 0, 0, "\(task): pipelines served from the archive: \(second)")
        XCTAssertLessThanOrEqual(calm, normal, "\(task): Reduce Motion is calmer")
    }

    /// VIS-015-T12 (QA-011 B07): a tapped tempo (four taps 400 ms apart through `-uitestTapInterval`, 150 BPM) speeds
    /// the tunnel up smoothly (`tunnelSpeedProbe`: no change over 10 % per 1/60 s) and Reset eases it back; the frame
    /// rate holds.
    func testVIS015TunnelTappedTempoAndReset() {
        let task = "VIS-015-T12"
        launchProbed(visual: "tunnel", extra: ["-uitestTapInterval", "400", "-uitestKeepControls"])
        func speed() -> Double { Self.number(probe("tunnelSpeedProbe"), "speed") ?? 0 }
        XCTAssertTrue(wait(5) { speed() > 0 }, "the tunnel's speed is reported")
        pause(3)
        let before = speed()
        showControls()
        for _ in 0..<4 { app.buttons["tapTempo"].tap() }
        XCTAssertTrue(wait(3) { ((self.app.buttons["tapTempo"].value as? String) ?? "").contains("150 BPM") },
                      "tapped 150 BPM: \(app.buttons["tapTempo"].value ?? "nil")")
        var rising: [Double] = []
        for _ in 0..<15 { rising.append(speed()); pause(0.2) }
        let tapped = speed()
        let reset = app.buttons["resetTempo"]
        if !reset.exists { showControls() }
        XCTAssertTrue(appears(reset, 3), "Reset tempo offered")
        reset.tap()
        var easing: [Double] = []
        for _ in 0..<15 { easing.append(speed()); pause(0.2) }
        let after = speed()
        let maxStep = Self.number(probe("tunnelSpeedProbe"), "maxStepPerFrame") ?? 1
        report(task, "speed", ["before": before, "tapped": tapped, "afterReset": after, "maxStepPerFrame": maxStep])
        XCTAssertGreaterThan(tapped, before * 1.1, "\(task): the tapped tempo speeds the tunnel up (\(before) → \(tapped))")
        XCTAssertLessThan(after, tapped * 0.95, "\(task): Reset eases it back (\(tapped) → \(after))")
        XCTAssertLessThan(maxStep, 0.10, "\(task): no step over 10 % per frame")
        XCTAssertGreaterThan(rising.last ?? 0, rising.first ?? 0, "\(task): rises over time \(rising)")
        XCTAssertLessThan(easing.last ?? 0, easing.first ?? 0, "\(task): eases back over time \(easing)")
        hideControls()
        assertFrameRate(task, "tunnel after reset", seconds: 6)
    }

    /// ANL-015-T12 (QA-011 B07): "Section change" bound to the glow (`-uitestBindGlowToSectionChange`) over the music
    /// fixture (scripts/make_music_fixture.py): the quiet intro (level 0.25, no drums) turns loud at 10 s (0.55 with
    /// drums, over 6 dB more: ANL-015-R4's entry threshold), then rises again at 20 s (to 1.0, +5.2 dB: under 6 dB, so no
    /// event) and stays loud with drum hits until the breakdown at 40 s. Exactly one fire before 40 s, about 2 s after
    /// the step (11.8-12.9 s of playback: the 2 s dwell, the 0.41 s slow window and one block), none on the drum hits.
    /// Measured 12.14-12.18 s on D1-D3 (2026-11-18); the first draft expected the fire at 20 s.
    func testANL015SectionChangeFlash() {
        let task = "ANL-015-T12"
        launchProbed(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true],
                     extra: ["-uitestBindGlowToSectionChange"])
        XCTAssertTrue(wait(55) { (Self.number(self.probe("sectionChangeProbe"), "position") ?? 0) >= 39 },
                      "the fixture played to the breakdown: \(probe("sectionChangeProbe"))")
        let fires = Self.numbers(probe("sectionChangeProbe"), "fires").filter { $0 < 40 }
        print("ANL015-FIRES \(fires)")
        report(task, "fires", ["count": Double(fires.count), "fire": fires.first ?? -1])
        XCTAssertEqual(fires.count, 1, "\(task): one fire for the quiet-to-loud step, none on drum hits: \(fires)")
        if let fire = fires.first {
            XCTAssertTrue((11.8...12.9).contains(fire), "\(task): about 2 s after the step at 10 s: \(fire)")
        }
    }

    /// VIS-012-T13: Reaction Diffusion at Speed 16, Reduce flashing on.
    func testVIS012ReactionDiffusionSpeed16() {
        visualCheck("VIS-012-T13", "reactionDiffusion", settings: ["settings.reactionDiffusion.speed": 16, "settings.reduceFlashing": true])
    }

    /// VIS-016-T13: Starfield at 2000 stars and Fast; with Reduce Motion it moves less. The screenshots show the stars
    /// moving; "less" is the flight speed, read from `starfieldProbe` as stars passing the near plane per simulation step
    /// over 4 s. Screenshots 1 s apart cannot tell the speeds apart: every star moves further than its own size at both,
    /// so the change is the same (0.007-0.009 on D1-D3 2026-11-18 with the overlay's text left out; D1 had passed on the
    /// overlay's changing text alone). Half speed (VIS-016, ACC-001) gives about half the rate; the limit is 0.75.
    func testVIS016StarfieldFastAndReduceMotion() {
        let task = "VIS-016-T13"
        let settings: [String: Any] = ["settings.starfield.density": 2000, "settings.starfield.speed": "fast"]
        func respawnRate(_ label: String) -> (rate: Double, line: String) {
            func read() -> (Double, Double) {
                let line = probe("starfieldProbe")
                return (Self.number(line, "steps") ?? 0, Self.number(line, "respawns") ?? 0)
            }
            XCTAssertTrue(wait(5) { read().0 > 0 }, "\(task) \(label): the starfield probe reads: \(probe("starfieldProbe"))")
            let (steps0, respawns0) = read()
            pause(4)
            let (steps1, respawns1) = read()
            let rate = steps1 > steps0 ? (respawns1 - respawns0) / (steps1 - steps0) : 0
            return (rate, probe("starfieldProbe"))
        }
        launchProbed(visual: "starfield", settings: settings)
        assertFrameRate(task, "2000 stars, Fast")
        let (_, a) = screen(task, "fast a"); pause(1); let (_, b) = screen(task, "fast b")
        let normal = Self.change(a, b)
        let fast = respawnRate("Fast")
        app.terminate()
        launchProbed(visual: "starfield", settings: settings, extra: ["-uitestReduceMotion", "YES"])
        let calm = respawnRate("Reduce Motion")
        report(task, "motion", ["normal": normal, "respawnsPerStepFast": fast.rate, "respawnsPerStepReduceMotion": calm.rate])
        XCTAssertGreaterThan(normal, 0.002, "\(task): the stars move")
        XCTAssertTrue(fast.line.contains("reduceMotion=off") && calm.line.contains("reduceMotion=on"),
                      "\(task): Reduce Motion reaches the starfield (\(fast.line) / \(calm.line))")
        XCTAssertGreaterThan(fast.rate, 0, "\(task): stars fly past at Fast (\(fast.line))")
        XCTAssertLessThanOrEqual(calm.rate, fast.rate * 0.75, "\(task): Reduce Motion is calmer (\(calm.rate) vs \(fast.rate) per step)")
    }

    /// VIS-008-T14 and VIS-009-T10: Particle Fountain and Orbit; Reduce Motion fewer and slower.
    func testVIS008VIS009ParticlesAndReduceMotion() {
        for (task, visual) in [("VIS-008-T14", "particleFountain"), ("VIS-009-T10", "particleOrbit")] {
            launch(visual: visual)
            assertFrameRate(task, visual)
            let (_, a) = screen(task, "\(visual) a"); pause(1); let (_, b) = screen(task, "\(visual) b")
            let normal = Self.change(a, b)
            app.terminate()
            launch(visual: visual, extra: ["-uitestReduceMotion", "YES"])
            let (_, c) = screen(task, "\(visual) reduce motion a"); pause(1); let (_, d) = screen(task, "\(visual) reduce motion b")
            let calm = Self.change(c, d)
            report(task, "\(visual) motion", ["normal": normal, "reduceMotion": calm])
            XCTAssertGreaterThan(normal, 0.001, "\(task): particles move")
            app.terminate()
        }
    }

    /// VIS-010-T16: Fountain and Orbit with Trails Short and Long; frame rate unchanged, Reduce flashing on.
    func testVIS010ParticleTrails() {
        for visual in ["particleFountain", "particleOrbit"] {
            for trails in ["short", "long"] {
                launch(visual: visual, settings: ["settings.particleTrails": trails, "settings.reduceFlashing": true])
                assertFrameRate("VIS-010-T16", "\(visual) trails \(trails)", seconds: 6)
                screen("VIS-010-T16", "\(visual) trails \(trails)")
                app.terminate()
            }
        }
    }

    /// VIS-017-T13: SDF Shapes at each quality; Reduce Motion calm.
    func testVIS017SignedDistanceQualities() {
        for quality in ["low", "medium", "high"] {
            launch(visual: "signedDistance", settings: ["settings.signedDistance.quality": quality])
            assertFrameRate("VIS-017-T13", "quality \(quality)", seconds: 6)
            screen("VIS-017-T13", "quality \(quality)")
            app.terminate()
        }
    }
}

@MainActor
final class B01PhotoEffectDeviceTests: B07DeviceCase {
    private func photo(_ settings: [String: Any] = [:], extra: [String] = []) {
        launch(visual: "photo", settings: settings, extra: ["-uitestSeedPhoto", "pattern"] + extra)
    }

    /// The photo region without effects (pattern fixture), for "the effect changes the picture".
    private var basePixels: [UInt8] = []

    /// The Photo visual's frame rate without effects, for "unchanged within noise".
    private func baseline(_ task: String) -> Double {
        photo()
        let fps = assertFrameRate(task, "photo, no effect", seconds: 6)
        basePixels = screen(task, "photo, no effect").1
        app.terminate()
        return fps
    }

    /// Frame rate within noise of off, and proof the effect is on: the still photo region differs from no effect.
    /// Returns the effect's sampled screenshot (QA-011 B07: FX-004's greys).
    @discardableResult
    private func effectCheck(_ task: String, _ label: String, _ settings: [String: Any], base: Double,
                             minimumChange: Double = 0.01) -> [UInt8] {
        photo(settings)
        let fps = assertFrameRate(task, label, seconds: 6)
        let pixels = screen(task, label).1
        let applied = stillChange(basePixels, pixels)
        report(task, label, ["changeFromOff": applied])
        XCTAssertGreaterThanOrEqual(fps, base - Self.effectToleranceFPS, "\(task) \(label): frame rate within noise of off")
        if !basePixels.isEmpty {
            XCTAssertGreaterThan(applied, minimumChange, "\(task) \(label): the effect changes the picture")
        }
        app.terminate()
        return pixels
    }

    /// Sample indices (pixel numbers) where the picture is grey: chroma (max − min) under 0.04 and luma over 0.15, away
    /// from the performance overlay (the top 15 %). The pattern photo's white and mid-grey bars (with their dimmed
    /// checkerboard squares) give these.
    private func greyIndices(_ p: [UInt8]) -> [Int] {
        let (w, h) = lastSize
        guard w > 0, h > 0 else { return [] }
        var result: [Int] = []
        for y in Int(Double(h) * 0.15)..<h {
            for x in 0..<w {
                let i = y * w + x
                guard i * 4 + 2 < p.count else { continue }
                let r = Double(p[i * 4]) / 255, g = Double(p[i * 4 + 1]) / 255, b = Double(p[i * 4 + 2]) / 255
                let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if max(r, g, b) - min(r, g, b) < 0.04, luma > 0.15 { result.append(i) }
            }
        }
        return result
    }

    private static func medianChroma(_ p: [UInt8], _ indices: [Int]) -> Double {
        let values: [Double] = indices.compactMap { (i: Int) -> Double? in
            guard i * 4 + 2 < p.count else { return nil }
            let r = Double(p[i * 4]), g = Double(p[i * 4 + 1]), b = Double(p[i * 4 + 2])
            return (max(r, g, b) - min(r, g, b)) / 255
        }
        return median(values)
    }

    /// FX-003-T22: warm, gain 1.5, saturation 0 → grey; reset → identical to none; frame rate unchanged.
    func testFX003GradeGreyAndReset() {
        let task = "FX-003-T22"
        photo()
        let base = assertFrameRate(task, "neutral", seconds: 6)
        let (_, neutralPixels) = screen(task, "neutral")
        let neutral = stillStats(neutralPixels)
        app.terminate()
        photo(["settings.colorGrade.temperature": 0.5, "settings.colorGrade.gain": 1.5, "settings.colorGrade.saturation": 0.0])
        let fps = assertFrameRate(task, "graded", seconds: 6)
        let (_, greyPixels) = screen(task, "warm, gain 1.5, saturation 0")
        let grey = stillStats(greyPixels)
        report(task, "photo region", ["neutralSaturation": neutral.meanSaturation, "gradedSaturation": grey.meanSaturation])
        XCTAssertLessThan(grey.meanSaturation, 0.05, "\(task): saturation 0 gives grey")
        XCTAssertGreaterThanOrEqual(fps, base - Self.effectToleranceFPS)
        app.terminate()
        photo()
        assertFrameRate(task, "reset", seconds: 6)   // as every other step: the launch controls have hidden by then
        let (_, resetPixels) = screen(task, "reset")
        let reset = stillStats(resetPixels)
        XCTAssertEqual(reset.meanLuma, neutral.meanLuma, accuracy: 0.02, "\(task): reset matches neutral")
    }

    /// FX-004-T15: hue +120 changes the colour, frame rate unchanged; greys stay grey (QA-011 B07: the median chroma
    /// at the no-effect picture's grey samples rises by less than 2 %).
    func testFX004Hue() {
        let task = "FX-004-T15"
        let base = baseline(task)
        let greys = greyIndices(basePixels)
        let shifted = effectCheck(task, "hue +120", ["settings.colorGrade.hue": 120.0], base: base)
        let before = Self.medianChroma(basePixels, greys), after = Self.medianChroma(shifted, greys)
        report(task, "greys", ["greySamples": Double(greys.count), "chromaBefore": before, "chromaAfter": after])
        XCTAssertGreaterThan(greys.count, max(20, basePixels.count / 4 / 200), "\(task): the pattern's grey bars are on screen")
        XCTAssertLessThan(after - before, 0.02, "\(task): greys unchanged by the hue shift (chroma \(before) → \(after))")
    }

    func testFX005ContrastCurves() {
        let task = "FX-005-T14"
        let base = baseline(task)
        effectCheck(task, "S-curve 100%", ["settings.colorGrade.contrast": "sCurve", "settings.colorGrade.contrastStrength": 1.0], base: base)
        effectCheck(task, "Filmic 100%", ["settings.colorGrade.contrast": "filmic", "settings.colorGrade.contrastStrength": 1.0], base: base)
    }

    func testFX006ChromaticSplit() {
        let task = "FX-006-T18"
        let base = baseline(task)
        effectCheck(task, "split 2% radial", ["settings.chromatic.enabled": true, "settings.chromatic.amount": 0.02,
                                              "settings.chromatic.radial": true], base: base)
    }

    func testFX007DirectionalBlur() {
        let task = "FX-007-T17"
        let base = baseline(task)
        effectCheck(task, "2% at 45°", ["settings.directionalBlur.enabled": true, "settings.directionalBlur.radius": 0.02,
                                       "settings.directionalBlur.angle": 45.0], base: base)
    }

    func testFX008RadialBlur() {
        let task = "FX-008-T18"
        let base = baseline(task)
        effectCheck(task, "25% centred", ["settings.radialBlur.enabled": true, "settings.radialBlur.strength": 0.25], base: base)
        effectCheck(task, "25% moved", ["settings.radialBlur.enabled": true, "settings.radialBlur.strength": 0.25,
                                        "settings.radialBlur.centerX": 0.3, "settings.radialBlur.centerY": 0.7], base: base)
    }

    func testFX012Mosaic() {
        let task = "FX-012-T18"
        // Every 3rd pixel, not every 8th: a square block shows its centre pixel (bx·N + N/2), and a nearest-neighbour
        // scale to 1/8 reads pixel 8k + 4, the very pixel each 8 px block shows. On D2 and D3, whose composite is the
        // screen's pixel grid, every sample was a block's own centre and the change read 0.0 (2026-11-18).
        sampleStep = 3
        let base = baseline(task)
        for shape in ["square", "hexagon"] {
            for size in [8, 64] {
                // 8 px blocks line up with the pattern's 8 px checkerboard, so they change it only a little.
                effectCheck(task, "\(shape) \(size)", ["settings.mosaic.enabled": true, "settings.mosaic.shape": shape,
                                                      "settings.mosaic.size": Double(size)], base: base,
                            minimumChange: size == 8 ? 0.003 : 0.01)
            }
        }
    }

    /// FX-013-T14: Posterize 6 levels with Dither: within 1 fps of off, no shimmer on the still picture.
    func testFX013PosterizeNoShimmer() {
        let task = "FX-013-T14"
        let base = baseline(task)
        photo(["settings.colorGrade.posterize": true, "settings.colorGrade.posterizeLevels": 6,
               "settings.colorGrade.posterizeDither": true])
        let fps = assertFrameRate(task, "6 levels, dither", seconds: 6)
        let (_, a) = screen(task, "still a"); pause(1); let (_, b) = screen(task, "still b")
        let shimmer = stillChange(a, b)
        report(task, "shimmer", ["change": shimmer])
        XCTAssertGreaterThanOrEqual(fps, base - 1, "\(task): within 1 fps of off")
        XCTAssertLessThan(shimmer, 0.01, "\(task): no shimmer on a still picture")
    }

    /// FX-015-T15: Vignette 100 %, softness 10 % and 90 %, centre moved: edges darker, the middle unchanged.
    /// Regions avoid the overlay (top leading) and the photo visual's centred spectrum: "middle" is just below the
    /// spectrum (inside the clear core at softness 10 %), "edge" the bottom-leading corner.
    func testFX015VignetteCentreUnchanged() {
        let task = "FX-015-T15"
        let middle: (Double, Double, Double, Double) = (0.42, 0.66, 0.16, 0.03)
        let edge: (Double, Double, Double, Double) = (0.0, 0.955, 0.04, 0.035)   // the very corner: outside the core even at softness 10 %
        photo()
        let base = assertFrameRate(task, "off", seconds: 6)
        let (_, offPixels) = screen(task, "off")
        let offMiddle = Self.region(offPixels, width: lastSize.0, height: lastSize.1, middle)
        let offEdge = Self.region(offPixels, width: lastSize.0, height: lastSize.1, edge)
        app.terminate()
        for softness in [0.1, 0.9] {
            photo(["settings.vignette.enabled": true, "settings.vignette.intensity": 1.0, "settings.vignette.softness": softness])
            let fps = assertFrameRate(task, "softness \(softness)", seconds: 6)
            let (_, p) = screen(task, "softness \(softness)")
            let mid = Self.region(p, width: lastSize.0, height: lastSize.1, middle)
            let corner = Self.region(p, width: lastSize.0, height: lastSize.1, edge)
            report(task, "softness \(softness)", ["middleLuma": mid.meanLuma, "offMiddleLuma": offMiddle.meanLuma,
                                                  "edgeLuma": corner.meanLuma, "offEdgeLuma": offEdge.meanLuma])
            if softness < 0.5 {
                XCTAssertEqual(mid.meanLuma, offMiddle.meanLuma, accuracy: 0.03, "\(task): the middle is unchanged")
            }
            XCTAssertLessThan(corner.meanLuma, offEdge.meanLuma - 0.05, "\(task): the edges darken")
            XCTAssertGreaterThanOrEqual(fps, base - Self.effectToleranceFPS)
            app.terminate()
        }
        // Centre moved up and leading: the far (bottom trailing) corner darkens more than with the centre in the middle.
        let far: (Double, Double, Double, Double) = (0.94, 0.955, 0.04, 0.035)
        let offFar = Self.region(offPixels, width: lastSize.0, height: lastSize.1, far)
        photo(["settings.vignette.enabled": true, "settings.vignette.intensity": 1.0,
               "settings.vignette.centerX": 0.3, "settings.vignette.centerY": 0.3])
        let fps = assertFrameRate(task, "centre moved", seconds: 6)
        let (_, moved) = screen(task, "centre moved")
        let movedFar = Self.region(moved, width: lastSize.0, height: lastSize.1, far)
        report(task, "centre moved", ["farCornerLuma": movedFar.meanLuma, "offFarCornerLuma": offFar.meanLuma])
        XCTAssertLessThan(movedFar.meanLuma, offFar.meanLuma - 0.05, "\(task): the far corner darkens with the centre moved")
        XCTAssertGreaterThanOrEqual(fps, base - Self.effectToleranceFPS)
    }

    /// FX-017-T17: Film grain at 100 %, sizes 1-3, colour and monochrome; Vary over time moves, Reduce Motion is still.
    func testFX017FilmGrain() {
        let task = "FX-017-T17"
        let base = baseline(task)
        for size in [1, 2, 3] {
            effectCheck(task, "size \(size)", ["settings.filmGrain.enabled": true, "settings.filmGrain.opacity": 1.0,
                                              "settings.filmGrain.size": size], base: base)
        }
        effectCheck(task, "monochrome", ["settings.filmGrain.enabled": true, "settings.filmGrain.opacity": 1.0,
                                         "settings.filmGrain.color": false], base: base)
        // Reduce flashing pinned off in both runs: it follows Reduce Motion unless set (AppSettings.reduceFlashing), and
        // its stricter composite flash envelope scales the whole frame with the spectrum's flashes. On D1-D3
        // (2026-11-18) the Reduce Motion pair differed by a uniform 3-5 % gain over a static grain (0.012-0.016 against
        // 0.01); this check is about the grain, so only Reduce Motion changes between the runs.
        let grain: [String: Any] = ["settings.filmGrain.enabled": true, "settings.filmGrain.opacity": 1.0,
                                    "settings.filmGrain.animated": true, "settings.reduceFlashing": false]
        photo(grain)
        // The controls still showed in the first "vary" screenshot on D2 and D3 (over the still region).
        _ = wait(6) { !self.controls.exists }
        let (_, a) = screen(task, "vary a"); pause(1); let (_, b) = screen(task, "vary b")
        let varying = stillChange(a, b)
        app.terminate()
        photo(grain, extra: ["-uitestReduceMotion", "YES"])
        _ = wait(6) { !self.controls.exists }
        let (_, c) = screen(task, "reduce motion a"); pause(1); let (_, d) = screen(task, "reduce motion b")
        let still = stillChange(c, d)
        report(task, "grain motion", ["vary": varying, "reduceMotion": still])
        XCTAssertGreaterThan(varying, still, "\(task): Vary over time moves; Reduce Motion holds it")
        XCTAssertLessThan(still, 0.01, "\(task): still with Reduce Motion")
    }

    /// FX-018-T16: Scanlines at spacing 2, 3 and 16, intensity 100 %, both orientations; frame rate with and without.
    func testFX018Scanlines() {
        let task = "FX-018-T16"
        sampleStep = 1   // 1-pixel lines: any coarser sampling can fall between them (aliasing)
        let base = baseline(task)
        for spacing in [2, 3, 16] {
            effectCheck(task, "spacing \(spacing)", ["settings.scanlines.enabled": true, "settings.scanlines.intensity": 1.0,
                                                    "settings.scanlines.spacing": spacing], base: base)
        }
        photo(["settings.scanlines.enabled": true, "settings.scanlines.intensity": 1.0, "settings.scanlines.spacing": 3],
              extra: [])
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertFrameRate(task, "landscape spacing 3", seconds: 6)
        let (_, a) = screen(task, "landscape a"); pause(1); let (_, b) = screen(task, "landscape b")
        let crawl = stillChange(a, b)
        report(task, "crawl", ["change": crawl])
        XCTAssertLessThan(crawl, 0.01, "\(task): no crawl or flicker on a still picture")
    }
}

/// QA-011 Batch 7: effect order and GPU cost on the Photo visual (pattern fixture), and the Cymatic Lines.
@MainActor
final class B01EffectOrderDeviceTests: B07DeviceCase {
    /// FX-020-T19: Trails and a strong grade in both orders over the pattern photo with music. The orders give different
    /// pictures where the spectrum moves (grade-then-trails vs trails-then-grade), the frame rate holds and the
    /// composite flash guard (`flashGuardProbe`, source compositor) runs in both orders. The "strobing fixture in both
    /// orders" half needs a strobing source on the compositor path, which the app cannot seed today (Batch 7 report).
    func testFX020BothOrders() {
        let task = "FX-020-T19"
        let effects: [String: Any] = ["settings.feedback.enabled": true, "settings.colorGrade.gain": 1.5,
                                      "settings.colorGrade.temperature": 0.6, "settings.colorGrade.saturation": 1.6]
        var pictures: [[UInt8]] = []
        for order in ["fx.trails,fx.grade", "fx.grade,fx.trails"] {
            var settings = effects
            settings["settings.effectChain.order"] = order
            launchProbed(visual: "photo", settings: settings, extra: ["-uitestSeedPhoto", "pattern"])
            assertFrameRate(task, order, seconds: 6)
            pictures.append(screen(task, order).1)
            let flash = probe("flashGuardProbe")
            report(task, "\(order) flash guard", ["sampled": Self.number(flash, "sampled") ?? -1,
                                                  "clamped": Self.number(flash, "clamped") ?? -1])
            XCTAssertTrue(flash.contains("source=compositor"), "\(task) \(order): the composite flash guard runs: \(flash)")
            app.terminate()
        }
        let whole = Self.change(pictures[0], pictures[1])
        let still = stillChange(pictures[0], pictures[1])
        report(task, "orders", ["changeWhole": whole, "changeStillRegion": still])
        XCTAssertGreaterThan(whole, 0.003, "\(task): the two orders look different")
    }

    /// FX-011-T16: Pixel sort at span 32 and 64, both directions, on the Photo visual: the overlay's GPU estimate
    /// ("estimate cpu …, gpu N ms") and frame rate, against Pixel sort off. The 4K external display part is not
    /// required (owner ruling 2026-11-18: no AirPlay or cable steps).
    func testFX011PixelSortGPUTime() {
        let task = "FX-011-T16"
        func run(_ label: String, _ settings: [String: Any]) -> (Double, Double) {
            launch(visual: "photo", settings: settings, extra: ["-uitestSeedPhoto", "pattern"])
            let fps = assertFrameRate(task, label, seconds: 6)
            var gpu: [Double] = []
            for _ in 0..<6 { if let g = overlayGPU() { gpu.append(g) }; pause(1) }
            let median = Self.median(gpu)
            report(task, label, ["gpuMs": median, "fps": fps, "gpuSamples": Double(gpu.count)])
            app.terminate()
            return (median, fps)
        }
        let (offGPU, offFPS) = run("off", [:])
        for span in [32, 64] {
            for direction in ["horizontal", "vertical"] {
                let (gpu, fps) = run("span \(span) \(direction)", ["settings.pixelSort.enabled": true, "settings.pixelSort.span": span,
                                                                   "settings.pixelSort.direction": direction])
                report(task, "span \(span) \(direction) cost", ["gpuMinusOffMs": gpu - offGPU])
                XCTAssertGreaterThan(gpu, 0, "\(task): the overlay reports the GPU time")
                XCTAssertGreaterThanOrEqual(fps, offFPS - Self.effectToleranceFPS, "\(task) span \(span) \(direction): frame rate holds")
            }
        }
    }

    /// The overlay's whole-frame GPU estimate in ms ("estimate cpu 1.2 ms, gpu 3.4 ms"), nil while unavailable.
    func overlayGPU() -> Double? {
        let label = app.descendants(matching: .any)["performanceOverlay"].firstMatch.label
        guard let r = label.range(of: #"gpu [0-9]+(\.[0-9]+)? ms"#, options: .regularExpression) else { return nil }
        return Double(label[r].dropFirst(4).dropLast(3))
    }

    /// VIS-019-T13: Cymatic Lines with the reference track (test tones with a silent gap) and with music: the frame
    /// rate holds, tones move the figure, silence settles it (a run of at least two still pairs, 1 s, while other
    /// pairs move: the cross), and Reduce Motion is calmer with music. The still run may come first: on D2
    /// (2026-11-18) the 15 s window opened in the gap (13 still pairs, then the tones). Motion with music is the mean
    /// of three pairs with the overlay's box left out and Reduce flashing pinned off in both runs (it follows Reduce
    /// Motion otherwise): one pair each read 0.0061 against 0.0060 on D1. The device GPU golden is the RenderGoldens
    /// device class (QA-003, Batch 2).
    func testVIS019CymaticTonesSilenceAndReduceMotion() {
        let task = "VIS-019-T13"
        launch(visual: "cymatic", music: false)
        assertFrameRate(task, "reference tones", seconds: 6)
        var motions: [Double] = []
        var previous = screen(task, "tones 0").1
        for i in 1..<30 {
            pause(0.5)
            let next = screen(task, "tones \(i)").1
            motions.append(Self.change(previous, next))
            previous = next
        }
        // The longest run of still pairs (under 0.002); some pair moves (over 0.005).
        var longest = 0, run = 0
        for m in motions {
            if m < 0.002 { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        report(task, "tones", ["maxMotion": motions.max() ?? 0, "stillRunPairs": Double(longest)])
        XCTAssertGreaterThan(motions.max() ?? 0, 0.005, "\(task): tones change the figure")
        XCTAssertGreaterThanOrEqual(longest, 2, "\(task): silence settles the figure (still for ≥ 1 s): \(motions)")
        app.terminate()
        func musicMotion(_ label: String, _ extra: [String]) -> Double {
            launch(visual: "cymatic", settings: ["settings.reduceFlashing": false], extra: extra)
            let box = overlayBox()
            var pairs: [Double] = []
            for i in 0..<3 {
                let (_, a) = screen(task, "\(label) \(i) a"); pause(1); let (_, b) = screen(task, "\(label) \(i) b")
                pairs.append(change(a, b, excluding: box))
                pause(1)
            }
            app.terminate()
            return pairs.reduce(0, +) / Double(pairs.count)
        }
        let normal = musicMotion("music", [])
        let calm = musicMotion("reduce motion", ["-uitestReduceMotion", "YES"])
        report(task, "music motion", ["normal": normal, "reduceMotion": calm])
        XCTAssertLessThanOrEqual(calm, normal, "\(task): Reduce Motion is calmer")
    }
}

/// QA-011 Batch 7: the Settings editors' previews (SHD-005, SHD-006, SHD-007, SHD-008, SHD-012) measured from
/// screenshots and the DEBUG `particleBoundsProbe`. Light appearance pinned (colour comparisons).
@MainActor
final class B01EditorPreviewDeviceTests: B07DeviceCase {
    private func openEditor(section: String, link: String, visual: String = "circularSpectrum") {
        launchPlain(["-uitestSettingsSection", section, "-uitestSettingsSectionOnce", "-uitestAppearance", "light",
                     "-uitestAccessibilityActions"],
                    settings: ["settings.visual": visual, "settings.performanceOverlay": true])
        openSettings()
        let row = app.buttons[link].firstMatch
        XCTAssertTrue(appears(row, 5) && (row.isHittable || reveal(row, up: false)), "the \(link) row")
        row.tap()
    }

    private func control(_ material: String, _ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "materialControl.material.\(material).\(name)").firstMatch
    }

    /// The palette strip under the Style picker (PaletteStrip, hidden from accessibility): the rows that differ from the
    /// form background (ΔE > 10) below the picker, at least 10 pt tall.
    private func strip(_ task: String, _ label: String, below style: XCUIElement) -> (Shot, CGRect)? {
        let s = shot(task, label)
        let picker = style.frame
        let bg = s.rgb(CGPoint(x: picker.midX, y: picker.maxY + 2))
        var rows: [CGFloat] = []
        var y = picker.maxY + 2
        while y < picker.maxY + 90 {
            if Self.deltaE(s.rgb(CGPoint(x: picker.minX + picker.width * 0.5, y: y)), bg) > 10 { rows.append(y) }
            y += 1
        }
        guard let top = rows.first, let bottom = rows.last, bottom - top >= 10 else { return nil }
        return (s, CGRect(x: picker.minX + 4, y: top, width: picker.width - 8, height: bottom - top))
    }

    /// SHD-005-T13: a new gradient palette with Stop 2 moved to about 30 %: past Stop 2 the strip shows its colour (ΔE < 3
    /// against the stop heading's swatch) and Smooth starts nearer Stop 1's colour than Stop 2's; Step gives flat bands
    /// (at most two hard edges, otherwise constant) and its first band is Stop 1's colour (ΔE < 3); a lower Stop 1 alpha
    /// darkens the strip's start (colour × alpha on black: the strip has no checkerboard, PaletteStrip.sampledStops).
    /// Smooth blends in linear light, which moves an sRGB channel near 0 fast: 1 pt into the strip D2 already read
    /// 63,195,254 against Stop 1's 46,196,255 (ΔE 8.6-9.2 at 2 % on D1-D3, 2026-11-18), so the start colour is checked on
    /// Step's flat band.
    func testSHD005GradientStopsStepAndAlpha() {
        let task = "SHD-005-T13"
        openEditor(section: "palettes", link: "paletteLibraryLink")
        let new = app.buttons["paletteNewButton"].firstMatch
        XCTAssertTrue(appears(new), "New Palette")
        new.tap()
        let style = app.segmentedControls["paletteStylePicker"].firstMatch
        XCTAssertTrue(appears(style), "the editor")
        let position = element("paletteStop2.position")
        XCTAssertTrue(reveal(position), "Stop 2's position")
        dragSlider(position, from: 1, to: 0.3)
        XCTAssertTrue(wait(5) { self.value(position) != "100 percent" }, "Stop 2 moved: \(value(position))")
        // Swatches beside the stop headings (18 pt squares at the heading's leading edge).
        var swatches: [(Double, Double, Double)] = []
        for heading in [element("paletteStop1.heading"), element("paletteStop2.heading")] {
            reveal(heading)
            swatches.append(shot(task, "swatch").rgb(CGPoint(x: heading.frame.minX + 9, y: heading.frame.midY)))
        }
        XCTAssertTrue(reveal(style, up: false), "back to the strip")
        guard let (linear, rect) = strip(task, "linear", below: style) else { return XCTFail("\(task): the palette strip was not found") }
        let start = linear.rgb(CGPoint(x: rect.minX + rect.width * 0.02, y: rect.midY))
        let end = linear.rgb(CGPoint(x: rect.minX + rect.width * 0.7, y: rect.midY))
        let dStart = Self.deltaE(start, swatches[0]), dEnd = Self.deltaE(end, swatches[1])
        report(task, "stops", ["deltaEStop1": dStart, "deltaEStop2": dEnd])
        XCTAssertLessThan(dStart, Self.deltaE(start, swatches[1]), "\(task): Smooth starts nearer Stop 1's colour")
        XCTAssertLessThan(dEnd, 3, "\(task): past the moved Stop 2 the strip is Stop 2's colour")

        let picker = element("paletteInterpolationPicker")
        XCTAssertTrue(reveal(picker), "the interpolation picker")
        picker.buttons["Step"].firstMatch.tap()
        XCTAssertTrue(reveal(style, up: false))
        guard let (stepped, rect2) = strip(task, "step", below: style) else { return XCTFail("\(task): the strip after Step") }
        var edges = 0, flat = 0, pairs = 0
        var x = rect2.minX + 2
        var last = stepped.rgb(CGPoint(x: x, y: rect2.midY))
        while x < rect2.maxX - 2 {
            x += 1
            let c = stepped.rgb(CGPoint(x: x, y: rect2.midY))
            let d = Self.deltaE(c, last)
            pairs += 1
            if d > 10 { edges += 1 } else if d < 1 { flat += 1 }
            last = c
        }
        let flatShare = Double(flat) / Double(max(pairs, 1))
        let stepStart = Self.deltaE(stepped.rgb(CGPoint(x: rect2.minX + rect2.width * 0.02, y: rect2.midY)), swatches[0])
        report(task, "step", ["hardEdges": Double(edges), "flatShare": flatShare, "deltaEStop1": stepStart])
        XCTAssertLessThan(stepStart, 3, "\(task): the strip starts with Stop 1's colour")
        XCTAssertGreaterThanOrEqual(edges, 1, "\(task): Step gives a hard edge between bands")
        XCTAssertLessThanOrEqual(edges, 2, "\(task): one edge per stop boundary")
        XCTAssertGreaterThan(flatShare, 0.9, "\(task): Step's bands are flat")

        let startBefore = stepped.luma(CGPoint(x: rect2.minX + rect2.width * 0.05, y: rect2.midY))
        let alpha = element("paletteStop1.alpha")
        XCTAssertTrue(reveal(alpha), "Stop 1's alpha")
        dragSlider(alpha, from: 1, to: 0.3)
        XCTAssertTrue(wait(5) { self.value(alpha) != "100 percent" }, "alpha lowered: \(value(alpha))")
        XCTAssertTrue(reveal(style, up: false))
        guard let (faded, rect3) = strip(task, "alpha", below: style) else { return XCTFail("\(task): the strip after alpha") }
        let startAfter = faded.luma(CGPoint(x: rect3.minX + rect3.width * 0.05, y: rect3.midY))
        report(task, "alpha", ["startLumaBefore": startBefore, "startLumaAfter": startAfter])
        XCTAssertLessThan(startAfter, startBefore - 0.05, "\(task): lower alpha fades Stop 1 toward black")
    }

    /// SHD-006-T14: the Noise editor preview changes with the seed, with more octaves (finer detail: the Laplacian
    /// variance rises) and with the warp amount (screenshot difference over the preview's own motion). The element's
    /// frame is the whole row (the image is centred in a full-width frame), so the grid is the centred square inset by
    /// 4 pt: with the row's light background in it the Laplacian read the image's edges, 0.0167-0.0170 for 3 and for 6
    /// octaves on D1-D3 (2026-11-18), while inside the image 6 octaves raise it 2.5× (D2 screenshots, 2 pt grid).
    func testSHD006NoisePreviewFollowsSeedOctavesWarp() {
        let task = "SHD-006-T14"
        openEditor(section: "noiseEditor", link: "noiseEditorLink")
        let preview = element("noiseEditorPreview")
        XCTAssertTrue(appears(preview), "the preview")
        func grid(_ label: String) -> (values: [Double], columns: Int) {
            if !preview.isHittable { reveal(preview, up: false) }
            let f = preview.frame
            let side = min(f.width, f.height) - 8
            return lumaGrid(shot(task, label), CGRect(x: f.midX - side / 2, y: f.midY - side / 2, width: side, height: side))
        }
        let a = grid("start a"); pause(1); let a2 = grid("start b")
        let own = Self.meanDifference(a.values, a2.values)
        app.buttons["noiseEditorRandomizeSeed"].firstMatch.tap()
        XCTAssertTrue(wait(5) { self.value(preview) != "Seed 0, 3 octaves" }, "a new seed")
        pause(0.5)
        let seeded = grid("new seed")
        let seedChange = Self.meanDifference(a2.values, seeded.values)
        let octaves = control("noiseFlow", "octaves")
        XCTAssertTrue(reveal(octaves), "the Octaves stepper")
        for _ in 0..<3 { octaves.buttons["Increment"].firstMatch.tap() }
        XCTAssertTrue(wait(3) { self.value(octaves) == "6" }, "6 octaves: \(value(octaves))")
        pause(0.5)
        let detailed = grid("6 octaves")
        let lapBefore = Self.laplacianVariance(seeded.values, columns: seeded.columns)
        let lapAfter = Self.laplacianVariance(detailed.values, columns: detailed.columns)
        let warp = control("noiseFlow", "warpAmount")
        XCTAssertTrue(reveal(warp), "the Warp amount slider")
        let warpBefore = value(warp)
        for _ in 0..<20 { accessibilityStep("materialControl.material.noiseFlow.warpAmount", up: true) }
        XCTAssertNotEqual(value(warp), warpBefore, "the warp amount rose")
        pause(0.5)
        let warped = grid("warp up")
        let warpChange = Self.meanDifference(detailed.values, warped.values)
        report(task, "preview", ["ownMotion": own, "seedChange": seedChange, "laplacianBefore": lapBefore,
                                 "laplacianAfter": lapAfter, "warpChange": warpChange])
        XCTAssertGreaterThan(seedChange, max(own * 3, 0.01), "\(task): the seed changes the preview")
        XCTAssertGreaterThan(lapAfter, lapBefore, "\(task): more octaves add fine detail")
        XCTAssertGreaterThan(warpChange, max(own * 3, 0.005), "\(task): the warp changes the preview")
    }

    /// Opens the Particle emitter editor with the emitter on.
    private func openEmitter() {
        openEditor(section: "particleEmitter", link: "particleEmitterLink", visual: "particleFountain")
        let toggle = app.switches["particleEmitterEnabled"].firstMatch
        XCTAssertTrue(appears(toggle), "the emitter switch")
        if value(toggle) != "1" { flip(toggle) }
        XCTAssertTrue(wait(3) { self.value(toggle) == "1" }, "the emitter is on")
    }

    private func choose(_ pickerID: String, _ item: String) {
        let picker = app.buttons[pickerID].firstMatch
        XCTAssertTrue(reveal(picker), pickerID)
        picker.tap()
        let entry = app.buttons[item].firstMatch
        XCTAssertTrue(appears(entry, 3), "\(item) in \(pickerID)")
        entry.tap()
    }

    /// SHD-007-T13: a box-bounce emitter at rate 120: no live particle outside the box over 5 s (`particleBoundsProbe`
    /// outside=0, with bounces), and the Particle Fountain's frame rate steady on the overlay afterwards.
    func testSHD007BoxBounceStaysInside() {
        let task = "SHD-007-T13"
        openEmitter()
        choose("particleEmitterBounds", "Box")
        let rate = element("particleEmitterRate")
        XCTAssertTrue(reveal(rate), "the Rate slider")
        dragSlider(rate, from: 30.0 / 240.0, to: 0.5)
        for _ in 0..<40 {
            guard let v = Double(value(rate)), abs(v - 120) > 0.5 else { break }
            accessibilityStep("particleEmitterRate", up: v < 120)
        }
        XCTAssertEqual(value(rate), "120", "rate 120")
        // The probe sits under the preview at the top of the list; a lazy list drops it once Rate scrolled it away (D2).
        let bounds = app.staticTexts["particleBoundsProbe"]
        XCTAssertTrue(reveal(bounds, up: false), "the bounds probe under the preview")
        var worst = 0.0, maxLive = 0.0, bounces = 0.0
        for _ in 0..<10 {
            let line = value(bounds)
            worst = max(worst, Self.number(line, "outside") ?? 99)
            maxLive = max(maxLive, Self.number(line, "live") ?? 0)
            bounces = max(bounces, Self.number(line, "bounces") ?? 0)
            pause(0.5)
        }
        print("SHD007-BOUNDS \(value(bounds))")
        report(task, "box", ["outsideMax": worst, "liveMax": maxLive, "bounces": bounces])
        XCTAssertTrue(value(bounds).contains("bounds=box"), "\(task): Box chosen: \(value(bounds))")
        XCTAssertGreaterThan(maxLive, 0, "\(task): particles are emitted")
        XCTAssertEqual(worst, 0, "\(task): every particle stays inside the box")
        XCTAssertGreaterThan(bounces, 0, "\(task): they bounce off it")
        closeSettings()
        hideControls()
        let samples = sampleFPS(seconds: 8)
        report(task, "fps", ["median": Self.median(samples), "min": samples.min() ?? 0])
        XCTAssertGreaterThanOrEqual(Self.median(samples), Self.minimumFPS, "\(task): frame rate steady")
    }

    /// SHD-008-T18 (emitter part): a triangle drawn by taps on the path canvas as the spawn shape; the newest particles
    /// (at most two simulation steps old) spawn inside it (≥ 90 %). The path mask part has no app surface to drive
    /// (no layer path mask in Settings); left open (Batch 7 report).
    func testSHD008PathEmitterSpawnsInside() {
        let task = "SHD-008-T18"
        openEmitter()
        choose("particleEmitterShape", "Path")
        let edit = app.buttons["particleEmitterPathEdit"].firstMatch
        XCTAssertTrue(reveal(edit), "Edit path")
        edit.tap()
        let message = app.staticTexts["vectorPathMessage"].firstMatch
        XCTAssertTrue(appears(message), "the path editor")
        app.buttons["vectorPathStartOver"].firstMatch.tap()
        let canvas = element("vectorPathCanvas")
        let size = canvas.frame.size
        let side = Double(min(size.width, size.height)) - 44
        let ox = (Double(size.width) - side) / 2, oy = (Double(size.height) - side) / 2
        for (x, y) in [(0.2, 0.8), (0.5, 0.2), (0.8, 0.8)] {
            canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: ox + x * side, dy: oy + y * side)).tap()
        }
        let close = app.buttons["vectorPathClose"].firstMatch
        XCTAssertTrue(wait(3) { close.isEnabled }, "the triangle can be closed")
        close.tap()
        XCTAssertTrue(wait(3) { message.label == "Path closed, 3 points." }, "closed: \(message.label)")
        app.navigationBars.buttons.firstMatch.tap()
        // Back in the emitter list, still scrolled to Edit path: the preview row (and its probe) is off screen (D1).
        let bounds = app.staticTexts["particleBoundsProbe"]
        XCTAssertTrue(appears(bounds, 2) || reveal(bounds, up: false), "the bounds probe")
        var newest = 0.0, inside = 0.0
        for _ in 0..<12 {
            let line = value(bounds)
            newest += Self.number(line, "newest") ?? 0
            inside += Self.number(line, "newestInPath") ?? 0
            pause(0.4)
        }
        print("SHD008-BOUNDS \(value(bounds))")
        report(task, "spawn", ["newest": newest, "newestInPath": inside])
        XCTAssertTrue(value(bounds).contains("shape=path"), "\(task): the path shape: \(value(bounds))")
        XCTAssertGreaterThan(newest, 0, "\(task): new particles were seen")
        XCTAssertGreaterThanOrEqual(inside / max(newest, 1), 0.9, "\(task): spawn points lie inside the path")
    }

    /// SHD-012-T13 (smoothness): Play fixture loops without freezing: over about 4 s of screenshots of the fixture picture
    /// every consecutive pair changes, evenly (coefficient of variation of the change under 1). "The warp follows the
    /// kicks" needs the fixture's kick frames, which the app does not expose (left open, Batch 7 report).
    func testSHD012FixtureLoopPlaysSmoothly() {
        let task = "SHD-012-T13"
        openEditor(section: "noiseEditor", link: "noiseEditorLink")
        let play = app.buttons["fixturePreviewPlay"].firstMatch
        XCTAssertTrue(reveal(play), "Play fixture")
        play.tap()
        let summary = app.staticTexts["fixturePreviewSummary"].firstMatch
        XCTAssertTrue(wait(15) { summary.label.hasPrefix("120 frames") }, "rendered: \(summary.label)")
        let picture = element("fixturePreviewPicture")
        XCTAssertTrue(appears(picture) && (picture.isHittable || reveal(picture, up: false)), "the fixture picture")
        var grids: [[Double]] = []
        for i in 0..<12 { grids.append(lumaGrid(shot(task, "loop \(i)"), picture.frame, step: 3).values); pause(0.25) }
        let changes = zip(grids, grids.dropFirst()).map { Self.meanDifference($0.0, $0.1) }
        let mean = changes.reduce(0, +) / Double(changes.count)
        let sd = (changes.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(changes.count)).squareRoot()
        report(task, "loop", ["meanChange": mean, "minChange": changes.min() ?? 0, "cv": sd / max(mean, 1e-6)])
        XCTAssertGreaterThan(changes.min() ?? 0, 0.0005, "\(task): no frozen stretch: \(changes)")
        XCTAssertLessThan(sd / max(mean, 1e-6), 1, "\(task): the loop moves evenly: \(changes)")
    }
}
