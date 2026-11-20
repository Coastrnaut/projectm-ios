// B05AudioMicDeviceTests.swift — QA-011 Batch 3 (audio), the Microphone cases, automated on the device with the Mac
// as the sound source: each test prints `MAC-DO {"module":"audio","action":"play",…}` and
// scripts/mac_device_driver.py plays the music fixture on the Mac's speaker (`afplay`), with the device next to it.
// The test waits on the app's probes, never on the Mac. Needs the microphone permission already granted (the
// prompt-flow batch, owner rule 14 as amended 2026-11-18); a test that finds the explainer or the prompt fails with
// that instruction and never taps the prompt.
// AUD-007-T16 (built-in microphone named), AUD-008-T13 (microphone trim), AUD-009-T13 (Mid/Side and the
// microphone), AUD-011-T12 (noise gate), AUD-012-T20 (source switches), AUD-015-T13 (background per source),
// PERF-013-T12 (audio age with the microphone).
import UIKit
import XCTest

@MainActor
final class B05AudioMicDeviceTests: DeviceAcceptanceCase {
    override func tearDown() async throws {
        macStopAudio()
        try await super.tearDown()
    }

    /// Launches with the Microphone source (`-autostart microphone`) and typed settings.
    private func launchMicrophone(_ task: String, visual: String = "linearSpectrum", settings: [String: Any] = [:],
                                  extra: [String] = []) {
        XCUIDevice.shared.orientation = .portrait
        var values: [String: Any] = ["settings.performanceOverlay": true]
        values.merge(settings) { (_: Any, given: Any) -> Any in given }
        values["settings.visual"] = visual
        let json = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "microphone", "-uitestUnlocked", "NO",
                               "-uitestDefaults", json, "-uitestSessionLog", "-uitestSessionEvents"] + extra
        app.launch()
        let started = wait(15) { self.sourceIndicator.hasPrefix("Microphone · ") }
        if !started, SystemUI.springboard.alerts.firstMatch.exists || app.buttons["Continue"].exists {
            XCTFail("\(task): the microphone permission is not answered on this device; run PromptFlowDeviceTests first")
        }
        XCTAssertTrue(started, "\(task): the microphone started: \(sourceIndicator)")
        _ = wait(8) { !self.app.otherElements["controls"].exists }
    }

    // MARK: Preflight: does the microphone hear the Mac?

    /// The result of the once-per-run check that the device's microphone hears the Mac's speaker; nil before it ran.
    private static var macAudible: (heard: Bool, detail: String)?

    /// Median of `count` readings of the gate probe's detector level (dB), 0.2 s apart.
    private func envelopeDb(_ count: Int) -> Double {
        var values: [Double] = []
        for _ in 0..<count {
            if let v = Double(probeFields("gateProbe")["envDb"] ?? "") { values.append(v) }
            pause(0.2)
        }
        return values.isEmpty ? -200 : Self.median(values)
    }

    /// Checks once per run, before any test that needs sound from the Mac, that the microphone hears it: the gate
    /// probe's level with the Mac silent, then with the music fixture playing. QA-011 pass 9 (D2, 2026-11-19): the Mac
    /// driver played every request on time (its MAC-DONE lines match the tests' MAC-DO ids), yet the level fell from
    /// -75 dB (quiet) to -81 dB (music), so five tests failed later with gate, trim and "silent" messages; in full 8 the
    /// same iPad read -61.5 dB quiet and the music opened the gate. Without the sound reaching the microphone those
    /// tests prove nothing about the app, so they stop at once with this environment message instead.
    @discardableResult
    private func requireMicHearsMac(_ task: String) -> Bool {
        if Self.macAudible == nil {
            launchMicrophone("mic preflight", settings: ["settings.noiseGate.enabled": true], extra: ["-uitestGateProbe"])
            pause(2)
            let quiet = envelopeDb(5)
            macPlayMusic(seconds: 10)
            pause(2)
            var loud = -200.0
            let end = Date().addingTimeInterval(6)
            while Date() < end { loud = max(loud, envelopeDb(3)) }
            macStopAudio()
            app.terminate()
            let heard = loud - quiet >= 10
            report("QA-011", "mic preflight", ["quietDb": quiet, "musicDb": loud, "heard": heard ? 1 : 0])
            Self.macAudible = (heard, String(format: "quiet %.1f dB, Mac music %.1f dB", quiet, loud))
        }
        guard let result = Self.macAudible, !result.heard else { return true }
        XCTFail("\(task): ENVIRONMENT, not the app: the microphone does not hear the Mac's speaker (\(result.detail); "
                + "needs at least +10 dB). Check that scripts/mac_device_driver.py follows this run (MAC-DONE lines), the "
                + "Mac's output device and volume (its MAC-DONE line for audio.play names them), and that the device lies "
                + "next to the Mac's speaker with its microphones uncovered.")
        return false
    }

    // MARK: AUD-007-T16

    /// The route indicator names the built-in microphone in Microphone mode and no capture source.
    func testAUD007MicrophoneModeNamesTheBuiltInInput() {
        let task = "AUD-007-T16"
        launchMicrophone(task)
        revealControls()
        let route = app.descendants(matching: .any)["routeIndicator"].firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 5), "the route indicator is in the controls")
        let label = route.label
        report(task, "microphone route", ["namesMicrophone": label.contains("Microphone") ? 1 : 0])
        // The element's label is the VoiceOver label, "Audio input: iPad Microphone" (UIStrings.routeAccessibilityLabel);
        // the visible text is "Input: …". QA-011 full 8 and pass 9 (D2, 2026-11-19) read the VoiceOver label.
        XCTAssertTrue(label.hasPrefix("Audio input:") && label.contains("Microphone"), "names the built-in input: \(label)")
        XCTAssertFalse(label.contains("System/App Capture") || label.lowercased().contains("captur"), "no capture source named")
    }

    // MARK: AUD-008-T13 (microphone part)

    private func effectiveGlow() -> Double? {
        let text = app.staticTexts["glowModulation"].label
        guard text.hasPrefix("bound"), let range = text.range(of: "effective ") else { return nil }
        return Double(text[range.upperBound...])
    }

    /// Mean glow-bound band level over ~10 s with the Mac playing.
    private func micLevel(_ task: String, decibels: Double) -> Double {
        launchMicrophone(task, visual: "circularSpectrum",
                         settings: ["settings.circularSpectrum.glow": true, "settings.inputTrim.decibels": decibels],
                         extra: ["-uitestBindGlowToLevel"])
        macPlayMusic(seconds: 25)
        pause(4)
        var samples: [Double] = []
        for _ in 0..<40 { if let v = effectiveGlow() { samples.append(v) }; pause(0.25) }
        macStopAudio()
        let mean = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
        report(task, "mic \(Int(decibels)) dB", ["levelMean": mean, "samples": Double(samples.count)])
        app.terminate()
        return mean
    }

    /// +12 dB of trim makes the band level at least 20 % higher than 0 dB for the same Mac playback; after a real
    /// alarm the trim stays and the analysis resumes.
    func testAUD008MicrophoneTrimRaisesTheBands() {
        let task = "AUD-008-T13"
        guard requireMicHearsMac(task) else { return }
        let flat = micLevel(task, decibels: 0)
        let boosted = micLevel(task, decibels: 12)
        XCTAssertGreaterThan(flat, 0, "the microphone hears the Mac")
        XCTAssertGreaterThan(boosted, flat * 1.2, "+12 dB drives the bands harder: \(flat) → \(boosted)")
        launchMicrophone(task, visual: "circularSpectrum",
                         settings: ["settings.circularSpectrum.glow": true, "settings.inputTrim.decibels": 12.0],
                         extra: ["-uitestBindGlowToLevel"])
        macPlayMusic(seconds: 40)   // before the alarm: a running microphone in a quiet room reads "silent"
        realInterruption(task, .clockTimer, whilePaused: false, ramp: false)
        let resumed = wait(10) { (self.effectiveGlow() ?? 0) > flat }
        report(task, "after alarm", ["analysisResumed": resumed ? 1 : 0])
        XCTAssertTrue(resumed, "after the interruption the trimmed analysis resumes")
    }

    // MARK: AUD-009-T13

    /// Mid and Side on In-App Playback (left-only and phase-inverted fixtures), then the microphone: a mono room sound
    /// moves Mid and leaves Side still.
    func testAUD009MidSideAndMicrophone() {
        let task = "AUD-009-T13"
        var motion: [String: Double] = [:]
        for (fixture, mode) in [("music-fixture-inverted.m4a", "mid"), ("music-fixture-inverted.m4a", "side"),
                                ("music-fixture-left.m4a", "mid"), ("music-fixture-left.m4a", "side")] {
            launch(visual: "linearSpectrum", settings: ["settings.analysisChannel.mode": mode], fixture: fixture)
            motion["\(fixture) \(mode)"] = peakMotion(task, "\(fixture) \(mode)")
            app.terminate()
        }
        let invMid = motion["music-fixture-inverted.m4a mid"] ?? 0, invSide = motion["music-fixture-inverted.m4a side"] ?? 0
        XCTAssertLessThan(invMid, invSide / 3, "inverted feed: Mid (L+R) cancels, Side moves: mid \(invMid), side \(invSide)")
        XCTAssertGreaterThan(motion["music-fixture-left.m4a mid"] ?? 0, 0.004, "left-only: Mid follows")
        XCTAssertGreaterThan(motion["music-fixture-left.m4a side"] ?? 0, 0.004, "left-only: Side follows")
        guard requireMicHearsMac(task) else { return }
        for mode in ["mid", "side"] {
            launchMicrophone(task, settings: ["settings.analysisChannel.mode": mode])
            macPlayMusic(seconds: 15)
            pause(3)
            motion["mic \(mode)"] = peakMotion(task, "mic \(mode)")
            macStopAudio()
            app.terminate()
        }
        let micMid = motion["mic mid"] ?? 0, micSide = motion["mic side"] ?? 0
        XCTAssertLessThan(micSide, micMid / 2, "a mono microphone: Side stays far stiller than Mid: side \(micSide), mid \(micMid)")
    }

    // MARK: AUD-011-T12

    /// Gate on, Mac silent: the gate stays closed and the bars still; music opens it within 0.1 s (of the input
    /// crossing the threshold); it closes 0.25 ± 0.1 s after the music stops; after a real alarm it still works; In-App
    /// Playback is not gated.
    func testAUD011NoiseGate() {
        let task = "AUD-011-T12"
        guard requireMicHearsMac(task) else { return }
        launchMicrophone(task, settings: ["settings.noiseGate.enabled": true], extra: ["-uitestGateProbe"])
        pause(3)
        let quiet = probeFields("gateProbe")
        let still = peakMotion(task, "quiet room")
        report(task, "quiet", ["envDb": Double(quiet["envDb"] ?? "") ?? 0, "motion": still])
        XCTAssertEqual(quiet["phase"], "closed", "a quiet room keeps the gate closed: \(probeValue("gateProbe"))")
        XCTAssertLessThan(still, 0.003, "the bars stay still")
        func cycle(_ label: String) {
            let opens = probeNumber("gateProbe", "opens"), closes = probeNumber("gateProbe", "closes")
            macPlayMusic(seconds: 6)
            XCTAssertTrue(wait(10) { self.probeNumber("gateProbe", "opens") > opens }, "\(label): music opens the gate: \(probeValue("gateProbe"))")
            let openMs = probeNumber("gateProbe", "openMs")
            XCTAssertTrue(wait(12) { self.probeNumber("gateProbe", "closes") > closes }, "\(label): the gate closes after the music")
            let closeMs = probeNumber("gateProbe", "closeMs")
            report(task, label, ["openMs": openMs, "closeMs": closeMs])
            XCTAssertLessThan(openMs, 100, "\(label): opens at once")
            XCTAssertEqual(closeMs, 250, accuracy: 100, "\(label): closes about 0.25 s after the input falls")
        }
        cycle("first")
        realInterruption(task, .clockTimer, whilePaused: false, ramp: false)
        cycle("after alarm")
        app.terminate()
        launch(visual: "linearSpectrum", settings: ["settings.noiseGate.enabled": true], extra: ["-uitestGateProbe"])
        pause(2)
        let playbackReads = probeNumber("gateProbe", "reads")
        pause(2)
        XCTAssertEqual(probeNumber("gateProbe", "reads"), playbackReads, "In-App Playback is never gated")
        XCTAssertGreaterThan(peakMotion(task, "in-app playback"), 0.004, "In-App Playback still moves the bars")
    }

    // MARK: AUD-012-T20

    /// The indicator texts seen while `action` runs (polled every 0.1 s).
    private func indicatorSequence(for seconds: Double, _ action: () -> Void) -> [String] {
        var seen: [String] = []
        action()
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let label = sourceIndicator
            if !label.isEmpty, seen.last != label { seen.append(label) }
            pause(0.1)
        }
        return seen
    }

    private func switchTo(_ mode: String) {
        revealControls()
        app.buttons["switchSource"].tap()
        let target = app.buttons["switchSource:\(mode)"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(mode) is offered")
        target.tap()
    }

    /// Microphone ↔ In-App Playback with a lost route, an interruption and a trip to the background during a switch:
    /// the indicator ends on the new source's live status each time and the visual keeps moving with the new audio.
    func testAUD012SwitchesNeverFreezeOnOldAudio() {
        let task = "AUD-012-T20"
        guard requireMicHearsMac(task) else { return }
        launch(visual: "linearSpectrum", extra: ["-uitestSessionLog", "-uitestSessionEvents", "-uitestKeepControls"])
        macPlayMusic(seconds: 120)
        let steps: [(String, String, () -> Void)] = [
            ("microphone", "Microphone", {}),
            ("inAppPlayback", "In-App Playback", { self.tapPanel("session:routeLost") }),
            ("microphone", "Microphone", { self.tapPanel("session:interruptBegan"); self.tapPanel("session:interruptEndedResume") }),
            ("inAppPlayback", "In-App Playback", {
                XCUIDevice.shared.press(.home); self.pause(2); self.app.activate(); _ = self.wait(10) { self.app.state == .runningForeground }
            }),
        ]
        for (i, (mode, name, during)) in steps.enumerated() {
            let seen = indicatorSequence(for: 8) {
                switchTo(mode)
                during()
            }
            print("DEVICE-ACCEPT-NOTE \(task) step \(i) \(mode): \(seen.joined(separator: " → "))")
            // A lost route or a background trip may leave In-App Playback paused. The microphone has no transport
            // (QA-011 pass 9, D2: "transportPlayPause is shown" failed on a silent microphone step).
            if mode == "inAppPlayback", !sourceIndicator.hasSuffix("· Active audio"), sourceIndicator.hasPrefix(name) {
                tapTransport("transportPlayPause")
            }
            let live = waitForIndicator("· Active audio", 10) && sourceIndicator.hasPrefix(name)
            let moving = peakMotion(task, "step \(i) \(mode)")
            report(task, "step \(i) \(mode)", ["live": live ? 1 : 0, "states": Double(seen.count)])
            XCTAssertTrue(live, "step \(i): ends on \(name) with live audio: \(sourceIndicator) (\(seen))")
            XCTAssertGreaterThan(moving, 0.003, "step \(i): the visual follows the new audio, not frozen")
        }
    }

    // MARK: AUD-015-T13

    /// Per source, Home and return, and Home then the app's icon on the Home Screen: Microphone stops away and
    /// restarts on return; In-App Playback pauses away and resumes on return (contract background-policy.md).
    func testAUD015BackgroundPerSource() {
        let task = "AUD-015-T13"
        guard requireMicHearsMac(task) else { return }
        for source in ["microphone", "inAppPlayback"] {
            for viaIcon in [false, true] {
                if source == "microphone" { launchMicrophone(task); macPlayMusic(seconds: 30) } else { launch(visual: "linearSpectrum") }
                XCTAssertTrue(waitForIndicator("· Active audio", 15), "\(source) live: \(sourceIndicator)")
                XCUIDevice.shared.press(.home)
                _ = wait(10) { self.app.state != .runningForeground }
                pause(3)
                if viaIcon {
                    // On iPad the icon is on the Home Screen and in the Dock (recent apps): QA-011 full 8 and pass 9
                    // (D2) failed with "Multiple matching elements found". Tap the first one that can be hit.
                    let icons = SystemUI.springboard.icons.matching(identifier: SystemUI.appDisplayName)
                    XCTAssertTrue(icons.firstMatch.waitForExistence(timeout: 5), "the app's Home Screen icon")
                    let hittable = icons.allElementsBoundByIndex.first { $0.isHittable } ?? icons.firstMatch
                    hittable.tap()
                } else {
                    app.activate()
                }
                _ = wait(10) { self.app.state == .runningForeground }
                let back = waitForIndicator("· Active audio", 15)
                let label = "\(source) \(viaIcon ? "icon" : "activate")"
                report(task, label, ["resumed": back ? 1 : 0, "sourceStarts": Double(probeValue("sourceStarts")) ?? -1])
                XCTAssertTrue(back, "\(label): live again after the return: \(sourceIndicator)")
                macStopAudio()
                app.terminate()
            }
        }
    }

    // MARK: PERF-013-T12

    /// A native visual on the microphone with the Mac playing: the overlay's audio age stays under 100 ms at every
    /// 10 s reading and no drift verdict appears. 180 s by default; the spec's 5 minutes with
    /// `TEST_RUNNER_PERF013_SECONDS=300`.
    func testPERF013MicrophoneAudioAge() {
        let task = "PERF-013-T12"
        let seconds = Int(ProcessInfo.processInfo.environment["PERF013_SECONDS"] ?? "") ?? 180
        launchMicrophone(task, visual: "linearSpectrum")
        macPlayMusic(seconds: seconds + 20)
        pause(5)
        var ages: [Double] = []
        var drift = false
        var driftPPM: [Double] = []
        for _ in 0..<(seconds / 10) {
            pause(10)
            let label = overlayLabel
            if let range = label.range(of: #"audio age ([0-9.]+) ms"#, options: .regularExpression) {
                ages.append(Double(label[range].split(separator: " ")[2]) ?? 999)
            }
            if label.contains(", drift ") {
                drift = true
                // The estimate, for deciding whether a detection is false (PERF-013-S5): "drift <ppm> ppm corrected".
                if let range = label.range(of: #"drift -?[0-9.]+ ppm"#, options: .regularExpression) {
                    driftPPM.append(Double(label[range].split(separator: " ")[1]) ?? 0)
                }
            }
            print("DEVICE-ACCEPT-NOTE \(task) reading \(ages.count): \(label.range(of: "audio age").map { String(label[$0.lowerBound...].prefix(120)) } ?? label.prefix(120).description)")
        }
        report(task, "\(seconds) s", ["ageMax": ages.max() ?? -1, "ageMedian": Self.median(ages), "readings": Double(ages.count),
                                      "drift": drift ? 1 : 0, "driftPPMFirst": driftPPM.first ?? 0,
                                      "driftPPMLast": driftPPM.last ?? 0])
        XCTAssertGreaterThanOrEqual(ages.count, seconds / 20, "the audio age line was readable: \(overlayLabel.prefix(200))")
        XCTAssertLessThan(ages.max() ?? 999, 100, "audio age < 100 ms at every reading: \(ages)")
        XCTAssertFalse(drift, "no drift verdict: estimates \(driftPPM) ppm, ages \(ages)")
    }
}
