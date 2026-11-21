// B10MIDIDeviceTests.swift — QA-011 Batch 8: the MIDI device tasks, driven by the app's own DEBUG virtual MIDI source
// (QA-011 device run 2026-11-21; specs/107-midi-001-midi-endpoint-discovery Clarifications).
//
// The tests were first written for the Mac as the controller over a CoreMIDI network session, which the app excludes
// by policy (MIDI-001-R2, R14; ADR-0038), DEBUG included, so they always skipped; USB-cable tests are not required
// (owner ruling 2026-11-18). Now each test launches with `-uitestVirtualMIDISource`: the app creates a CoreMIDI virtual
// source and destination named "QA011 Test Source" (Debug/UITestVirtualMIDISource.swift). The test taps a scenario's
// probe button (`midiProbe.<scenario>`, a small window above every sheet) and the source sends the same bytes the Mac
// driver sent (scripts/mac_driver/midi.py `SCENARIOS`) through the system's MIDI service to the app's real discovery,
// input, mappings, clock and feedback. Virtual endpoints need `audio` in UIBackgroundModes on iOS: only the Debug
// device-test host gets it (DeviceTests.yml); the probe reports "failed -10844" otherwise and the tests fail with it.
//
// MIDI-001-T18 (the virtual source listed as an input and an output; hot-plug stays with a USB controller),
// MIDI-002-T20 (monitor), MIDI-003-T17 (learn, relaunch), MIDI-004-T16 (inverted), MIDI-005-T14 (14-bit), MIDI-006-T16
// (pad and hold), MIDI-007-T15 (program change), MIDI-008-T12 (CC button, Play/Pause), MIDI-009-T15 (feedback without
// an echo loop; the probe's destination counts what the app sends back), MIDI-010-T12 (clock), MIDI-012-T15 (profile
// export on D1, import on D2: scripts/mac_driver/peer.py), MIDI-013-T13 (panic). MIDI-011-T12 (drop and restore the
// connection) is not written here: a USB controller's unplug is the real case.
import UIKit
import XCTest

@MainActor
final class B10MIDIDeviceTests: ControlSurfaceCase {
    /// The in-app virtual endpoints' name (UITestVirtualMIDISource.endpointName).
    private let sourceName = "QA011 Test Source"

    /// Listening on, `mappings` stored, Settings open at MIDI, the in-app virtual source ready and listed as an input
    /// and an output.
    private func prepare(_ task: String, mappings: [String]? = nil, settings: [String: Any] = [:], extra: [String] = []) throws {
        var values: [String: Any] = Self.glowSettings.merging(["settings.midi.enabled": true]) { a, _ in a }
        if let mappings { values["settings.midi.mappings"] = mappings }
        values.merge(settings) { (_: Any, given: Any) -> Any in given }
        launch(visual: "circularSpectrum", settings: values,
               extra: Self.glowReadoutArguments + ["-uitestSettingsSection", "midi", "-uitestResetMIDIProfiles",
                                                   "-uitestVirtualMIDISource"] + extra)
        let status = { self.text("midiProbeStatus") }
        XCTAssertTrue(wait(15) { status() == "ready" || status().hasPrefix("failed") }, "the virtual MIDI probe starts: \(status())")
        if status().hasPrefix("failed -10844") {   // the ordinary host: no `audio` background mode (2026-11-21)
            throw XCTSkip("B10 runs on the MIDI host build only: xcodebuild build-for-testing … QA011_MIDI_HOST=YES "
                          + "-derivedDataPath Build/device-acceptance-midi (docs/autotester.md, B10)")
        }
        XCTAssertEqual(status(), "ready", "the virtual source and destination exist")
        unbindGlow()
        openSettingsPanel()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'midiEndpoint.'"))
        func ours(_ direction: String) -> Bool {
            rows.allElementsBoundByIndex.contains { $0.label.contains(self.sourceName) && $0.label.contains(direction) }
        }
        let start = Date()
        let listed = wait(8) { ours("Input") && ours("Output") }
        report(task, "virtual source listed", ["listed": listed ? 1 : 0, "seconds": Date().timeIntervalSince(start)])
        XCTAssertTrue(listed, "\(sourceName) is listed as an Input and an Output: \(rows.allElementsBoundByIndex.map(\.label))")
    }

