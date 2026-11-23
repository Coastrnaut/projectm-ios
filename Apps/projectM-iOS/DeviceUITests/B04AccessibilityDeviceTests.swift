// B04AccessibilityDeviceTests.swift — QA-011 owner session B04 ("Accessibility"), the parts a machine can check, on D1
// (and D2 where the task names it). VoiceOver's speech and gestures cannot be heard or made from XCUITest, so the tests
// check what VoiceOver reads (labels, values, traits), what the app announces (`announcementsProbe`: the announcer's
// spoken list, so "once" is countable), the accessibility actions VoiceOver calls (`-uitestAccessibilityActions` probe
// buttons), `performAccessibilityAudit()`, and target geometry with coordinate taps instead of a thumb. A person still
// has to listen and use the gestures (listed per test). Probes: `-uitestVisualProbes` (UITestVisualProbes).
import UIKit
import XCTest

@MainActor
final class B04AccessibilityDeviceTests: B07DeviceCase {
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000000\(n)" }

    /// The announcer's spoken texts ("<kind>|<text>"), read from the visualizer (close sheets first).
    private func spoken() -> [String] {
        Array(probe("announcementsProbe").components(separatedBy: "‖").dropFirst())
    }

    private func occurrences(_ text: String) -> Int { spoken().filter { $0.contains(text) }.count }

    // MARK: ACC-002

    /// ACC-002-T20 (automated part): with Reduce flashing on, the flagged fixture's row reads "may flash", choosing it
    /// shows the "May flash" alert first; 50 Random picks over the unlocked library never land on a flagged preset
    /// (`presetFlashProbe`); at the largest text size (AX5) the alert's buttons can be hit. VoiceOver speech stays a
    /// person's check.
    func testACC002MayFlashLabelsRandom50AndAlertAtAX5() {
        let task = "ACC-002-T20"
        launchPlain(["-uitestImportPreset", "fixture:strobe", "-uitestKeepControls"],
                    settings: ["settings.reduceFlashing": true], unlocked: true)
        tapFresh("presets")
        XCTAssertTrue(appears(app.buttons["node:included"], 10), "library home")
        XCTAssertTrue(openMyPresets(), "My Presets opened")
        let row = app.buttons["preset:Strobe"]
        XCTAssertTrue(wait(30) {
            if self.app.alerts["Import Preset"].exists { self.app.alerts["Import Preset"].buttons["OK"].firstMatch.tap() }
            return row.exists
        }, "the fixture is listed")
        XCTAssertTrue(row.label.contains("may flash"), "\(task): the row reads may flash: \(row.label)")
        row.tap()
        let warning = app.alerts["May flash"]
        XCTAssertTrue(appears(warning, 5), "\(task): the alert comes before the preset loads")
        XCTAssertTrue(warning.label.contains("May flash") || warning.staticTexts.element(boundBy: 0).label.contains("flash"),
                      "\(task): the alert says may flash: \(warning.label)")
        warning.buttons["Cancel"].firstMatch.tap()
        app.navigationBars.buttons["Done"].firstMatch.tap()
        _ = wait(5) { !row.exists }

        // 50 Random picks.
        var names: Set<String> = [], flagged: [String] = []
        for _ in 0..<50 {
            let before = probe("presetFlashProbe")
            tapFresh("random")
            _ = wait(5) { self.probe("presetFlashProbe") != before }
            let now = probe("presetFlashProbe")
            names.insert(now)
            if now.contains("mayFlash=yes") { flagged.append(now) }
        }
        report(task, "random 50", ["distinct": Double(names.count), "flagged": Double(flagged.count)])
        XCTAssertGreaterThan(names.count, 25, "\(task): Random moved through the library")
        XCTAssertTrue(flagged.isEmpty, "\(task): Random never picks a flagged preset: \(flagged)")
        app.terminate()

        // The alert at AX5.
        launchPlain(["-uitestImportPreset", "fixture:strobe", "-UIPreferredContentSizeCategoryName", Self.ax5],
                    settings: ["settings.reduceFlashing": true])
        tapFresh("presets")
        XCTAssertTrue(appears(app.buttons["node:included"], 10))
        XCTAssertTrue(openMyPresets(), "My Presets opened at AX5")
        XCTAssertTrue(wait(30) {
            if self.app.alerts["Import Preset"].exists { self.app.alerts["Import Preset"].buttons["OK"].firstMatch.tap() }
            return self.app.buttons["preset:Strobe"].exists
        })
        let big = app.buttons["preset:Strobe"]
        XCTAssertTrue(reveal(big), "the row at AX5")
        big.tap()
        XCTAssertTrue(appears(warning, 5), "\(task): the alert at AX5")
        for title in ["Load Anyway", "Cancel"] {
            let b = warning.buttons[title].firstMatch
            XCTAssertTrue(b.exists && b.isHittable, "\(task): \(title) can be hit at AX5")
        }
        warning.buttons["Cancel"].firstMatch.tap()
    }

