// B13ExtraDeviceTests.swift — QA-011 device tasks that need no person, automated on the device with DEBUG probes.
// MED-011-T13: Show Clock on the Text and Photo visuals reads the device's own time (probe `clockProbe`), changes at
// the minute, and 12-hour with seconds changes every second. The "a REC-003 recording contains the clock" part is
// not automated (no probe reads the recorded pixels); the clock is a compositor layer, so REC-003 records it.
// AUD-008-T13 (In-App Playback part): input trim +12 dB drives the analysis harder than 0 dB (the mean band level
// bound to the glow, `-uitestBindGlowToLevel`, AUD-008-R11) while the source stays Active audio. Headphones and a
// phone call need a person and stay in the owner's session.
// REC-003-T23 (Circular Spectrum part): a 60 s recording at the drawable's own size (Max profile) reads back at
// about 60 s; frame rate, written and dropped slots, file size and thermal state are reported. The Camera part can
// raise a permission prompt, so it stays with the human-testing group (autotester.md, owner rule 14).
// FX-019-T23 is not here: no DEBUG hook selects a strobing preset on a device and the projectM envelope's gain is
// not exposed to the app (see the QA-011 report).
import AVFAudio
import UIKit
import XCTest

@MainActor
final class B13ExtraDeviceTests: DeviceAcceptanceCase {
    // MARK: Helpers

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    // MARK: MED-011-T13 (clock)

    /// The clock's stored settings as `-uitestDefaults` JSON data (ClockOverlaySettings version 1; style default).
    private static func clockSettings(twelveHour: Bool, seconds: Bool) -> [String: Any] {
        let stored: [String: Any] = ["version": 1, "isShown": true,
                                     "hourCycle": twelveHour ? "twelveHour" : "twentyFourHour", "showsSeconds": seconds]
        let wrapped: [String: Any] = ["$json": stored]
        return ["settings.clock.overlay": wrapped]
    }

    /// "<text|none> drawn=<frames>" → (text, frames).
    private func clockProbe() -> (text: String, drawn: Int) {
        let value = (app.staticTexts["clockProbe"].value as? String) ?? ""
        guard let range = value.range(of: " drawn=") else { return ("", -1) }
        return (String(value[..<range.lowerBound]), Int(value[range.upperBound...]) ?? -1)
    }

    /// The device's time formatted the app's way (ClockHourCycle patterns, current locale and time zone).
    private static func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// The device time's strings over the last `window` seconds (the probe refreshes every 0.25 s).
    private static func recentTimes(pattern: String, window: Double = 1.5) -> Set<String> {
        let now = Date()
        return Set(stride(from: 0.0, through: window, by: 0.25).map { formatted(now.addingTimeInterval(-$0), pattern: pattern) })
    }

    /// Launches `visual` with the clock shown and checks the drawn string is the device's time.
    private func launchClock(_ task: String, visual: String, extra: [String] = [], twelveHour: Bool, seconds: Bool,
                             pattern: String) {
        launch(visual: visual, settings: Self.clockSettings(twelveHour: twelveHour, seconds: seconds), extra: extra)
        XCTAssertTrue(wait(10) { self.clockProbe().drawn > 0 }, "\(visual): the clock layer draws: \(clockProbe())")
        let shown = clockProbe().text
        let expected = Self.recentTimes(pattern: pattern)
        report(task, "\(visual) \(pattern)", ["drawn": Double(clockProbe().drawn), "matches": expected.contains(shown) ? 1 : 0])
        print("B13 \(task) \(visual): shown \(shown), device \(expected.sorted())")
        XCTAssertTrue(expected.contains(shown), "\(visual): the clock shows the device time: \(shown), expected \(expected.sorted())")
        screen(task, "\(visual) clock")   // attached for the readability review
    }

    /// MED-011-T13: Text and Photo show the device time; on Text it changes at the minute and still matches.
    func testMED011ClockShowsTheDeviceTimeAndChangesAtTheMinute() {
        let task = "MED-011-T13"
        launchClock(task, visual: "photo", extra: ["-uitestSeedPhoto", "pattern"], twelveHour: false, seconds: false,
                    pattern: "HH:mm")
        app.terminate()
        launchClock(task, visual: "text", twelveHour: false, seconds: false, pattern: "HH:mm")
        let before = clockProbe().text
        // Wait for the next minute (at most ~62 s), then 2 s for the tick and the probe.
        let changed = wait(64) { self.clockProbe().text != before }
        pause(0.5)
        let after = clockProbe().text
        let expected = Self.recentTimes(pattern: "HH:mm")
        report(task, "minute change", ["changed": changed ? 1 : 0, "matches": expected.contains(after) ? 1 : 0])
        print("B13 \(task) minute: \(before) -> \(after)")
        XCTAssertTrue(changed, "the clock changes at the minute: still \(before)")
        XCTAssertTrue(expected.contains(after), "after the minute it shows the device time: \(after), expected \(expected.sorted())")
    }