    /// Runs one scenario on the in-app virtual source (queued on its serial queue; returns at once). The probe window
    /// sits above every sheet but is never key, so XCUITest does not call its buttons hittable: the tap goes to the
    /// button's screen point, and `midiProbeQueued` going up proves it landed.
    private func send(_ scenario: String) {
        let button = app.buttons["midiProbe." + scenario].firstMatch
        XCTAssertTrue(wait(5) { button.exists }, "probe button \(scenario)")
        let before = Int(text("midiProbeQueued")) ?? 0
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(wait(3) { (Int(self.text("midiProbeQueued")) ?? 0) > before }, "the probe took \(scenario) (\(button.frame))")
        print("MIDI-SENT \(scenario)")
    }

    /// The glow the visual shows: the readout's "effective" value. MIDI mappings write live values on top of the manual
    /// glow (`NativeSpectrumHost.externalValues`), so "manual" never moves with MIDI; with the glow unbound from MOD-002
    /// (`unbindGlow()`), "effective" is the manual glow with the MIDI values applied (simulator rehearsal 2026-11-21).
    private func liveGlow() -> Double? {
        let label = app.staticTexts["glowModulation"].firstMatch.label
        guard let range = label.range(of: "effective ") else { return nil }
        return Double(label[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
    }

    private func openMappings() {
        let link = app.buttons["midiMappingsLink"].firstMatch
        XCTAssertTrue(scrollTo(link), "MIDI Mappings")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["MIDI Mappings"].exists })
    }

    /// The glow after `scenario` (read with Settings closed), or nil when it never changed. The scenario sets an
    /// absolute value, so it is sent again every 4 s while nothing changed (a source still connecting after a
    /// relaunch misses the first one).
    private func glow(after scenario: String, from: Double?) -> Double? {
        var changed = false
        for _ in 0..<3 where !changed {
            send(scenario)
            changed = wait(4) {
                guard let v = self.liveGlow() else { return false }
                return from.map { abs(v - $0) > 0.005 } ?? true
            }
        }
        pause(1)
        return changed ? liveGlow() : nil
    }

    func testMIDI001VirtualSourceListed() throws {
        try prepare("MIDI-001-T18")
        XCTAssertTrue(text("midiStatus").hasPrefix("Listening"), "status: \(text("midiStatus"))")
    }

