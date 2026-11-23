// B05AudioDeviceTests.swift — QA-011 owner session B05 ("Audio routes, headphones, calls and interruptions"), the
// parts that need no headphones, calls or listening, automated on the device with generated stereo fixtures
// (scripts/make_music_fixture.py --variant left|inverted, copied by scripts/install_test_fixtures.py).
// AUD-009-T13 (In-App Playback part): with music in the left channel only, Left and Mix move the bars and Right
// leaves them still. ANL-013-T14: a phase-inverted feed reads a negative r on the overlay and the warning shows.
// AUD-006-T39 (background part): a user pause stays paused across background and return; playing resumes.
// QA-011 Batch 3 (2026-11-18): AUD-001-T23/T33, AUD-002-T25/T26/T27, AUD-006-T38/T39/T40/T41, AUD-014-T29/T30,
// AUD-003-T22, AUD-004-T19, AUD-005-T17, AUD-016-T30, PRE-015-T26 with the DEBUG audio probes (AudioProbeSupport.swift).
import UIKit
import XCTest

@MainActor
final class B05AudioDeviceTests: DeviceAcceptanceCase {
    private var overlay: XCUIElement { app.descendants(matching: .any)["performanceOverlay"].firstMatch }

    /// Siri off on the device is a skip with a reason, not a failure (SiriAvailability).
    override func record(_ issue: XCTIssue) {
        if SiriAvailability.swallow(issue) { return }
        super.record(issue)
    }

    /// After the other steps ran: skips the test, naming the Siri steps that could not run.
    private func skipIfSiriStepsSkipped() throws {
        let steps = SiriAvailability.skippedSteps
        SiriAvailability.skippedSteps = []
        try XCTSkipIf(!steps.isEmpty, "\(SiriAvailability.skipReason); not run: \(steps.joined(separator: ", "))")
    }

    /// Mean motion of the whole screen over three pairs of screenshots (the spectrum is most of the moving picture).
    private func motion(_ task: String, _ label: String) -> Double {
        var values: [Double] = []
        for i in 0..<3 {
            let (_, a) = screen(task, "\(label) \(i) a")
            pause(1)
            let (_, b) = screen(task, "\(label) \(i) b")
            values.append(Self.change(a, b))
        }
        let mean = values.reduce(0, +) / Double(values.count)
        report(task, label, ["motionMean": mean, "motionMax": values.max() ?? 0])
        return mean
    }

    /// AUD-009-T13: left-only music; Mix and Left follow it, Right stays still.
    func testAUD009ChannelSelectionFollowsTheChosenChannel() {
        let task = "AUD-009-T13"
        var moved: [String: Double] = [:]
        for mode in ["mix", "left", "right"] {
            launch(visual: "linearSpectrum", settings: ["settings.analysisChannel.mode": mode],
                   fixture: "music-fixture-left.m4a")
            moved[mode] = motion(task, mode)
            app.terminate()
        }
        let left = moved["left"] ?? 0, right = moved["right"] ?? 0, mix = moved["mix"] ?? 0
        XCTAssertGreaterThan(left, 0.004, "Left follows the music (\(left))")
        XCTAssertGreaterThan(mix, 0.004, "Mix follows the music (\(mix))")
        XCTAssertLessThan(right, left / 3, "Right (silent channel) stays far stiller than Left: right \(right), left \(left)")
    }