    // MARK: ACC-004

    /// ACC-004-T12 (automated part): stepping cues announces each cue once (no repeats in the spoken list) and the
    /// cue controls carry labels. The full audit of every primary screen is PrimaryScreensAccessibilityUITests on D1;
    /// VoiceOver's rotor and swipe actions stay a person's check.
    func testACC004CueAnnouncementsOnce() {
        let task = "ACC-004-T12"
        launchPlain(["-uitestShowSeed", "-uitestKeepControls"])
        showControls()
        let next = app.buttons["showNextCue"]
        XCTAssertTrue(appears(next), "Next cue")
        XCTAssertFalse(next.label.isEmpty, "\(task): Next cue is named")
        for _ in 0..<3 { next.tap(); pause(1.5) }
        hideControls()
        let list = spoken()
        var repeats = 0
        for (a, b) in zip(list, list.dropFirst()) where a == b { repeats += 1 }
        // The cue lane only: the source's own announcements ("source|In-App Playback · …") were counted as cue steps.
        let cues = list.filter { $0.hasPrefix("cue|") }
        print("ACC004-SPOKEN \(list)")
        report(task, "announcements", ["spoken": Double(list.count), "cueSteps": Double(cues.count),
                                       "immediateRepeats": Double(repeats)])
        XCTAssertGreaterThanOrEqual(cues.count, 3, "\(task): each cue step is announced: \(list)")
        XCTAssertEqual(repeats, 0, "\(task): no announcement repeats: \(list)")
    }

    // MARK: ACC-005

    /// ACC-005-T16 (automated part): the glow sliders' accessibility increment and decrement (VoiceOver's swipe up and
    /// down, through the probe buttons) move exactly one step and the value carries its unit; stepping past the end
    /// announces "Maximum, …" once. VoiceOver's own gestures and speech stay a person's check.
    func testACC005SliderStepsUnitsAndEndAnnouncedOnce() {
        let task = "ACC-005-T16"
        // Settings opens at the visual's options (Bars, Glow and its sliders): with two dozen visual rows above them,
        // twelve drags never brought the slider on screen on D1-D3 (2026-11-18). Opening at a section beats flinging.
        launchPlain(["-uitestAccessibilityActions", "-uitestSettingsSection", "visualOptions", "-uitestSettingsSectionOnce"],
                    settings: ["settings.visual": "circularSpectrum", "settings.circularSpectrum.glow": true])
        openSettings()
        let intensity = element("glowIntensitySlider")
        XCTAssertTrue(appears(intensity, 5) || reveal(intensity) || reveal(intensity, up: false), "the glow intensity slider")
        XCTAssertEqual(value(intensity), "50 percent")
        XCTAssertTrue(accessibilityStep("glowIntensitySlider", up: true))
        XCTAssertTrue(wait(3) { self.value(intensity) == "55 percent" }, "\(task): one 5 % step: \(value(intensity))")
        XCTAssertTrue(accessibilityStep("glowIntensitySlider", up: false))
        XCTAssertTrue(wait(3) { self.value(intensity) == "50 percent" }, "\(task): and back: \(value(intensity))")
        let radius = element("glowRadiusSlider")
        XCTAssertTrue(reveal(radius), "the glow radius slider")
        XCTAssertTrue(value(radius).hasSuffix("percent"), "\(task): the radius reads its unit: \(value(radius))")
        // To the end and one more: the maximum is announced once.
        for _ in 0..<12 { accessibilityStep("glowIntensitySlider", up: true) }
        XCTAssertEqual(value(intensity), "100 percent", "\(task): the end of the range")
        accessibilityStep("glowIntensitySlider", up: true)
        pause(1.5)   // the announcer's window
        closeSettings()
        let maxima = occurrences("Maximum, 100 percent")
        print("ACC005-SPOKEN \(spoken())")
        report(task, "end", ["maximumAnnouncements": Double(maxima)])
        XCTAssertEqual(maxima, 1, "\(task): the end is announced once: \(spoken())")
    }

