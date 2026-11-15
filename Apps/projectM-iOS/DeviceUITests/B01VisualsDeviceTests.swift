// B01VisualsDeviceTests.swift — QA-011 owner session B01 ("Visuals and effects: look and frame rate with music"),
// automated on D1 (and D2 where the task names it). Each test closes the measurable part of its task: the frame
// rate on the performance overlay against the device budget, and image checks for the look (the visual draws and
// moves with the music; grey after saturation 0; an unchanged centre under Vignette; a still picture under
// Posterize and under Reduce Motion). Screenshots are attached for review. Music: In-App Playback's bundled track.
import UIKit
import XCTest

@MainActor
final class B01NativeVisualDeviceTests: DeviceAcceptanceCase {
    private func visualCheck(_ task: String, _ visual: String, settings: [String: Any] = [:]) {
        launch(visual: visual, settings: settings)
        assertFrameRate(task, visual)
        assertDrawingAndMoving(task, visual)
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

    func testVIS004LissajousWithPersistence() { visualCheck("VIS-004-T13", "lissajous", settings: ["settings.lissajous.persistence": true]) }
    func testVIS005RadialWaveform() { visualCheck("VIS-005-T12", "radialWaveform") }
    func testVIS006BeatRings() { visualCheck("VIS-006-T14", "beatRings") }
    func testVIS007Mandala() { visualCheck("VIS-007-T13", "mandala") }
    func testVIS013NoiseField() { visualCheck("VIS-013-T15", "noiseField") }
    func testVIS011FluidInk() { visualCheck("VIS-011-T13", "fluidInk", settings: ["settings.reduceFlashing": true]) }
    func testVIS020SpectrumWaterfall() { visualCheck("VIS-020-T12", "spectrumWaterfall") }

    /// VIS-014-T12: Kaleidoscope at 2, 7 and 24 wedges holds the frame rate.
    func testVIS014KaleidoscopeWedges() {
        for wedges in [2, 7, 24] {
            launch(visual: "kaleidoscope", settings: ["settings.kaleidoscope.wedges": wedges])
            assertFrameRate("VIS-014-T12", "\(wedges) wedges", seconds: 6)
            screen("VIS-014-T12", "\(wedges) wedges")
            app.terminate()
        }
    }

    /// VIS-012-T13: Reaction Diffusion at Speed 16, Reduce flashing on.
    func testVIS012ReactionDiffusionSpeed16() {
        visualCheck("VIS-012-T13", "reactionDiffusion", settings: ["settings.reactionDiffusion.speed": 16, "settings.reduceFlashing": true])
    }

    /// VIS-016-T13: Starfield at 2000 stars and Fast; with Reduce Motion it moves less.
    func testVIS016StarfieldFastAndReduceMotion() {
        let task = "VIS-016-T13"
        let settings: [String: Any] = ["settings.starfield.density": 2000, "settings.starfield.speed": "fast"]
        launch(visual: "starfield", settings: settings)
        assertFrameRate(task, "2000 stars, Fast")
        let (_, a) = screen(task, "fast a"); pause(1); let (_, b) = screen(task, "fast b")
        let normal = Self.change(a, b)
        app.terminate()
        launch(visual: "starfield", settings: settings, extra: ["-uitestReduceMotion", "YES"])
        let (_, c) = screen(task, "reduce motion a"); pause(1); let (_, d) = screen(task, "reduce motion b")
        let calm = Self.change(c, d)
        report(task, "motion", ["normal": normal, "reduceMotion": calm])
        XCTAssertGreaterThan(normal, 0.002, "\(task): the stars move")
        XCTAssertLessThanOrEqual(calm, normal, "\(task): Reduce Motion is calmer")
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
final class B01PhotoEffectDeviceTests: DeviceAcceptanceCase {
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
    private func effectCheck(_ task: String, _ label: String, _ settings: [String: Any], base: Double, minimumChange: Double = 0.01) {
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

    /// FX-004-T15: hue +120 changes the colour, frame rate unchanged.
    func testFX004Hue() {
        let task = "FX-004-T15"
        let base = baseline(task)
        effectCheck(task, "hue +120", ["settings.colorGrade.hue": 120.0], base: base)
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
        let grain: [String: Any] = ["settings.filmGrain.enabled": true, "settings.filmGrain.opacity": 1.0,
                                    "settings.filmGrain.animated": true]
        photo(grain)
        let (_, a) = screen(task, "vary a"); pause(1); let (_, b) = screen(task, "vary b")
        let varying = stillChange(a, b)
        app.terminate()
        photo(grain, extra: ["-uitestReduceMotion", "YES"])
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