    func testMIDI002MonitorShowsCCAndNotes() throws {
        let task = "MIDI-002-T20"
        try prepare(task)
        let link = app.buttons["midiMonitorLink"].firstMatch
        XCTAssertTrue(scrollTo(link), "MIDI Monitor")
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["MIDI Monitor"].exists })
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'midiMonitorEntry.'"))
        func labels() -> [String] { rows.allElementsBoundByIndex.map(\.label) }
        send("monitor")
        let cc = wait(15) { labels().contains { $0.hasPrefix("Control change, channel 1, controller 7") } }
        let note = wait(10) { labels().contains { $0.hasPrefix("Note on, channel 1, note 60") } }
        report(task, "monitor", ["cc": cc ? 1 : 0, "note": note ? 1 : 0, "rows": Double(labels().count)])
        XCTAssertTrue(cc && note, "CC 7 and note 60 rows: \(labels().prefix(6))")
        goBack()
        send("monitor-closed")
        pause(3)
        link.tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["MIDI Monitor"].exists })
        let empty = labels().isEmpty
        report(task, "reopen", ["empty": empty ? 1 : 0])
        XCTAssertTrue(empty, "closing stopped receiving and the monitor reopens empty: \(labels().prefix(3))")
    }

    func testMIDI003LearnGlow() throws {
        let task = "MIDI-003-T17"
        try prepare(task, mappings: [])
        openMappings()
        let row = element("midiMapping.effect.bloom.intensity")
        XCTAssertTrue(wait(5) { row.exists })
        app.buttons["midiLearn.effect.bloom.intensity"].firstMatch.tap()
        send("learn21")
        let learned = wait(15) { row.label == "Glow intensity, CC 21, channel 1" }
        report(task, "learn", ["learned": learned ? 1 : 0])
        XCTAssertTrue(learned, "row: \(row.label)")
        goBack()
        closeSettingsPanel()
        let low = glow(after: "cc21-low", from: liveGlow())
        let high = glow(after: "cc21-high", from: low)
        XCTAssertNotNil(low, "CC 21 moves the glow")
        if let low, let high { XCTAssertGreaterThan(high, low, "120 gives more glow than 10") }
        // Relaunch without the reset: the learned mapping is kept, and a new CC 21 value still moves the glow.
        // A launch with `-uitestDefaults` first removes every key the previous launch wrote (the learned mapping too),
        // so the relaunch drops `-uitestDefaults` and its JSON as well as `-uitestResetNotice`: the app then keeps what
        // is stored, "as after a real relaunch" (AppCoordinator.applyUITestDefaults; simulator rehearsal 2026-11-21).
        app.terminate()
        var arguments = app.launchArguments.filter { $0 != "-uitestResetNotice" }
        if let i = arguments.firstIndex(of: "-uitestDefaults"), i + 1 < arguments.count { arguments.removeSubrange(i...(i + 1)) }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists })
        XCTAssertTrue(wait(10) { self.text("midiProbeStatus") == "ready" }, "the virtual source after the relaunch")
        unbindGlow()
        // The glow may already sit at CC 21's low value after the relaunch, so the proof is the same pair as before:
        // low, then high moves it up.
        let start = liveGlow()
        let lowAgain = glow(after: "cc21-low", from: start) ?? start
        let after = glow(after: "cc21-high", from: lowAgain)
        report(task, "after relaunch", ["start": start ?? -1, "low": lowAgain ?? -1, "high": after ?? -1])
        XCTAssertNotNil(after, "the mapping survives a relaunch: CC 21 still moves the glow")
        if let lowAgain, let after { XCTAssertGreaterThan(after, lowAgain, "120 gives more glow than 10 after the relaunch") }
    }

    func testMIDI004InvertedFader() throws {
        let task = "MIDI-004-T16"
        try prepare(task, mappings: ["cc:0:21=effect.bloom.intensity;invert=1"])
        closeSettingsPanel()
        let atZero = glow(after: "cc21-0", from: liveGlow())
        let atTop = glow(after: "cc21-127", from: atZero)
        report(task, "inverted", ["at0": atZero ?? -1, "at127": atTop ?? -1])
        XCTAssertNotNil(atZero)
        if let atZero, let atTop { XCTAssertGreaterThan(atZero, atTop, "inverted: brightest at 0, dimmest at 127") }
    }

    func testMIDI005FourteenBit() throws {
        let task = "MIDI-005-T14"
        try prepare(task, mappings: [])
        openMappings()
        app.buttons["midiLearn.effect.bloom.intensity"].firstMatch.tap()
        send("learn14")
        let curve = app.buttons["midiCurve.effect.bloom.intensity"].firstMatch
        let detected = wait(15) { ((curve.value as? String) ?? "").contains("14-bit") }
        report(task, "learn pair", ["detected": detected ? 1 : 0])
        XCTAssertTrue(detected, "learn detects the CC 1/33 pair: \(String(describing: curve.value))")
        goBack()
        closeSettingsPanel()
        send("ramp14")   // 0 → 16383 in 2,000 steps of 8 ms (about 16 s), starting at once
        var values = Set<String>()
        let end = Date().addingTimeInterval(17)   // the whole ramp: the two-decimal readout is read about 5 times a second
        while Date() < end {
            if let v = liveGlow() { values.insert(String(format: "%.2f", v)) }
            pause(0.05)
        }
        // The readout has two decimals, so it can show at most ~100 steps of the 16,384; the > 1,000-step criterion
        // needs a finer probe (Batch 8 report). Many distinct readings still prove the fine part is used.
        report(task, "ramp", ["distinctReadings": Double(values.count)])
        XCTAssertGreaterThan(values.count, 40, "the 14-bit ramp moves the glow smoothly: \(values.count) readings")
    }

    func testMIDI006NoteTriggers() throws {
        let task = "MIDI-006-T16"
        try prepare(task, mappings: ["note:0:60=cue.next", "note:0:61=blackout;mode=hold"], extra: ["-uitestShowSeed"])
        closeSettingsPanel()
        let before = appliedCue() ?? 1
        send("pad60")
        let stepped = wait(10) { (self.appliedCue() ?? 0) == before + 1 }
        pause(2)
        XCTAssertTrue(stepped, "one press, one step (velocity-0 note-on is its release): cue \(appliedCue() ?? -1)")
        XCTAssertEqual(appliedCue(), before + 1, "the release did not step again")
        let badge = element("blackoutBadge")
        // Black is the badge's "Blacked out" phase; after note off the output fades back in (OUT-010: "Fading in", 1 s)
        // before the badge goes, so the held time ends when the phase leaves "Blacked out" (simulator rehearsal
        // 2026-11-21: the badge itself stayed ~1.7 s past the note off).
        let blackedOut = { badge.exists && (badge.value as? String) == "Blacked out" }
        send("hold61")
        let black = wait(10) { blackedOut() }
        let t0 = Date()
        let releasing = wait(10) { !blackedOut() }
        let held = Date().timeIntervalSince(t0)
        let released = releasing && wait(10) { !badge.exists }
        report(task, "hold", ["black": black ? 1 : 0, "heldSeconds": held])
        XCTAssertTrue(black && released, "Black out while held, back after release")
        XCTAssertEqual(held, 4, accuracy: 1.5, "black only between note on and note off")
    }

    func testMIDI007ProgramChange() throws {
        let task = "MIDI-007-T15"
        try prepare(task, mappings: ["pc:0:3=cue.go:\(Self.seedSceneID(3))"], extra: ["-uitestShowSeed"])
        closeSettingsPanel()
        var changes = 0, last = appliedScene
        send("pc3")   // program 3, then again 1.5 s later
        let end = Date().addingTimeInterval(15)
        while Date() < end {
            if appliedScene != last { changes += 1; last = appliedScene }
            if appliedCue() == 3 && changes > 0 { pause(4); if appliedScene != last { changes += 1 }; break }
            pause(0.1)
        }
        report(task, "program 3 twice", ["changes": Double(changes), "cue": Double(appliedCue() ?? -1)])
        XCTAssertEqual(appliedCue(), 3, "program 3 selects cue 3's scene")
        XCTAssertEqual(changes, 1, "the repeat does nothing")
    }

    func testMIDI008Transport() throws {
        let task = "MIDI-008-T12"
        try prepare(task, mappings: ["ccbtn:0:20=cue.next", "note:0:62=transport.toggle"], extra: ["-uitestShowSeed"])
        closeSettingsPanel()
        let before = appliedCue() ?? 1
        send("ccbtn20")
        XCTAssertTrue(wait(10) { (self.appliedCue() ?? 0) == before + 1 }, "the CC button steps once")
        send("ccbtn20")
        XCTAssertTrue(wait(10) { (self.appliedCue() ?? 0) == before + 2 }, "and again")
        let paused = app.staticTexts["pausedLabel"].firstMatch
        send("note62")
        let didPause = wait(10) { paused.exists }
        send("note62")
        let resumed = wait(10) { !paused.exists }
        report(task, "transport", ["cue": Double(appliedCue() ?? -1), "paused": didPause ? 1 : 0, "resumed": resumed ? 1 : 0])
        XCTAssertEqual(appliedCue(), before + 2, "each press acted once")
        XCTAssertTrue(didPause && resumed, "the pad toggles Play/Pause once per press")
    }

    /// MIDI-009-T15: the source moves CC 21 and the in-app destination (paired with the source by name, so the app's
    /// feedback goes there) counts what the app sends back. The verdict is the Mac driver's: at most 60 messages and
    /// none more than 1 s after the moves stop (no echo loop); the probe reports it 3 s after the last move. On-screen
    /// changes producing CC out need an on-screen control mapped to feedback; the stand-in for it is the glow following
    /// the moves.
    func testMIDI009FeedbackWithoutEcho() throws {
        let task = "MIDI-009-T15"
        try prepare(task, mappings: ["cc:0:21=effect.bloom.intensity;fb=1"])
        closeSettingsPanel()
        let before = liveGlow()
        send("feedback-move")
        let moved = wait(10) { self.liveGlow().map { v in before.map { abs(v - $0) > 0.005 } ?? true } ?? false }
        let verdict = { self.text("midiProbeFeedback") }
        let judged = wait(12) { verdict().hasPrefix("received ") }
        report(task, "feedback", ["moved": moved ? 1 : 0, "judged": judged ? 1 : 0])
        print("MIDI-FEEDBACK \(verdict())")
        XCTAssertTrue(moved, "the mapped control drives the glow")
        XCTAssertTrue(judged, "the probe judged the feedback: \(verdict())")
        XCTAssertTrue(verdict().hasSuffix("ok 1"), "bounded feedback, nothing after the moves stop: \(verdict())")
    }

    func testMIDI010FollowClock() throws {
        let task = "MIDI-010-T12"
        try prepare(task, settings: ["settings.midi.followClock": true])
        func bpm() -> Double? {
            let s = text("midiClockStatus")
            guard let r = s.range(of: #"[0-9]+\.[0-9]"#, options: .regularExpression) else { return nil }
            return Double(s[r])
        }
        XCTAssertTrue(scrollTo(app.staticTexts["midiClockStatus"].firstMatch), "the clock status row")
        send("clock120")
        let at120 = wait(10) { abs((bpm() ?? 0) - 120) <= 0.1 }
        report(task, "120", ["bpm": bpm() ?? -1])
        send("clock174")   // takes over at once (the source stops the 120 BPM clock)
        let at174 = wait(10) { abs((bpm() ?? 0) - 174) <= 0.1 }
        report(task, "174", ["bpm": bpm() ?? -1])
        send("clockstop")
        // Stop unlocks the clock and the tempo falls back (MIDI-010-S4); the status then reads "MIDI clock: stopped"
        // (contracts/midi-clock.md C4; "No MIDI clock" is the state before any clock arrived).
        let fellBack = wait(10) { self.text("midiClockStatus") == "MIDI clock: stopped" }
        report(task, "stop", ["fellBack": fellBack ? 1 : 0])
        XCTAssertTrue(at120, "120 BPM within 0.1 from the virtual source")
        XCTAssertTrue(at174, "174 BPM within 0.1")
        XCTAssertTrue(fellBack, "Stop falls back: \(text("midiClockStatus"))")
    }

    /// MIDI-012-T15 on D1: save the current mappings as "Profile 1" and export it to Documents (Profile 1.pmmidi).
    func testMIDI012ProfileExport() throws {
        let task = "MIDI-012-T15"
        try prepare(task, mappings: ["cc:0:21=effect.bloom.intensity"])
        openMappings()
        let save = app.buttons["midiProfileSaveCurrent"].firstMatch
        XCTAssertTrue(scrollTo(save), "Profiles")
        save.tap()
        let row = element("midiProfile.Profile 1")
        XCTAssertTrue(wait(5) { row.exists }, "Profile 1 saved")
        // Export… is in the row's More menu (MIDIProfilesSection: Rename…, Export…, Link to Device, Delete…), not a
        // long-press menu (D2 2026-11-21: the press opened nothing).
        let more = app.buttons["midiProfileMore.Profile 1"].firstMatch
        XCTAssertTrue(wait(5) { more.exists } && scrollTo(more), "the row's More menu")
        more.tap()
        let export = app.buttons["Export…"].firstMatch
        XCTAssertTrue(wait(5) { export.exists }, "Export… in the row's More menu")
        export.tap()
        bridgeSaveToDocuments()
        XCTAssertTrue(wait(10) { self.app.navigationBars["MIDI Mappings"].exists }, "back after saving")
        report(task, "export", ["exported": 1])
        ready("PEER", "midi012-exported")
    }

    /// MIDI-012-T15 on D2 (peer.py copied D1's Profile 1.pmmidi into D2's Documents): import, apply, and the virtual
    /// source's CC 21 moves the glow.
    func testMIDI012ProfileImport() throws {
        let task = "MIDI-012-T15"
        try prepare(task, mappings: [])
        openMappings()
        let importButton = app.buttons["midiProfileImport"].firstMatch
        XCTAssertTrue(scrollTo(importButton), "Import…")
        importButton.tap()
        bridgePickFromDocuments("Profile 1.pmmidi")
        let row = element("midiProfile.Profile 1")
        XCTAssertTrue(wait(10) { row.exists }, "the imported profile is listed")
        app.buttons["midiProfileApply.Profile 1"].firstMatch.tap()
        XCTAssertTrue(wait(5) { row.label.hasSuffix("in use") }, "applied: \(row.label)")
        goBack()
        closeSettingsPanel()
        let low = glow(after: "cc21-low", from: liveGlow())
        let high = glow(after: "cc21-high", from: low)
        report(task, "import", ["low": low ?? -1, "high": high ?? -1])
        XCTAssertNotNil(low, "the imported mapping drives the glow")
        if let low, let high { XCTAssertGreaterThan(high, low) }
    }

    func testMIDI013Panic() throws {
        let task = "MIDI-013-T13"
        try prepare(task, mappings: ["note:0:61=blackout;mode=hold"])
        closeSettingsPanel()
        let badge = element("blackoutBadge")
        send("hold61-long")
        XCTAssertTrue(wait(10) { badge.exists }, "the held note blacks out")
        openSettingsPanel()
        let panic = app.buttons["midiPanicButton"].firstMatch
        XCTAssertTrue(scrollTo(panic), "MIDI Panic")
        panic.tap()
        closeSettingsPanel()
        let restored = wait(5) { !badge.exists }
        send("release61")
        pause(3)
        send("pad61")
        let again = wait(10) { badge.exists }
        let releasedAgain = wait(10) { !badge.exists }
        report(task, "panic", ["restored": restored ? 1 : 0, "nextPress": again && releasedAgain ? 1 : 0])
        XCTAssertTrue(restored, "MIDI Panic returns the output")
        XCTAssertTrue(again && releasedAgain, "the next press works")
    }
}