    // MARK: ACC-007

    private func hapticSettings(_ choice: String, extra: [String: Any] = [:]) -> [String: Any] {
        var s: [String: Any] = ["settings.haptics.beatPulses": true, "settings.haptics.beatEvent": choice]
        s.merge(extra) { $1 }
        return s
    }

    private func pulseTimes() -> [Double] { Self.numbers(probe("hapticProbe"), "times") }

    /// Waits until the music fixture plays its chorus: drums from 10 s (the first 10 s are a quiet intro without them,
    /// scripts/make_music_fixture.py), plus 10 s for ANL-005's 6 s window to fill so beats reach confidence 0.5 (the
    /// Beats rule). The chorus with drums lasts until 40 s, so a 12 s count from here sees drums throughout.
    private func waitForChorus(_ task: String, _ label: String) {
        func position() -> Double { Self.number(probe("sectionChangeProbe"), "position") ?? 0 }
        XCTAssertTrue(wait(25) { position() >= 20 }, "\(task) \(label): the fixture reached its chorus: \(probe("sectionChangeProbe"))")
    }

    /// ACC-007-T13 (automated part): Haptics on with the 120 BPM music fixture: Beats pulse once per beat (median interval
    /// 0.5 s ± 30 ms, `hapticProbe`); Downbeats give fewer pulses (about one per bar) and Kicks pulse with the drums;
    /// Strict and the switch off give none. Feeling the taps stays a person's check; Low Power Mode is
    /// `testACC007LowPowerGivesNone` (Batch 1's Settings helper).
    /// 2026-11-22 (D1 full run 1, the first run on haptic hardware): the 12 s count started about 8 s after launch, in
    /// the fixture's drumless intro, so Beats counted 2 pulses (an earlier D1 run: Beats 2, Downbeats 1, Kicks 13, the
    /// kicks being the last seconds' drums). Each count now starts in the chorus (`waitForChorus`).
    /// 2026-11-23 (D1 rerun): Beats 9 in the chorus (Kicks 23). An app defect: the fixture's off-beat hi-hats hold
    /// ANL-005's confidence at 0.46-0.52, so a 0.5 cut skipped most beats; the gate now holds Beats down to 0.4 once
    /// engaged (ACC-007 Clarifications 2026-11-23, `HapticPulseGateTests`).
    func testACC007PulsesFollowTheChoice() throws {
        let task = "ACC-007-T13"
        // iPads have no haptic hardware (ACC-007 Clarifications: the switch is disabled with "This device has no
        // haptics."); D2 and D3 counted 0 pulses for every choice (2026-11-18). ACC-007-T13 is D1's.
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("haptics are iPhone only (ACC-007)") }
        var counts: [String: Double] = [:]
        for choice in ["beats", "downbeats", "kicks"] {
            launchProbed(visual: "circularSpectrum", settings: hapticSettings(choice))
            waitForChorus(task, choice)
            let start = Self.number(probe("hapticProbe"), "pulses") ?? 0
            pause(12)
            let end = Self.number(probe("hapticProbe"), "pulses") ?? 0
            counts[choice] = end - start
            if choice == "beats" {
                // The intervals of the pulses in the count window only (times are seconds after the first pulse).
                let all = pulseTimes()
                let times = Array(all.suffix(max(Int(end - start), 0)))
                let intervals = zip(times, times.dropFirst()).map { $1 - $0 }.filter { $0 < 1.2 }
                let median = Self.median(intervals)
                let near = intervals.filter { abs($0 - 0.5) <= 0.03 }.count
                report(task, "beats", ["pulses": end - start, "medianInterval": median,
                                       "withinThirtyMs": Double(near) / Double(max(intervals.count, 1))])
                XCTAssertEqual(median, 0.5, accuracy: 0.03, "\(task): one pulse per beat: \(intervals)")
            }
            app.terminate()
        }
        report(task, "choices", ["beats": counts["beats"] ?? 0, "downbeats": counts["downbeats"] ?? 0, "kicks": counts["kicks"] ?? 0])
        XCTAssertGreaterThan(counts["beats"] ?? 0, 15, "\(task): Beats pulse with the music")
        XCTAssertLessThan(counts["downbeats"] ?? 0, (counts["beats"] ?? 0) * 0.6, "\(task): Downbeats pulse less often")
        // The fixture's kick falls on every beat, so in the chorus Kicks and Beats both give about 24 pulses in 12 s and
        // "a different count" held only while the count window covered the drumless intro. Kicks must pulse with the
        // drums (half of the 24 kicks or more; D1's earlier run counted 13 in about 8 s of drums).
        XCTAssertGreaterThan(counts["kicks"] ?? 0, 12, "\(task): Kicks pulse with the drums")

