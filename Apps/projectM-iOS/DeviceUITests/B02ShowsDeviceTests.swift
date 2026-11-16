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