    /// MED-011-T13: 12-hour with seconds changes once a second and always shows the device time.
    func testMED011TwelveHourWithSecondsUpdatesEachSecond() {
        let task = "MED-011-T13"
        let pattern = "h:mm:ss a"
        launchClock(task, visual: "text", twelveHour: true, seconds: true, pattern: pattern)
        var seen: [String] = []
        var mismatches = 0
        let end = Date().addingTimeInterval(6)
        while Date() < end {
            let text = clockProbe().text
            if text != seen.last {
                seen.append(text)
                if !Self.recentTimes(pattern: pattern).contains(text) { mismatches += 1 }
            }
            pause(0.2)
        }
        report(task, "12-hour seconds", ["distinct": Double(seen.count), "mismatches": Double(mismatches)])
        print("B13 \(task) seconds: \(seen)")
        // 6 s of sampling: at least 5 distinct strings (one a second), none off the device time.
        XCTAssertGreaterThanOrEqual(seen.count, 5, "the seconds update each second: \(seen)")
        XCTAssertLessThanOrEqual(seen.count, 8, "no more than one change a second: \(seen)")
        XCTAssertEqual(mismatches, 0, "every string is the device time: \(seen)")
        XCTAssertTrue(seen.allSatisfy { $0.contains(":") && $0.split(separator: ":").count == 3 }, "h:mm:ss: \(seen)")
    }

    // MARK: AUD-008-T13 (input trim)

    /// The effective glow intensity from "bound, manual 0.50, effective 0.73" (the mean band level, AUD-008-R11).
    private func effectiveGlow() -> Double? {
        let text = app.staticTexts["glowModulation"].label
        guard text.hasPrefix("bound"), let range = text.range(of: "effective ") else { return nil }
        return Double(text[range.upperBound...])
    }

    /// Plays the music fixture at `decibels` of trim; returns the mean and max effective glow over ~10 s.
    private func analysisLevel(_ task: String, decibels: Double) -> (mean: Double, max: Double) {
        launch(visual: "circularSpectrum",
               settings: ["settings.circularSpectrum.glow": true, "settings.inputTrim.decibels": decibels],
               extra: ["-uitestBindGlowToLevel"])
        XCTAssertTrue(wait(10) { self.effectiveGlow() != nil }, "\(decibels) dB: the glow follows the level: "
                      + app.staticTexts["glowModulation"].label)
        var samples: [Double] = []
        for _ in 0..<40 {
            if let value = effectiveGlow() { samples.append(value) }
            pause(0.25)
        }
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch.label
        let mean = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
        // The system output volume (the trim never touches playback; it is read for the record, not asserted).
        let volume = Double(AVAudioSession.sharedInstance().outputVolume)
        report(task, "\(Int(decibels)) dB", ["levelMean": mean, "levelMax": samples.max() ?? 0,
                                              "samples": Double(samples.count), "outputVolume": volume])
        XCTAssertGreaterThanOrEqual(samples.count, 20, "\(decibels) dB: the readout was readable")
        XCTAssertTrue(overlay.contains("Active audio"), "\(decibels) dB: playback stays Active audio: \(overlay.prefix(120))")
        app.terminate()
        return (mean, samples.max() ?? 0)
    }

    /// AUD-008-T13: +12 dB makes the analysis react more strongly than 0 dB; playback is not changed by the trim.
    func testAUD008PlusTwelveDecibelsDrivesTheAnalysisHarder() {
        let task = "AUD-008-T13"
        let flat = analysisLevel(task, decibels: 0)
        let raised = analysisLevel(task, decibels: 12)
        report(task, "compare", ["flatMean": flat.mean, "raisedMean": raised.mean, "difference": raised.mean - flat.mean])
        XCTAssertGreaterThan(flat.max, 0, "0 dB: the music moves the analysis")
        // A relative margin: the band level's scale differs by device (0.035 on D3, 0.20 on D1 at 0 dB, 2026-11-18),
        // while +12 dB raised it by 36-55 % on D1-D3. An absolute 0.02 failed D3 at +46 %.
        XCTAssertGreaterThan(raised.mean, flat.mean * 1.2,
                             "+12 dB reads a mean band level at least 20 % higher: \(raised.mean) vs \(flat.mean) at 0 dB")
    }