        for (label, settings) in [("Strict", hapticSettings("beats", extra: ["settings.sensorySafety.profile": "strict"])),
                                  ("switch off", ["settings.haptics.beatPulses": false] as [String: Any])] {
            launchProbed(visual: "circularSpectrum", settings: settings)
            waitForChorus(task, label)   // a zero counts only with drums playing (the intro has none)
            pause(8)
            let pulses = Self.number(probe("hapticProbe"), "pulses") ?? -1
            report(task, label, ["pulses": pulses])
            XCTAssertEqual(pulses, 0, "\(task): \(label) gives no pulses")
            app.terminate()
        }
    }

    /// ACC-007-T13: Low Power Mode on gives no pulses (Settings › Battery through SystemUI, restored afterwards).
    func testACC007LowPowerGivesNone() throws {
        let task = "ACC-007-T13"
        // Without haptic hardware nothing ever pulses, so an iPad proves nothing about Low Power Mode.
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("haptics are iPhone only (ACC-007)") }
        let system = SystemUI(app: app)
        system.toggleAccessibility(.lowPower, on: true)
        defer { system.restore() }
        launchProbed(visual: "circularSpectrum", settings: hapticSettings("beats"))
        pause(8)
        let pulses = Self.number(probe("hapticProbe"), "pulses") ?? -1
        report(task, "low power", ["pulses": pulses])
        XCTAssertEqual(pulses, 0, "\(task): Low Power Mode gives no pulses")
    }

    // MARK: ACC-009, ACC-010 (one-handed and left-handed geometry)

    private func rect(_ probeID: String) -> CGRect? {
        let parts = value(app.staticTexts[probeID]).split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    private static let critical = ["showPreviousCue", "showNextCue", "tapTempo", "blackout", "previous", "next", "random",
                                   "pauseResume", "presets", "settings", "stop"]

    /// ACC-009-T14 (automated part): Right and Left hand, portrait and landscape, without and with the pad: every
    /// critical action present lies inside the holding thumb's zone (`oneHandedZone`), is at least 44 pt (60 pt on the
    /// pad), and answers a coordinate tap (Tap tempo counts a tap; the pad's Next cue steps the show). A real thumb
    /// stays a person's check. D1 (one-handed controls are not offered on an iPad).
    func testACC009ThumbZoneEveryConfiguration() throws {
        let task = "ACC-009-T14"
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("one-handed controls are iPhone only (ACC-009)") }
        for hand in ["right", "left"] {
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                for pad in [false, true] {
                    let label = "\(hand) \(orientation == .portrait ? "portrait" : "landscape")\(pad ? " pad" : "")"
                    launchPlain(["-uitestShowSeed", "-uitestTapInterval", "500"] + (pad ? ["-uitestPerformanceLayout"] : ["-uitestKeepControls"]),
                                settings: ["settings.controls.oneHanded": hand], orientation: orientation)
                    if !pad { showControls() } else { hideControls() }
                    guard let zone = wait(3, { self.rect("oneHandedZone") != nil }) ? rect("oneHandedZone") : nil else {
                        report(task, label, ["zone": 0])
                        XCTAssertNotEqual(orientation, .portrait, "\(task) \(label): the thumb zone probe")
                        app.terminate()
                        continue
                    }
                    let ids = pad ? ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"]
                        : Self.critical.filter { app.buttons[$0].exists }
                    var outside: [String] = []
                    for id in ids {
                        let f = app.buttons[id].frame
                        if !zone.insetBy(dx: -0.5, dy: -0.5).contains(f) { outside.append(id) }
                        XCTAssertGreaterThanOrEqual(min(f.width, f.height), (pad ? 60 : 44) - 0.5, "\(task) \(label): \(id) size \(f)")
                    }
                    // Coordinate taps (where a thumb lands), not element taps.
                    let tapID = pad ? "perfTapTempo" : "tapTempo"
                    let tap = app.buttons[tapID]
                    tapPoint(CGPoint(x: tap.frame.midX, y: tap.frame.midY))
                    let counted = wait(2) { self.value(tap) == "Tap 1 of 4" }
                    var stepped = true
                    if pad {
                        let before = probe("showAppliedScene")
                        let next = app.buttons["perfNextCue"]
                        tapPoint(CGPoint(x: next.frame.midX, y: next.frame.midY))
                        stepped = wait(3) { self.probe("showAppliedScene") != before }
                    }
                    report(task, label, ["targets": Double(ids.count), "outsideZone": Double(outside.count),
                                         "tapCounted": counted ? 1 : 0, "cueStepped": stepped ? 1 : 0])
                    XCTAssertTrue(outside.isEmpty, "\(task) \(label): inside the thumb zone \(zone): \(outside)")
                    XCTAssertTrue(counted, "\(task) \(label): Tap tempo answers a coordinate tap: \(value(tap))")
                    XCTAssertTrue(stepped, "\(task) \(label): Next cue answers a coordinate tap")
                    app.terminate()
                }
            }
        }
    }

    /// ACC-010-T13 (automated part, D1 and D2): Left-handed controls put the emergency button in the bottom-leading
    /// corner and, in landscape, the pad's side columns swapped (ACC-010 US1 scenario 1: Tap tempo and Black out in the
    /// leading column, the cue targets in the trailing one), and each pad target answers a coordinate tap. Using it
    /// with a left hand stays a person's check; LeftHandedUITests also runs on D1 and D2.
    /// 2026-11-19 (pass 3): the landscape check expected Next cue on the leading side, which is the right-handed
    /// placement; D2 (1332 of 1376 pt) and D3 (1136 of 1180 pt) put it in the trailing column, as the spec says.
    func testACC010LeftHandedGeometryAndTaps() {
        let task = "ACC-010-T13"
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let label = orientation == .portrait ? "portrait" : "landscape"
            launchPlain(["-uitestShowSeed", "-uitestTapInterval", "500"], settings: ["settings.controls.leftHanded": true],
                        orientation: orientation)
            let window = app.windows.firstMatch.frame
            // The button sits at the bottom of the status stack, right above the controls card: with the card and
            // the show rows up it stood above the middle of D3's 1180 pt window (midY 556.5, 2026-11-18). Measure it
            // with the controls hidden, where the corner is the screen's.
            hideControls()
            XCTAssertFalse(controls.exists, "\(task) \(label): the controls are hidden for the corner measurement")
            let emergency = app.buttons["emergencyBlackout"]
            XCTAssertTrue(appears(emergency, 5), "\(task) \(label): the emergency button")
            // Read once: the pad launch below has no emergency button (the pad's Blackout replaces it), and a frame
            // read after it failed the test with "no matches" (D2, D3).
            let corner = emergency.exists ? emergency.frame : .null
            XCTAssertLessThan(corner.midX, window.midX, "\(task) \(label): bottom-leading for the left hand")
            XCTAssertGreaterThan(corner.midY, window.midY, "\(task) \(label): at the bottom")
            app.terminate()
            launchPlain(["-uitestShowSeed", "-uitestTapInterval", "500", "-uitestPerformanceLayout"],
                        settings: ["settings.controls.leftHanded": true], orientation: orientation)
            hideControls()
            let tap = app.buttons["perfTapTempo"], next = app.buttons["perfNextCue"]
            XCTAssertTrue(appears(tap, 5), "\(task) \(label): the pad")
            if orientation != .portrait {
                // Side columns swapped: the cue column trailing, Tap tempo (with Black out) leading.
                XCTAssertGreaterThan(next.frame.midX, window.midX, "\(task) \(label): Next cue in the trailing column")
                XCTAssertLessThan(tap.frame.midX, window.midX, "\(task) \(label): Tap tempo in the leading column")
            }
            tapPoint(CGPoint(x: tap.frame.midX, y: tap.frame.midY))
            XCTAssertTrue(wait(2) { self.value(tap) == "Tap 1 of 4" }, "\(task) \(label): Tap tempo answers")
            let before = probe("showAppliedScene")
            tapPoint(CGPoint(x: next.frame.midX, y: next.frame.midY))
            XCTAssertTrue(wait(3) { self.probe("showAppliedScene") != before }, "\(task) \(label): Next cue answers")
            report(task, label, ["emergencyMidX": Double(corner.midX), "emergencyMidY": Double(corner.midY),
                                 "nextMidX": Double(next.frame.midX), "windowWidth": Double(window.width)])
            app.terminate()
        }
    }

    // MARK: ACC-012

    /// ACC-012-T22: the Strict sensory safety profile on the device: Settings shows Strict's clamp (the SensorySafety
    /// probe), the strobing fixture is clamped by projectM's envelope (`flashGuardProbe`), and the frame rate with
    /// Strict stays within noise of Standard (both with the gain probe on, which costs a few fps).
    /// 2026-11-19: the Strobe fixture never flashed (projectM 4 ignores per-frame `invert`/`gamma`), so Strict's clamp
    /// (pass 3: recentClamped 11 on D2, 16 on D3) was its 0.10/s rise limit on ordinary motion, and Standard's minGain
    /// (0.29, 0.20) was the launch preset's, counted since launch. The fixture now inverts the whole frame at 1.5 Hz in
    /// its composite shader (UITestVisualProbes.strobePreset; FlashLimiterTests proves Standard leaves it at gain 1 and
    /// Strict clamps it), and both profiles are compared over the probe's last 3 s (`recentMin`, `recentClamped`), long
    /// after the blend from the launch preset: Standard must not clamp the fixture, Strict must.
    func testACC012SensorySafetyProfile() {
        let task = "ACC-012-T22"
        var fps: [String: Double] = [:]
        var recentMin: [String: Double] = [:]
        for profile in ["standard", "strict"] {
            // Reduce flashing pinned off: Standard with it off is today's picture, bit-identical (ACC-012 US2), and its
            // always-on cap allows 3 flashes per second, so the fixture's 1.5 Hz flash passes unclamped; with Reduce
            // Motion on, Reduce flashing would follow it and Standard would clamp as Reduced. Strict keeps flashing
            // reduced whatever the toggle says (ACC-012-R7).
            launchProbed(visual: "projectM", settings: ["settings.sensorySafety.profile": profile,
                                                        "settings.reduceFlashing": false],
                         extra: ["-uitestImportPreset", "fixture:strobe", "-uitestSettingsSection", "safety"])
            if profile == "strict" {
                openSettings()
                let sensory = app.staticTexts["sensorySafetyProbe"]
                XCTAssertTrue(appears(sensory, 3) || reveal(sensory), "the Sensory safety probe")
                XCTAssertEqual(sensory.label, "glow 0.25 flashes 1/s rise 0.10 intensity 0.25", "\(task): Strict's clamp")
                closeSettings()
            }
            XCTAssertTrue(playStrobeFixture(), "\(task) \(profile): the strobing fixture plays")
            _ = wait(8) { !self.controls.exists }
            var line = ""
            // Strict: wait for a clamp. Standard: the reference reading, taken after the 8 s frame-rate sample.
            let clamped = profile == "strict"
                ? wait(12) { line = self.probe("flashGuardProbe"); return (Self.number(line, "recentClamped") ?? 0) > 0 }
                : false
            fps[profile] = Self.median(sampleFPS(seconds: 8))
            line = profile == "strict" ? line : probe("flashGuardProbe")
            recentMin[profile] = Self.number(line, "recentMin") ?? -1
            report(task, profile, ["fps": fps[profile] ?? 0, "recentClamped": Self.number(line, "recentClamped") ?? -1,
                                   "recentMin": recentMin[profile] ?? -1, "minGain": Self.number(line, "minGain") ?? -1])
            XCTAssertGreaterThan(Self.number(line, "recentSampled") ?? 0, 5, "\(task) \(profile): the gain probe samples projectM: \(line)")
            if profile == "strict" { XCTAssertTrue(clamped, "\(task) strict: the envelope clamps the strobe: \(line)") }
            if profile == "standard" {
                XCTAssertEqual(Self.number(line, "recentClamped"), 0,
                               "\(task) standard: a 1.5 Hz flash is within the always-on cap (3 flashes per second): \(line)")
            }
            app.terminate()
        }
        XCTAssertLessThan(recentMin["strict"] ?? 1, (recentMin["standard"] ?? 1) - 0.1, "\(task): Strict dims the strobe, Standard does not")
        XCTAssertGreaterThanOrEqual(fps["strict"] ?? 0, (fps["standard"] ?? 0) - Self.effectToleranceFPS,
                                    "\(task): Strict costs no frame rate")
    }

    // MARK: SHD-003

    /// SHD-003-T20 (automated part): the seeded material layer's Material settings: every generated control has a
    /// label and a value (with its unit where it has one), and the screen passes the element-description audit.
    /// Listening with VoiceOver stays a person's check.
    func testSHD003MaterialControlsReadable() throws {
        let task = "SHD-003-T20"
        launchPlain(["-uitestSeedPhoto", "solid", "-uitestLayerInspectorSeed"])
        openSettings()
        let link = app.buttons["layersLink"]
        XCTAssertTrue(reveal(link), "Settings offers Layers")
        link.tap()
        let row = app.buttons["layerRow.3"]
        XCTAssertTrue(appears(row), "the material row")
        row.tap()
        XCTAssertTrue(appears(app.navigationBars["Material (plasma)"]), "the material layer")
        var checked = 0
        for name in ["scale", "speed", "brightness", "contrast", "audioReactivity"] {
            let c = app.descendants(matching: .any).matching(identifier: "materialControl.material.plasma." + name).firstMatch
            guard reveal(c) else { continue }
            checked += 1
            XCTAssertFalse(c.label.isEmpty, "\(task): \(name) has a label")
            XCTAssertFalse(value(c).isEmpty, "\(task): \(name) has a value")
            if ["brightness", "audioReactivity"].contains(name) {
                XCTAssertTrue(value(c).hasSuffix("percent"), "\(task): \(name) reads its unit: \(value(c))")
            }
        }
        report(task, "controls", ["checked": Double(checked)])
        XCTAssertGreaterThanOrEqual(checked, 3, "\(task): the generated controls are reachable")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            // The app's near-transparent DEBUG probes (`-uitestDiagnostics`) have no description by design. On an iPad
            // the visualizer's probes stay on screen beside the Settings panel: `splitOutputFrame` failed D2 and D3
            // (2026-11-18), so the shared list (SystemUI.swift) decides.
            let id = (try? issue.element?.snapshot().identifier) ?? ""
            if !DebugProbes.contains(id) { print("SHD003-AUDIT id=\(id): \(issue.compactDescription)") }
            return DebugProbes.contains(id)
        }
    }

    // MARK: UIX-005

    /// UIX-005-T13 (automated part, D1 and D2): portrait and landscape, every pad target is at least 60 pt (72 pt on the
    /// iPad, both size classes regular), inside the safe area, in the bottom half (portrait) or a side column
    /// (landscape), and answers a coordinate tap: Next cue steps, Tap tempo counts, Blackout blacks out and restores,
    /// Previous cue returns. "Without looking" stays a performer's check.
    func testUIX005PadTargetsGeometryAndTaps() {
        let task = "UIX-005-T13"
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let label = orientation == .portrait ? "portrait" : "landscape"
            launchPlain(["-uitestShowSeed", "-uitestPerformanceLayout", "-uitestTapInterval", "500"], orientation: orientation)
            hideControls()
            let window = app.windows.firstMatch.frame
            let safe = (wait(3) { self.rect("performanceSafeArea") != nil } ? rect("performanceSafeArea") : nil) ?? window
            var smallest: CGFloat = 999
            for id in ["perfPreviousCue", "perfNextCue", "perfTapTempo", "perfBlackout"] {
                let f = app.buttons[id].frame
                smallest = min(smallest, f.width, f.height)
                XCTAssertGreaterThanOrEqual(min(f.width, f.height), performanceTargetSide - 0.5, "\(task) \(label): \(id) \(f)")
                XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(task) \(label): \(id) inside the safe area")
                if orientation == .portrait {
                    XCTAssertGreaterThan(f.midY, window.midY, "\(task) \(label): \(id) within the thumbs' reach (bottom half)")
                } else {
                    XCTAssertTrue(f.maxX < window.width * 0.35 || f.minX > window.width * 0.65, "\(task) \(label): \(id) in a side column")
                }
            }
            func tap(_ id: String) { let f = app.buttons[id].frame; tapPoint(CGPoint(x: f.midX, y: f.midY)) }
            let cue1 = probe("showAppliedScene")
            tap("perfNextCue")
            XCTAssertTrue(wait(3) { self.probe("showAppliedScene").hasPrefix(Self.sceneID(2)) }, "\(task) \(label): Next cue")
            tap("perfTapTempo")
            XCTAssertTrue(wait(2) { self.value(self.app.buttons["perfTapTempo"]) == "Tap 1 of 4" }, "\(task) \(label): Tap tempo")
            tap("perfBlackout")
            XCTAssertTrue(wait(2) { self.probe("outputBlackout") == "black" }, "\(task) \(label): Blackout")
            tap("perfBlackout")
            XCTAssertTrue(wait(3) { self.probe("outputBlackout") != "black" }, "\(task) \(label): Restore")
            tap("perfPreviousCue")
            XCTAssertTrue(wait(3) { self.probe("showAppliedScene") == cue1 }, "\(task) \(label): Previous cue")
            report(task, label, ["smallestTarget": Double(smallest), "required": Double(performanceTargetSide)])
            app.terminate()
        }
    }

    // MARK: UIX-010

    /// UIX-010-T10 (automated part): in selection mode each parameter row reads as a toggle with its state ("Not
    /// selected" / "Selected"), the reset button reads its count ("Reset 2 parameters to defaults"), and "Reset 2
    /// parameters" is announced once after the reset. VoiceOver speech stays a person's check.
    func testUIX010BatchResetReadsAndAnnouncesOnce() {
        let task = "UIX-010-T10"
        launchPlain(["-uitestSettingsSection", "parameterSearch", "-uitestSettingsSectionOnce"],
                    settings: ["settings.visual": "circularSpectrum", "settings.circularSpectrum.bars": 16,
                               "settings.linearSpectrum.orientation": "horizontal"])
        openSettings()
        let link = app.buttons["parameterSearchLink"].firstMatch
        XCTAssertTrue(appears(link) && (link.isHittable || reveal(link, up: false)), "Search Parameters")
        link.tap()
        app.buttons["parameterReset.select"].firstMatch.tap()
        let bars = element("parameterResetToggle.visual.circularSpectrum.barCount")
        let orientation = element("parameterResetToggle.visual.linearSpectrum.orientation")
        XCTAssertTrue(appears(bars), "rows in selection mode")
        XCTAssertTrue(value(bars).hasPrefix("Not selected"), "\(task): the row reads its state: \(value(bars))")
        XCTAssertTrue([.toggle, .switch].contains(bars.elementType), "\(task): the row is a toggle (type \(bars.elementType.rawValue))")
        bars.tap()
        if !orientation.isHittable { reveal(orientation, up: false) }
        orientation.tap()
        XCTAssertTrue(value(bars).hasPrefix("Selected"), "\(task): selected: \(value(bars))")
        // Read now: after the reset and Done the row is gone, and reading its type then failed the test with "no
        // matches" after every assertion had passed (D1-D3, 2026-11-18).
        let rowType = Double(bars.elementType.rawValue)
        let reset = app.buttons["parameterReset.reset"].firstMatch
        XCTAssertEqual(reset.label, "Reset 2 parameters to defaults", "\(task): the button reads its count")
        reset.tap()
        pause(1.5)
        closeSettings()
        let count = occurrences("Reset 2 parameters")
        print("UIX010-SPOKEN \(spoken())")
        report(task, "announcement", ["resetAnnouncements": Double(count), "rowType": rowType])
        XCTAssertEqual(count, 1, "\(task): \"Reset 2 parameters\" announced once: \(spoken())")
    }

    // MARK: PERF-014

    /// PERF-014-T22 (D1 and D3): projectM's swap fails from launch (`-uitestRenderFaults present`): the controls respond,
    /// the placeholder covers the visual after the bounded retries, the "Render fault" events are logged
    /// (`renderFaultEventsProbe`: `DiagnosticsLog.renderFault`, the os_log and Points of Interest line Console shows),
    /// and pause/resume with the fault cleared brings projectM back. Reading Console itself needs `log collect` with
    /// sudo on the Mac (not automated).
    func testPERF014PlaceholderEventsAndResume() {
        let task = "PERF-014-T22"
        launchPlain(["-uitestRenderFaults", "present"])
        XCTAssertTrue(wait(10) { self.probe("renderHealth").contains("presentationFailed") }, probe("renderHealth"))
        XCTAssertTrue(wait(15) { self.probe("renderPlaceholderShown") == "yes" }, "\(task): the placeholder: \(probe("renderHealth"))")
        let logged = Self.number(probe("renderFaultEventsProbe"), "events") ?? 0
        showControls()
        XCTAssertTrue(app.buttons["settings"].isHittable, "\(task): the controls respond")
        app.buttons["faults:clear"].tap()
        showControls()
        app.buttons["pauseResume"].tap()
        app.buttons["pauseResume"].tap()   // resume: a fresh budget (PERF-014-R6)
        XCTAssertTrue(wait(5) { self.probe("renderPlaceholderShown") == "no" }, "\(task): back after resume: \(probe("renderHealth"))")
        let afterRecovery = Self.number(probe("renderFaultEventsProbe"), "events") ?? 0
        report(task, "events", ["faultEvents": logged, "afterRecovery": afterRecovery])
        XCTAssertGreaterThan(logged, 0, "\(task): render fault events were logged")
        XCTAssertGreaterThan(afterRecovery, logged, "\(task): the recovery is logged too")
    }
}