    /// ANL-013-T14: a phase-inverted feed under Mix: the overlay's r is negative and the warning shows within ~1 s.
    func testANL013PhaseInvertedFeedWarns() {
        let task = "ANL-013-T14"
        launch(visual: "linearSpectrum", fixture: "music-fixture-inverted.m4a")
        let warned = wait(5) { self.overlay.label.contains("phase-inverted") }
        let label = overlay.label
        let r: Double? = label.range(of: #"stereo: r (-?[0-9.]+)"#, options: .regularExpression)
            .flatMap { Double(label[$0].replacingOccurrences(of: "stereo: r ", with: "")) }
        report(task, "inverted", ["r": r ?? 99, "warned": warned ? 1 : 0])
        XCTAssertNotNil(r, "the overlay shows the stereo line: \(label.prefix(200))")
        XCTAssertLessThan(r ?? 1, -0.5, "a negative r for an inverted feed")
        XCTAssertTrue(warned, "the phase-inverted warning shows")
        app.terminate()
        // Switching AUD-009 to Left clears it: one channel cannot be out of phase with itself.
        launch(visual: "linearSpectrum", settings: ["settings.analysisChannel.mode": "left"], fixture: "music-fixture-inverted.m4a")
        pause(3)
        let cleared = !overlay.label.contains("phase-inverted")
        report(task, "left", ["warned": cleared ? 0 : 1])
        XCTAssertTrue(cleared, "Left clears the warning: \(overlay.label.prefix(200))")
    }

    /// AUD-006-T39 (background part): a user pause stays paused across background and return; playing resumes.
    func testAUD006PauseStaysPausedAcrossBackground() {
        let task = "AUD-006-T39"
        launch(visual: "linearSpectrum")
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        let playPause = app.buttons["transportPlayPause"]
        XCTAssertTrue(wait(5) { playPause.exists }, "the transport")
        playPause.tap()
        XCTAssertTrue(wait(5) { self.overlay.label.contains("Paused") }, "paused: \(overlay.label.prefix(120))")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        pause(2)
        XCTAssertTrue(overlay.label.contains("Paused"), "still paused after the return: \(overlay.label.prefix(120))")
        report(task, "paused across background", ["stillPaused": overlay.label.contains("Paused") ? 1 : 0])
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        playPause.tap()
        XCTAssertTrue(wait(10) { self.overlay.label.contains("Active audio") }, "Play resumes: \(overlay.label.prefix(120))")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        let resumed = wait(10) { self.overlay.label.contains("Active audio") }
        report(task, "playing across background", ["resumed": resumed ? 1 : 0])
        XCTAssertTrue(resumed, "playing playback resumes after the return: \(overlay.label.prefix(120))")
    }

    // MARK: - QA-011 Batch 3: imports, transport, queue and interruptions (In-App Playback, probe-measured)
    //
    // The ramp fixtures (`-uitestSeedAudio ramps`, Debug/UITestAudioProbes.swift) carry a time code in channel 0, so
    // the playback probe proves from the delivered samples what was heard: no audio from before a seek, no gap, no
    // repeated fragment. Real interruptions come from SystemUI (Clock timer, Siri); a lost route is synthetic.

    private func chooserLaunch(_ extra: [String], resetLibrary: Bool = true) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestPickerInDocuments"]
            + (resetLibrary ? ["-uitestResetAudioLibrary"] : []) + extra
        app.launch()
        let acknowledge = app.buttons["acknowledgeNotice"]
        if acknowledge.waitForExistence(timeout: 10) { acknowledge.tap() }
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 15), "the chooser offers Import Audio…")
    }

    /// The Import Audio alert's message (after a Files pick). With no alert, a picker still up is cancelled, so the
    /// next file's Import Audio tap is not blocked by it (rerun 3, D3 2026-11-19: "importAudio … not hittable").
    private func importAlertMessage() -> String {
        let alert = app.alerts["Import Audio"]
        guard alert.waitForExistence(timeout: 20) else {
            SystemUI(app: app).cancelFilesPicker()
            return ""
        }
        let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0 != "Import Audio" }.joined(separator: "\n")
        alert.buttons["OK"].tap()
        return text
    }

    /// AUD-006-T38: 20 seeks while playing; the first buffer after each is within 0.25 s of its target (no stale audio
    /// from before the seek), and no later buffer jumps or rewinds. Answers "does player.stop() precede the render
    /// cycle in flight on hardware" with counts.
    func testAUD006TwentySeeksDeliverNoStaleAudio() {
        let task = "AUD-006-T38"
        launchPlayback(task, files: ["ramp-seek.wav"])
        pause(2)
        tapPanel("audio:probeReset")
        for i in 0..<20 {
            let seeksBefore = playbackNumber("seeks")
            tapPanel("audio:seekNext")
            XCTAssertTrue(wait(3) { self.playbackNumber("seeks") > seeksBefore }, "seek \(i + 1) cut in: \(probeValue("playbackProbe"))")
            pause(0.8)
        }
        pause(1)
        reportPlayback(task, "20 seeks")
        XCTAssertEqual(playbackNumber("seeks"), 20, "every seek delivered a cut: \(probeValue("playbackProbe"))")
        XCTAssertEqual(playbackNumber("staleSeeks"), 0, "no seek delivered audio from before it")
        XCTAssertLessThan(playbackNumber("maxSeekErrMs"), 250, "the first buffer after a seek is at the target")
        XCTAssertEqual(playbackNumber("rewinds"), 0, "no old audio later (a rewind inside the track)")
        XCTAssertEqual(playbackNumber("disc"), 0, "no jump forward that no seek explains")
        XCTAssertEqual(playback["state"], "playing")
    }

    /// AUD-006-T39 (D1 part and the 50 ms check): a user pause holds its position across background and return (both
    /// the shown position and the first delivered sample after Play); playing playback continues where it was.
    func testAUD006PausedPositionHoldsAcrossBackground() {
        let task = "AUD-006-T39"
        launchPlayback(task, files: ["ramp-seek.wav"])
        pause(3)
        tapTransport("transportPlayPause")
        XCTAssertTrue(waitForIndicator("· Paused"), "paused: \(sourceIndicator)")
        pause(1)
        let held = playbackNumber("pos")
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        pause(2)
        let after = playbackNumber("pos")
        XCTAssertTrue(sourceIndicator.hasSuffix("· Paused"), "still paused after the return: \(sourceIndicator)")
        XCTAssertLessThan(abs(after - held), 0.05, "the shown position held: \(held) → \(after)")
        tapTransport("transportPlayPause")
        XCTAssertTrue(waitForIndicator("· Active audio"), "Play continues: \(sourceIndicator)")
        pause(1)
        // The 50 ms criterion is "by ear and by the shown time": the first sample delivered after Play (`lastCut`) is
        // at the held, shown position. `cutJumpMs` compares it with the last sample the tap delivered before the
        // pause, and the tap hands over 100 ms blocks: a pause can drop the block in progress, whose audio was rendered
        // and heard but never delivered (D3 pass 3, 2026-11-19: lastCut 8.81 = held 8.81, cutJumpMs 74). So the jump
        // may be up to one block forward, never backward (a repeat).
        let pausedJump = playbackNumber("cutJumpMs")
        let resumedAt = Double((playback["lastCut"] ?? "").split(separator: ":").last ?? "") ?? -1
        XCTAssertLessThan(abs(resumedAt - after), 0.05,
                          "the first sample after Play is at the held position \(after): \(probeValue("playbackProbe"))")
        XCTAssertTrue(pausedJump > -50 && pausedJump < 150,
                      "no repeat, and no jump past the tap's one undelivered block: \(probeValue("playbackProbe"))")
        // Playing across background (the policy pauses it away and resumes on return): continues at the same place.
        pause(2)
        XCUIDevice.shared.press(.home)
        _ = wait(10) { self.app.state != .runningForeground }
        pause(3)
        app.activate()
        _ = wait(10) { self.app.state == .runningForeground }
        XCTAssertTrue(waitForIndicator("· Active audio"), "playing playback resumes after the return: \(sourceIndicator)")
        pause(1)
        let playingJump = playbackNumber("cutJumpMs")
        report(task, "positions", ["heldPos": held, "afterPos": after, "resumedAt": resumedAt, "pausedJumpMs": pausedJump,
                                   "playingJumpMs": playingJump])
        XCTAssertLessThan(abs(playingJump), 50, "it continues from the position it left: \(probeValue("playbackProbe"))")
    }

    /// AUD-006-T40 (automatable part): an alarm (Clock timer) while playing and while paused, Siri while playing, a
    /// lost output route then Play, and Next track between a 48 kHz and a 44.1 kHz track (no gap, no repeat).
    func testAUD006InterruptionsRouteLossAndRateChange() throws {
        SiriAvailability.skippedSteps = []
        let task = "AUD-006-T40"
        launchPlayback(task, files: ["ramp-seek.wav", "ramp-44k.wav"])
        pause(2)
        realInterruption(task, .clockTimer, whilePaused: false)
        realInterruption(task, .siri, whilePaused: false)
        tapTransport("transportPlayPause")
        XCTAssertTrue(waitForIndicator("· Paused"), "user pause: \(sourceIndicator)")
        realInterruption(task, .clockTimer, whilePaused: true)
        if !sourceIndicator.hasSuffix("· Active audio") {
            tapTransport("transportPlayPause")
            XCTAssertTrue(waitForIndicator("· Active audio"), "Play: \(sourceIndicator)")
        }
        routeLostThenPlay(task)
        tapPanel("audio:probeReset")
        tapTransport("transportNext")
        // Next is a hard cut (AUD-006), so the probe counts it as a cut into the next track, never in `changes` (which
        // lists changes at a track's end without a cut). QA-011 pass 4 (D2, D3 2026-11-19): `cuts=1 lastCut=6:0.03
        // track=6 changes=none`, the change done right; the old check read `changes`.
        XCTAssertTrue(wait(5) { self.playbackNumber("cuts") >= 1 && (self.playback["lastCut"] ?? "").hasPrefix("6:") },
                      "Next track cut to the 44.1 kHz track: \(probeValue("playbackProbe"))")
        pause(3)
        reportPlayback(task, "next track across sample rates")
        XCTAssertEqual(playbackNumber("track"), 6, "the 44.1 kHz track plays after Next: \(probeValue("playbackProbe"))")
        XCTAssertEqual(playbackNumber("rewinds"), 0, "no old audio after the change")
        XCTAssertLessThan(playbackNumber("maxSilentMs"), 100, "no gap longer than 100 ms at the change")
        try skipIfSiriStepsSkipped()
    }

    /// AUD-014-T29 (D1) and AUD-014-T30 (D2 iPadOS 27, D3 iPadOS 26): real Clock-timer and Siri interruptions while
    /// playing and while paused; the session log records whether iOS delivered the end and `shouldResume`, and the
    /// transport follows the policy for what arrived. A seek while held then Play continues at the seek target.
    func testAUD014RealSystemInterruptions() throws {
        SiriAvailability.skippedSteps = []
        let task = deviceModel().hasPrefix("iPhone") ? "AUD-014-T29" : "AUD-014-T30"
        launchPlayback(task, files: ["ramp-seek.wav"])
        pause(2)
        for kind in [RealInterruption.clockTimer, .siri] {
            realInterruption(task, kind, whilePaused: false)
            tapTransport("transportPlayPause")
            XCTAssertTrue(waitForIndicator("· Paused"), "user pause: \(sourceIndicator)")
            realInterruption(task, kind, whilePaused: true)
            // Seek while held, then Play: the first delivered buffer is at the target.
            if !sourceIndicator.hasSuffix("· Active audio") {
                tapPanel("audio:seekNext")
                pause(0.5)
                tapTransport("transportPlayPause")
                XCTAssertTrue(waitForIndicator("· Active audio"), "\(kind.rawValue): Play after a seek while held: \(sourceIndicator)")
                pause(1)
                XCTAssertEqual(playbackNumber("staleSeeks"), 0, "\(kind.rawValue): the seek while held plays from its target")
            }
        }
        report(task, "session log", ["began": Double(sessionCounts().began), "ended": Double(sessionCounts().ended),
                                     "resume": Double(sessionCounts().resume)])
        print("DEVICE-ACCEPT-NOTE \(task) sessionLog: \(probeValue("sessionLog"))")
        try skipIfSiriStepsSkipped()
    }

    /// AUD-002-T25: each container from a real encoder imports and reaches "Active audio": MP3 constant and variable
    /// bit rate with ID3 artwork (lame, installed by scripts/install_test_fixtures.py), AAC `.aac`, M4A AAC, M4A Apple
    /// Lossless, WAV and AIFF (AVAudioFile, Apple's encoders, `-uitestSeedAudio containers`); one also through Files.
    func testAUD002EveryContainerReachesActiveAudio() {
        let task = "AUD-002-T25"
        let files = ["music-fixture-cbr.mp3", "music-fixture-vbr.mp3", "seed-adts.aac", "seed-aac.m4a", "seed-alac.m4a",
                     "seed-pcm.wav", "seed-pcm.aif"]
        for file in files {
            launch(visual: "linearSpectrum", extra: ["-uitestResetAudioLibrary", "-uitestSeedAudio", "containers"], fixture: file)
            let active = overlayLabel.contains("Active audio")
            report(task, file, ["activeAudio": active ? 1 : 0])
            XCTAssertTrue(active, "\(file) reaches Active audio: \(sourceIndicator)")
            app.terminate()
        }
        // The same import through the real document picker (On My iPhone/iPad › projectM-iOS).
        chooserLaunch(["-uitestSeedAudio", "containers"])
        app.buttons["importAudio"].tap()
        pickFromAppDocuments("seed-alac.m4a")
        let row = app.buttons["importedTrack"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the picked file is listed")
        row.tap()
        XCTAssertTrue(waitForIndicator("· Active audio", 15), "the picked ALAC file plays: \(sourceIndicator)")
        report(task, "files picker alac", ["activeAudio": sourceIndicator.hasSuffix("· Active audio") ? 1 : 0])
    }

    /// AUD-002-T26 (automatable part): an MP3 and an M4A track through a real alarm (Clock timer) and a lost route
    /// behave as the reference track does.
    func testAUD002AlarmAndRouteLossMatchTheReferenceTrack() {
        let task = "AUD-002-T26"
        var outcomes: [String: [String: Double]] = [:]
        for file in ["reference", "music-fixture-vbr.mp3", "seed-aac.m4a"] {
            if file == "reference" {
                launch(visual: "linearSpectrum", extra: ["-uitestSessionLog", "-uitestSessionEvents"], music: false)
            } else {
                launch(visual: "linearSpectrum", extra: ["-uitestResetAudioLibrary", "-uitestSeedAudio", "containers",
                                                         "-uitestSessionLog", "-uitestSessionEvents"], fixture: file)
            }
            XCTAssertTrue(waitForIndicator("· Active audio", 15), "\(file) plays: \(sourceIndicator)")
            outcomes[file] = realInterruption("\(task) \(file)", .clockTimer, whilePaused: false, ramp: false)
            routeLostThenPlay("\(task) \(file)")
            app.terminate()
        }
        let reference = outcomes["reference"] ?? [:]
        for file in ["music-fixture-vbr.mp3", "seed-aac.m4a"] {
            for key in ["autoResumed", "held", "playResumes"] {
                XCTAssertEqual(outcomes[file]?[key], reference[key], "\(file) \(key) as for the reference track")
            }
        }
    }

    /// AUD-002-T27: a damaged M4A and a PDF named `.mp3` picked in Files show the contract messages, and the same
    /// text is posted as the VoiceOver announcement (`importProbe` reads what was announced).
    func testAUD002DamagedAndNonAudioFromFiles() {
        let task = "AUD-002-T27"
        let expected = ["seed-damaged.m4a": "“seed-damaged.m4a”: This audio file can't be read. It may be damaged.",
                        "seed-notaudio.mp3": "“seed-notaudio.mp3”: This file's format isn't supported. Import MP3, AAC, M4A, WAV or AIFF audio."]
        chooserLaunch(["-uitestSeedAudio", "broken"])
        for (name, message) in expected.sorted(by: { $0.key < $1.key }) {
            app.buttons["importAudio"].tap()
            pickFromAppDocuments(name)
            let shown = importAlertMessage()
            let announced = probeValue("importProbe").components(separatedBy: "announce=").last ?? ""
            report(task, name, ["messageMatches": shown == message ? 1 : 0, "announced": announced == message ? 1 : 0])
            XCTAssertEqual(shown, message, "\(name): the contract message")
            XCTAssertEqual(announced, message, "\(name): announced to VoiceOver")
        }
        XCTAssertFalse(app.buttons["importedTrack"].exists, "neither file is listed")
    }

    /// AUD-001-T23 (owner ruling 2026-11-18: the Airplane Mode step is not required): import through Files, the
    /// original deleted, relaunch, play from the library's own copy.
    func testAUD001ImportFromFilesSurvivesOriginalDeleted() {
        let task = "AUD-001-T23"
        chooserLaunch(["-uitestSeedAudio", "original"])
        app.buttons["importAudio"].tap()
        pickFromAppDocuments("aud001-original.m4a")
        XCTAssertTrue(app.buttons["importedTrack"].firstMatch.waitForExistence(timeout: 20), "imported")
        app.terminate()
        // The original goes (the app deletes its own Documents copy, which is the picked location), then a relaunch.
        app.launchArguments = ["-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestDeleteDocument", "aud001-original.m4a"]
        app.launch()
        let row = app.buttons["importedTrack"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the track is still listed after the original is gone")
        row.tap()
        let active = waitForIndicator("· Active audio", 15)
        report(task, "played without the original", ["activeAudio": active ? 1 : 0])
        XCTAssertTrue(active, "plays from the library's copy: \(sourceIndicator)")
    }

    /// AUD-001-T33 (S1 and the interruption part): a 10.6 MB WAV is imported and listed within 2 s; an imported track
    /// through a real alarm and a lost route behaves as the reference track (FR-051).
    func testAUD001LargeFileListedWithinTwoSecondsAndInterruptions() {
        let task = "AUD-001-T33"
        launch(visual: "linearSpectrum", extra: ["-uitestResetAudioLibrary", "-uitestSeedAudio", "large", "-uitestSessionLog",
                                                 "-uitestSessionEvents"], fixture: "seed-10mb.wav")
        let imports = probeValue("importProbe")
        let ms = imports.range(of: #"seed-10mb\.wav=([0-9]+)"#, options: .regularExpression)
            .flatMap { Double(imports[$0].split(separator: "=").last ?? "") } ?? -1
        report(task, "10 MB import", ["importMs": ms])
        XCTAssertGreaterThanOrEqual(ms, 0, "the import was timed: \(imports)")
        XCTAssertLessThan(ms, 2000, "AUD-001-S1: listed within 2 s")
        realInterruption(task, .clockTimer, whilePaused: false, ramp: false)
        routeLostThenPlay(task)
    }

    /// AUD-001-T33 (S7): a 60-minute imported track plays for 60 s without the footprint growing (memoryProbe). The
    /// first run on a device writes the file (`-uitestSeedAudio long`, about a minute or two); later runs reuse it.
    func testAUD001SixtyMinuteTrackMemory() {
        let task = "AUD-001-T33"
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO",
                               "-uitestResetAudioLibrary", "-uitestSeedAudio", "long", "-uitestImportAudio", "seed-60min.m4a",
                               "-uitestPlayImported", "YES"]
        app.launch()
        XCTAssertTrue(wait(240) { self.sourceIndicator.hasSuffix("· Active audio") }, "the 60-minute track plays: \(sourceIndicator)")
        func footprint() -> Double { probeNumber("memoryProbe", "footprintMB") }
        pause(5)
        let first = footprint()
        var samples: [Double] = []
        for _ in 0..<12 { pause(5); samples.append(footprint()) }
        let growth = (samples.last ?? first) - first
        report(task, "60-minute track", ["firstMB": first, "maxMB": samples.max() ?? 0, "growthMB": growth])
        XCTAssertGreaterThan(first, 0, "memoryProbe is readable")
        XCTAssertLessThan(growth, 20, "the footprint does not grow with a streamed 60-minute track (\(first) → \(samples))")
        XCTAssertTrue(sourceIndicator.hasSuffix("· Active audio"), "still playing")
    }

    /// AUD-003-T22: queue edits while playing never cut, gap or repeat audio: reorder the others, move the playing
    /// track, remove it (it plays to its end), add a track while a lone track loops (it ends once, the new one
    /// follows), reorder during an interruption; a relaunch keeps the queue order.
    func testAUD003QueueEditsLeaveNoGapOrRepeat() {
        let task = "AUD-003-T22"
        launchPlayback(task, files: ["ramp-q1.wav", "ramp-q2.wav", "ramp-q3.wav"])
        pause(2)
        tapPanel("audio:probeReset")
        for edit in ["audio:queueReorderOthers", "audio:queueMoveCurrent"] {
            tapPanel(edit)
            pause(2)
        }
        tapPanel("session:interruptBegan")
        pause(1)
        tapPanel("audio:queueReorderOthers")
        tapPanel("session:interruptEndedResume")
        XCTAssertTrue(waitForIndicator("· Active audio"), "resumes after the interruption as without the edit: \(sourceIndicator)")
        pause(1)
        let jump = playbackNumber("cutJumpMs")
        tapPanel("audio:queueRemoveCurrent")
        pause(2)
        reportPlayback(task, "edits while playing")
        XCTAssertEqual(playbackNumber("rewinds"), 0, "no repeated fragment: \(probeValue("playbackProbe"))")
        XCTAssertEqual(playbackNumber("disc"), 0, "no jump")
        XCTAssertFalse((playback["changes"] ?? "").contains("!"), "no track change cut in at an edit")
        // The silence between a track that played to its end and the next one is `changeGapMs`, reported, not part of
        // this check: the next track is scheduled once the last one has rendered (AUD-006-R17, no gapless promise).
        // QA-011 pass 9 (D2, 2026-11-19): 74 ms there (1>2, `undecoded=0.0000/0.1300/…`), 64 ms in the step below.
        XCTAssertLessThan(playbackNumber("maxSilentMs"), 50, "no gap at an edit: \(probeValue("playbackProbe"))")
        XCTAssertLessThan(abs(jump), 300, "the interruption resumed at its position")
        let queueBefore = probeFields("importProbe")["queue"] ?? ""
        app.terminate()
        app.launchArguments = ["-uitestDiagnostics", "-uitestUnlocked", "NO", "-uitestAudioPanel"]
        app.launch()
        // The relaunch need not land on the chooser (D1 and D3 2026-11-18: no Import Audio within 15 s; without
        // `-uitestResetNotice` the app may restore the last scene): `importProbe` is on every screen and reads the queue.
        XCTAssertTrue(wait(15) { !(self.probeFields("importProbe")["queue"] ?? "").isEmpty }, "relaunched, the queue is read: \(probeValue("importProbe"))")
        let queueAfter = probeFields("importProbe")["queue"] ?? ""
        XCTAssertEqual(queueAfter, queueBefore, "a relaunch keeps the queue")
        app.terminate()

        // A lone looping track, then a second one is added: it ends once and the new one follows at its end.
        launchPlayback(task, files: ["ramp-q1.wav"])
        XCTAssertTrue(wait(15) { self.playbackNumber("wraps") >= 1 }, "the lone track loops: \(probeValue("playbackProbe"))")
        tapPanel("audio:probeReset")
        tapPanel("audio:importNext")
        XCTAssertTrue(wait(16) { (self.playback["changes"] ?? "none") != "none" }, "the added track follows: \(probeValue("playbackProbe"))")
        reportPlayback(task, "add to a looping track")
        XCTAssertEqual(playback["changes"], "1>2", "at the end of track 1, track 2 (no cut-in, no extra loop)")
        XCTAssertEqual(playbackNumber("wraps"), 0, "the lone track ended once instead of looping again")
        XCTAssertEqual(playbackNumber("rewinds"), 0, "no repeated fragment at the edit")
    }

    /// AUD-004-T19 (automatable part): Off stops after the last track with the first track cued at 0:00; One Track
    /// loops without a silent buffer; an interruption during One Track resumes and it keeps looping; mode changes
    /// during playback cut nothing.
    func testAUD004RepeatModes() {
        let task = "AUD-004-T19"
        launchPlayback(task, files: ["ramp-q1.wav", "ramp-q2.wav", "ramp-q3.wav"])
        tapPanel("audio:repeat:one")
        tapPanel("audio:probeReset")
        XCTAssertTrue(wait(15) { self.playbackNumber("wraps") >= 1 }, "One Track repeats: \(probeValue("playbackProbe"))")
        tapPanel("session:interruptBegan")
        pause(1)
        tapPanel("session:interruptEndedResume")
        XCTAssertTrue(waitForIndicator("· Active audio"), "resumes: \(sourceIndicator)")
        let wraps = playbackNumber("wraps")
        XCTAssertTrue(wait(15) { self.playbackNumber("wraps") > wraps }, "still One Track after the interruption")
        reportPlayback(task, "one track")
        XCTAssertEqual(playbackNumber("silentBuffers"), 0, "no silent buffer at the loop (no gap)")
        XCTAssertEqual(playback["changes"], "none", "One Track never changes the track")
        tapPanel("audio:probeReset")
        for mode in ["all", "off", "one", "all"] { tapPanel("audio:repeat:\(mode)"); pause(1) }
        reportPlayback(task, "mode changes")
        XCTAssertEqual(playbackNumber("disc") + playbackNumber("rewinds"), 0, "mode changes cut nothing")
        XCTAssertFalse((playback["changes"] ?? "").contains("!"), "no change cut in")
        XCTAssertLessThan(playbackNumber("maxSilentMs"), 25, "no gap")
        // Off: play through to the end of the last track; then stopped at the first track's 0:00.
        tapPanel("audio:repeat:off")
        XCTAssertTrue(wait(45) { self.playback["state"] == "stopped" }, "Off stops after the last track: \(probeValue("playbackProbe"))")
        let title = app.staticTexts["transportTitle"]
        revealControls()
        let first = (probeFields("importProbe")["queue"] ?? "").split(separator: ",").first.map(String.init) ?? ""
        report(task, "off", ["pos": playbackNumber("pos"), "stopped": playback["state"] == "stopped" ? 1 : 0])
        XCTAssertEqual(playbackNumber("pos"), 0, "cued at 0:00")
        XCTAssertEqual(title.exists ? title.label : "", first, "the first queued track is cued")
        XCTAssertTrue(sourceIndicator.contains("Stopped") || playback["state"] == "stopped", "Stopped: \(sourceIndicator)")
    }

    /// AUD-005-T17: five tracks, Shuffle on and off while playing, a lost route and an interruption; Shuffle changes
    /// never cut, gap or repeat audio (AUD-005-R15).
    func testAUD005ShuffleNeverCutsAudio() {
        let task = "AUD-005-T17"
        launchPlayback(task, files: (1...5).map { "ramp-q\($0).wav" })
        pause(2)
        tapPanel("audio:probeReset")
        for state in ["on", "off", "on", "off", "on"] { tapPanel("audio:shuffle:\(state)"); pause(1.5) }
        reportPlayback(task, "shuffle changes")
        XCTAssertEqual(playbackNumber("disc") + playbackNumber("rewinds"), 0, "Shuffle changes cut nothing: \(probeValue("playbackProbe"))")
        XCTAssertFalse((playback["changes"] ?? "").contains("!"), "no track change at a Shuffle change")
        XCTAssertEqual(playbackNumber("silentBuffers"), 0, "no gap")
        routeLostThenPlay(task)
        tapPanel("session:interruptBegan")
        pause(1)
        tapPanel("session:interruptEndedResume")
        XCTAssertTrue(waitForIndicator("· Active audio"), "resumes: \(sourceIndicator)")
        tapPanel("audio:shuffle:off")
        pause(2)
        XCTAssertEqual(playbackNumber("disc") + playbackNumber("rewinds"), 0, "still no cut after the route and interruption")
    }

    /// AUD-016-T30 (automatable part): each signal kind's status, then a lost route and a real alarm on a tone behave
    /// as for an imported track. Release generation time: AutomationRunner mode `aud016` (matrix).
    func testAUD016EachSignalStatus() {
        let task = "AUD-016-T30"
        let signals: [(String, String, String)] = [
            ("sine-1k", "Test tone 1 kHz", "Active audio"), ("sweep-log", "Test sweep 20 Hz–20 kHz, logarithmic", "Active audio"),
            ("pulse-120", "Test pulses 120 BPM", "Audio received — silent"), ("silence", "Test silence", "Audio received — silent"),
        ]
        for (id, name, status) in signals {
            chooserLaunch(["-uitestSessionLog", "-uitestSessionEvents"], resetLibrary: false)
            let row = app.buttons["testSignals"]
            for _ in 0..<6 where !row.isHittable { app.swipeUp() }
            row.tap()
            let signal = app.buttons["testSignal.\(id)"]
            for _ in 0..<6 where !signal.exists { app.swipeUp() }
            signal.tap()
            let expected = "In-App Playback · \(name) · \(status)"
            let ok = wait(15) { self.sourceIndicator == expected }
            report(task, id, ["statusMatches": ok ? 1 : 0])
            XCTAssertTrue(ok, "\(id): \"\(expected)\"; shows \"\(sourceIndicator)\"")
            if id == "sine-1k" {
                routeLostThenPlay("\(task) \(id)")
                realInterruption("\(task) \(id)", .clockTimer, whilePaused: false, ramp: false)
            }
            app.terminate()
        }
    }

    /// AUD-006-T41 (D1 at the largest text size): every transport control is shown inside the window and hittable, the
    /// scrubber moves the position and its value reads the time, and the transport passes the
    /// accessibility audit for clipped text and descriptions. VoiceOver speech itself stays with a person.
    ///
    /// QA-011 pass 3 (2026-11-19; D1-D3 in every run): the transport was drawn whole on screen at AX5, but the
    /// performance overlay (FR-048, a readout whose text grows to the whole screen at AX5) and the DEBUG `importProbe`
    /// (96 pt tall at AX5) lay over it, so XCUITest's accessibility hit test reported the buttons not hittable. The
    /// probes now keep one text size, and this test runs without the overlay: the transport's layout is under test.
    /// At AX5 the controls scroll and open at their bottom (ACC-006-R2), so the test drags them down to the transport.
    func testAUD006TransportAtLargestTextSize() throws {
        let task = "AUD-006-T41"
        launchPlayback(task, files: ["ramp-seek.wav"], settings: ["settings.performanceOverlay": false],
                       extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        revealControls()
        let controls = app.otherElements["controls"], playPause = app.buttons["transportPlayPause"]
        // The drag starts inside the visible part of the controls. QA-011 D1 full run 1 (2026-11-22, iPhone 15): the
        // `controls` element is the whole scroll content, taller than the phone's window at AX5 and anchored at the
        // bottom, so its 25 % point lay above the window; the four drags scrolled nothing, the controls hid 5 s after
        // the reveal and the next drag found no "controls". Start at 60 % of the visible part (below the DEBUG
        // panels) and drag down by at most what stays inside the window; re-reveal if they hid meanwhile.
        for _ in 0..<4 where !(playPause.exists && playPause.isHittable) {
            if !controls.exists { revealControls() }
            guard controls.exists else { break }
            let windowFrame = app.windows.firstMatch.frame
            let visible = controls.frame.intersection(windowFrame)
            guard !visible.isNull, visible.height > 40 else { break }
            let startY = visible.minY + visible.height * 0.6
            let drag = min(300, windowFrame.maxY - 20 - startY)
            let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: startY))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: max(drag, 60))),
                       withVelocity: .default, thenHoldForDuration: 0.1)
        }
        let window = app.windows.firstMatch.frame
        for id in ["transportPrevious", "transportPlayPause", "transportStop", "transportNext"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists && button.isHittable, "\(id) is shown and hittable at AX5")
            XCTAssertTrue(window.contains(button.frame), "\(id) is inside the window: \(button.frame) in \(window)")
        }
        let scrubber = app.descendants(matching: .any)["transportScrubber"].firstMatch
        XCTAssertTrue(scrubber.exists && window.contains(scrubber.frame), "the scrubber is inside the window")
        tapTransport("transportPlayPause")   // paused: the position stays put while it is read
        XCTAssertTrue(waitForIndicator("· Paused"))
        // XCUITest has no public adjustable increment on iOS: the scrubber is moved to 50 % of the 60 s ramp instead, and
        // the shown position and the delivered audio follow (the VoiceOver 10 s increment stays with a person). The
        // scrubber is the app's own adjustable element (type Other, D2 2026-11-18: `adjust(toNormalizedSliderPosition:)`
        // raised "Can only adjust position of slider elements"), so it is dragged as TransportUITests does.
        revealControls()
        if scrubber.elementType == .slider {
            scrubber.adjust(toNormalizedSliderPosition: 0.5)
        } else {
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
                .press(forDuration: 0.2, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        pause(1)
        let after = playbackNumber("pos")
        let value = (scrubber.value as? String) ?? ""
        report(task, "scrubber adjust", ["after": after])
        XCTAssertEqual(after, 30, accuracy: 2, "the scrubber moves the position at AX5")
        XCTAssertTrue(value.contains("second") || value.contains(":"), "the scrubber's value reads the time: \(value)")
        revealControls()
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription]) { issue in
            // Only the transport is under test here; the DEBUG probes and panel are not the app's UI.
            !(issue.element?.identifier.hasPrefix("transport") ?? false)
        }
    }

    /// PRE-015-T26 (S7): the editor opens the 524,288-byte user preset in under 2 s; the editor passes the
    /// accessibility audit for clipped text and descriptions. VoiceOver listening stays with a person.
    func testPRE015LargePresetOpensUnder2s() throws {
        let task = "PRE-015-T26"
        XCUIDevice.shared.orientation = .portrait
        // D1 and D3 2026-11-18: the row was missing on a device's first run: the preset import hook raced the seed
        // writer (two launch tasks); the DEBUG hook now writes the `bigpreset` seed itself before it imports.
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestUnlocked", "NO", "-autostart", "inAppPlayback",
                               "-uitestSeedAudio", "bigpreset", "-uitestImportPreset", "pre015-large.milk"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sourceStarts"].waitForExistence(timeout: 30))
        pause(5)   // the import runs after the renderer's preset trial
        tapTransport("presets")
        let mine = app.buttons["node:myPresets"]
        for _ in 0..<4 where !mine.isHittable { app.swipeUp() }
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "library home")
        mine.tap()
        let row = app.buttons["preset:pre015-large"]
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the large preset was imported")
        row.press(forDuration: 1.2)
        let edit = app.buttons["editUserPreset"].exists ? app.buttons["editUserPreset"] : app.collectionViews.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "Edit")
        let started = Date()
        edit.tap()
        let editor = app.textViews["presetEditorText"]
        // Polled every 0.2 s: `waitForExistence` checks about once a second on a device, so D2's 2.16 s (2026-11-18)
        // carried up to a second of polling.
        let opened = wait(10) { editor.exists }
        let seconds = Date().timeIntervalSince(started)
        report(task, "open editor", ["seconds": seconds])
        XCTAssertTrue(opened, "the editor opens")
        XCTAssertLessThan(seconds, 2, "S7: under 2 s")
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription]) { issue in
            !(issue.element?.identifier.hasPrefix("presetEditor") ?? false)
        }
    }
}