    // MARK: REC-003-T23 (60 s recording)

    private var recordingProbe: String { (app.staticTexts["videoRecordingProbe"].value as? String) ?? "" }

    /// "fps=<n> frames=<n> dropped=<n> bytes=<n>" → values.
    private func recordingFacts() -> [String: Int] {
        let text = (app.staticTexts["recordingFacts"].value as? String) ?? ""
        var values: [String: Int] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=")
            if kv.count == 2, let v = Int(kv[1]) { values[String(kv[0])] = v }
        }
        return values
    }

    /// REC-003-T23: 60 s of the Circular Spectrum at the drawable's size (Max; High or Standard when the device refuses
    /// Max) reads back at the recorded length; frame rate, slots, size and thermal state are reported. Drops are
    /// reported, not asserted (the iPads were measured to drop slots).
    func testREC003SixtySecondCircularSpectrumRecording() {
        let task = "REC-003-T23"
        let thermalBefore = ProcessInfo.processInfo.thermalState
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        var profileUsed: String?
        var started = Date()
        for profile in ["max", "high", "standard"] {
            launch(visual: "circularSpectrum", settings: ["settings.recording.qualityProfile": profile],
                   extra: ["-uitestRecordingDirectory", "B13ExtraDeviceTests"])
            showControls()
            let button = app.buttons["record"]
            XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "\(profile): Record is offered (\(button.label))")
            button.tap()
            started = Date()
            if wait(5, { indicator.exists }) {
                profileUsed = profile
                break
            }
            report(task, "\(profile) refused", ["refused": 1])
            print("B13 \(task) \(profile) did not start: \(recordingProbe)")
            app.terminate()
        }
        guard let profile = profileUsed else { return XCTFail("no profile started a recording: \(recordingProbe)") }
        // One overlay reading a second while recording, until the indicator reaches 1:00.
        var fps: [Double] = []
        while Date().timeIntervalSince(started) < 75, !(indicator.exists && indicator.label >= "Recording, 1:00") {
            pause(1)
            if let value = overlayFPS() { fps.append(value) }
        }
        showControls()
        app.buttons["record"].tap()
        let recordedFor = Date().timeIntervalSince(started)
        XCTAssertTrue(wait(60) { self.recordingProbe.hasPrefix("video ") || self.recordingProbe.hasPrefix("failed") },
                      "the file is read back: \(recordingProbe)")
        let thermalAfter = ProcessInfo.processInfo.thermalState
        print("B13 \(task) \(profile): \(recordingProbe) facts \(recordingFacts())")
        let parts = recordingProbe.split(separator: " ").map(String.init)
        guard parts.count >= 6, parts[0] == "video" else { return XCTFail("no readable recording: \(recordingProbe)") }
        let size = parts[2].split(separator: "x").compactMap { Int($0) }
        let frames = Int(parts[3].replacingOccurrences(of: "frames=", with: "")) ?? 0
        let duration = Double(parts[4].replacingOccurrences(of: "duration=", with: "")) ?? 0
        let facts = recordingFacts()
        let shot = XCUIScreen.main.screenshot().image.cgImage
        let written = facts["frames"] ?? 0, dropped = facts["dropped"] ?? 0
        report(task, "circular spectrum \(profile)", [
            "width": Double(size.first ?? 0), "height": Double(size.last ?? 0),
            "screenWidth": Double(shot?.width ?? 0), "screenHeight": Double(shot?.height ?? 0),
            "frames": Double(frames), "duration": duration, "recordedFor": recordedFor,
            "fps": Double(facts["fps"] ?? 0), "written": Double(written), "dropped": Double(dropped),
            "droppedShare": written + dropped > 0 ? Double(dropped) / Double(written + dropped) : 0,
            "bytes": Double(facts["bytes"] ?? -1),
            "renderFPSMedian": Self.median(fps), "renderFPSMin": fps.min() ?? 0,
            "thermalBefore": Double(thermalBefore.rawValue), "thermalAfter": Double(thermalAfter.rawValue)])
        XCTAssertEqual(size.count, 2, "the probe names the size: \(recordingProbe)")
        XCTAssertEqual(duration, recordedFor, accuracy: 1.0, "the file is as long as the recording (\(recordedFor) s)")
        XCTAssertGreaterThanOrEqual(duration, 59, "about 60 s recorded")
        XCTAssertEqual(frames, written, "the file holds the written frames")
        XCTAssertGreaterThan(facts["bytes"] ?? -1, 0, "the file has a size: \(facts)")
    }
}
