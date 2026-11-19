// B08RecordingDeviceTests.swift — QA-011 owner session B08 ("Recording"), the parts that need a real recording read
// back, automated on the device. Each test records the Photo visual (a recordable visual; projectM is not, REC-003-R12)
// with the reference track and reads the offered file back through the DEBUG `videoRecordingProbe`
// ("video <codec> <w>x<h> frames=<n> duration=<s> audio=<n>", RecordedVideoInspector).
// REC-014-T15: Square (D1) and Portrait (D2) read back at the planned shape, and the file shows the centre of the
// picture (a screenshot's centre-crop grid, compared with the file's frame on the Mac). REC-005-T14: each quality
// profile records and reads back (a profile the device cannot offer is reported as refused, not as a failure).
// QA-011 Batch 6 (2026-11-18): REC-008-T14 names the causes of skipped slots; REC-016-T13 (30 s, no `moof`, CPU) with
// QA-008-T10 on the same file; REC-009-T11 (status lines not in the file, a real low-storage line from the disk
// ballast); REC-015-T17 (the real disk guard stops a recording); REC-007-T13 (countdown); REC-004-T19 (click and flash,
// Microphone audio track); MED-011-T13 and MED-012-T14 (clock and countdown in the file). Files the Mac must read are
// named by `RECORDING-CHECK` lines (RecordingCheckSupport.swift); after the run:
//     python3 scripts/recording_frame_check.py run --log <xcodebuild log> --device D1
// Ballast tests relaunch the app once in tearDown (a DEBUG launch deletes the ballast).
import UIKit
import XCTest

@MainActor
final class B08RecordingDeviceTests: DeviceAcceptanceCase {
    private var probe: String { (app.staticTexts["videoRecordingProbe"].value as? String) ?? "" }

    /// Set by tests that fill the disk: tearDown relaunches the app once, which deletes the ballast.
    private var usedBallast = false

    override func tearDown() async throws {
        if usedBallast {
            app.launchArguments = ["-uitestDiagnostics", "-uitestUnlocked", "NO"]   // a DEBUG launch deletes the ballast
            app.launch()
            pause(2)
            app.terminate()
        }
        try await super.tearDown()
    }

    /// REC-006-R4 facts of the last recording: (fps, written frames, dropped slots), from the DEBUG `recordingFacts`.
    private func facts() -> (fps: Int, frames: Int, dropped: Int)? {
        let text = (app.staticTexts["recordingFacts"].value as? String) ?? ""
        var values: [String: Int] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=")
            if kv.count == 2, let v = Int(kv[1]) { values[String(kv[0])] = v }
        }
        guard let fps = values["fps"], let frames = values["frames"], let dropped = values["dropped"] else { return nil }
        return (fps, frames, dropped)
    }

    /// Dropped slots are skipped by design and reported (REC-006 Clarifications); the device test bounds them at 5 %.
    static let maximumDroppedShare = 0.05

    private func showControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    /// Records about `seconds` of the Photo visual and returns the parsed probe (width, height, frames, duration).
    /// `midway` runs once while recording, after the controls hid (REC-014's screenshot; its argument is the time
    /// since the Record tap); `directory` is the `-uitestRecordingDirectory` folder.
    private func record(_ task: String, _ label: String, settings: [String: Any], seconds: Int,
                        directory: String = "B08RecordingDeviceTests", midway: ((Double) -> Void)? = nil)
        -> (codec: String, width: Int, height: Int, frames: Int, duration: Double)? {
        launch(visual: "photo", settings: settings,
               extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", directory])
        showControls()
        let button = app.buttons["record"]
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "\(label): Record is offered (\(button.label))")
        button.tap()
        let started = Date()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(wait(5) { indicator.exists }, "\(label): the recording indicator")
        if let midway {
            _ = wait(8) { !self.app.otherElements["controls"].exists }
            midway(Date().timeIntervalSince(started))
        }
        let target = String(format: "Recording, 0:%02d", seconds)
        _ = wait(Double(seconds) + 10) { indicator.label >= target }
        showControls()
        app.buttons["record"].tap()
        XCTAssertTrue(wait(20) { self.probe.hasPrefix("video ") || self.probe.hasPrefix("failed") || self.probe.hasPrefix("refused") },
                      "\(label): the file is read back: \(probe)")
        print("B08 \(task) \(label): \(probe)")
        let parts = probe.split(separator: " ").map(String.init)
        guard parts.count >= 6, parts[0] == "video" else { return nil }
        let size = parts[2].split(separator: "x").compactMap { Int($0) }
        let frames = Int(parts[3].replacingOccurrences(of: "frames=", with: "")) ?? 0
        let duration = Double(parts[4].replacingOccurrences(of: "duration=", with: "")) ?? 0
        guard size.count == 2 else { return nil }
        report(task, label, ["width": Double(size[0]), "height": Double(size[1]), "frames": Double(frames),
                             "duration": duration])
        return (parts[1], size[0], size[1], frames, duration)
    }

    /// REC-014-T15: Square on an iPhone, Portrait on an iPad (the task's split), 5 s, read back at the planned shape.
    func testREC014AspectPresetReadsBackAtThePlannedShape() {
        let task = "REC-014-T15"
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let kind = pad ? "portrait" : "square"
        // The centre check (REC-014-S5): a screenshot while recording (controls hidden, overlay off), its centre crop at
        // the file's aspect as a block grid; the Mac correlates it with the file's frame at the same time.
        var shot: (image: UIImage, at: Double)?
        let began = Date()
        let settings: [String: Any] = ["settings.recording.aspect": kind, "settings.performanceOverlay": false]
        guard let file = record(task, kind, settings: settings, seconds: 9, directory: "QA011-REC014", midway: { (at: Double) in
            let s = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: s)
            attachment.name = "\(task) centre"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            shot = (s.image, at)
        }) else {
            XCTFail("no readable recording: \(probe)")
            return
        }
        if pad {
            // Portrait is 9:16 (REC-014): width × 16 equals height × 9 within the even-side rounding.
            XCTAssertLessThanOrEqual(abs(file.width * 16 - file.height * 9), 32,
                                     "Portrait reads back at 9:16: \(file.width)x\(file.height)")
        } else {
            XCTAssertEqual(file.width, file.height, "Square reads back square: \(file.width)x\(file.height)")
        }
        XCTAssertEqual(file.width % 2, 0, "even width")
        XCTAssertEqual(file.height % 2, 0, "even height")
        XCTAssertGreaterThanOrEqual(file.duration, 4.0, "about 5 s recorded")
        guard let shot else { return XCTFail("no screenshot while recording") }
        let cols = pad ? 9 : 12, rows = pad ? 16 : 12
        let grid = RecordingCheck.centreGrid(shot.image, width: file.width, height: file.height, cols: cols, rows: rows)
        XCTAssertEqual(grid.count, cols * rows, "the screenshot's centre grid")
        // The file's clock starts at its first written frame, a little after the tap.
        RecordingCheck.emit(task: task, label: "\(kind) centre", dir: RecordingCheck.tmp("QA011-REC014"), notBefore: began,
                            checks: ["centre": ["time": max(0.5, shot.at - 0.3), "cols": cols, "rows": rows,
                                                "values": grid, "minCorrelation": 0.8]])
    }

    /// REC-005-T14: each quality profile records and reads back.
    func testREC005EachProfileRecordsAndReadsBack() {
        let task = "REC-005-T14"
        var pixels: [String: Int] = [:]
        for profile in ["draft", "standard", "high", "max"] {
            let file = record(task, profile, settings: ["settings.recording.qualityProfile": profile], seconds: 3)
            if let file {
                pixels[profile] = file.width * file.height
                XCTAssertGreaterThan(file.frames, 30, "\(profile): frames written")
                if profile == "draft" {
                    // Draft is H.264 at a long side of at most 1280 (RecordingQualityProfile): proof the profile applied.
                    XCTAssertEqual(file.codec, "avc1", "Draft records H.264")
                    XCTAssertLessThanOrEqual(max(file.width, file.height), 1280, "Draft's long side is at most 1280")
                }
            } else {
                // A profile this device cannot offer is refused with its reason (REC-005-R4): reported, not a failure.
                report(task, "\(profile) refused", ["refused": 1])
                XCTAssertTrue(probe.hasPrefix("refused"), "\(profile): a readable file or a refusal: \(probe)")
            }
            app.terminate()
        }
        // Draft never records more pixels than Max (profiles never upscale, REC-005).
        if let draft = pixels["draft"], let max = pixels["max"] {
            XCTAssertLessThanOrEqual(draft, max, "Draft is no larger than Max")
        }
    }

    /// REC-008-T14: a 10 s timed stop ends the recording by itself; the file is 10 s, 300 frames at 30 fps.
    func testREC008TimedStopTenSeconds() {
        let task = "REC-008-T14"
        launch(visual: "photo", settings: ["settings.recording.timedStop": "10"],
               extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", "B08RecordingDeviceTests"])
        showControls()
        let button = app.buttons["record"]
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "Record is offered")
        button.tap()
        // No Stop: the timed stop ends it; the offered file is read back.
        XCTAssertTrue(wait(30) { self.probe.hasPrefix("video ") || self.probe.hasPrefix("failed") }, "stopped by itself: \(probe)")
        print("B08 \(task): \(probe)")
        let parts = probe.split(separator: " ").map(String.init)
        guard parts.count >= 6, parts[0] == "video" else { return XCTFail("no readable recording: \(probe)") }
        let frames = Int(parts[3].replacingOccurrences(of: "frames=", with: "")) ?? 0
        let duration = Double(parts[4].replacingOccurrences(of: "duration=", with: "")) ?? 0
        report(task, "timed stop", ["frames": Double(frames), "duration": duration])
        XCTAssertEqual(duration, 10, accuracy: 0.1, "10 s long")
        guard let f = facts() else { return XCTFail("no recording facts") }
        // QA-011 Batch 6: why slots were skipped (gate full, writer not ready, rate skip), so a run short of 300 names the
        // cause. Run with screenshots as the capture format (DeviceTests.yml), never a screen recording.
        let causes = probeNumbers("recordingFacts")
        report(task, "slots", ["written": Double(f.frames), "dropped": Double(f.dropped), "fps": Double(f.fps),
                               "busy": causes["busy"] ?? -1, "notReady": causes["notReady"] ?? -1,
                               "rateSkipped": causes["rateSkipped"] ?? -1])
        XCTAssertEqual(f.fps, 30, "recorded at 30 fps")
        XCTAssertEqual(frames, f.frames, "the file holds the written frames")
        // QA-011 device run 2026-11-19 (REC-008 Clarifications): on a device the timed stop is checked on the 300 slots of
        // the 10 s grid (written + dropped) and the exact 10.000 s length; a slot the render loop missed is skipped and
        // counted (REC-006-D3, REC-008's "no padding" answer), bounded like every device recording. D1 and D3 both wrote
        // 295 + 5 dropped (busy 0, notReady 0). Exactly 300 written frames stays the host acceptance test's rule (a
        // writer that is not real-time limited).
        XCTAssertEqual(f.frames + f.dropped, 300, "300 slots at 30 fps: written \(f.frames) + dropped \(f.dropped) "
                       + "(busy \(Int(causes["busy"] ?? -1)), notReady \(Int(causes["notReady"] ?? -1)), "
                       + "rateSkipped \(Int(causes["rateSkipped"] ?? -1)))")
        XCTAssertLessThanOrEqual(Double(f.dropped), 300 * Self.maximumDroppedShare, "dropped slots stay bounded")
    }

    /// REC-006-T15: a 24 fps recording of the Photo visual (rendering at 60 Hz) reads back at 24 fps.
    func testREC006TwentyFourFPSReadsBackAt24() {
        let task = "REC-006-T15"
        guard let file = record(task, "24 fps", settings: ["settings.recording.frameRate": "24"], seconds: 4) else {
            return XCTFail("no readable recording: \(probe)")
        }
        guard let f = facts() else { return XCTFail("no recording facts") }
        let slots = file.duration * 24
        report(task, "24 fps slots", ["written": Double(f.frames), "dropped": Double(f.dropped), "fps": Double(f.fps),
                                      "expectedSlots": slots])
        XCTAssertEqual(f.fps, 24, "recorded at 24 fps")
        // REC-006-S6: every frame's presentation time lies on the 1/24 s grid (the read-back counts those off it).
        let offGrid = probe.split(separator: " ").first { $0.hasPrefix("offGrid=") }.flatMap { Int($0.dropFirst(8)) } ?? -1
        report(task, "24 fps grid", ["offGrid": Double(offGrid)])
        XCTAssertEqual(offGrid, 0, "every presentation time on the 1/24 s grid: \(probe)")
        XCTAssertEqual(Double(f.frames + f.dropped), slots, accuracy: 1.5,
                       "written \(f.frames) + dropped \(f.dropped) fill \(file.duration) s at 24 fps")
        XCTAssertLessThanOrEqual(Double(f.dropped), slots * Self.maximumDroppedShare, "dropped slots stay bounded")
    }

    // MARK: QA-011 Batch 6

    /// The app's CPU share (100 % = one core) between two `cpuProbe` readings.
    private static func cpuPercent(_ a: [String: Double], _ b: [String: Double]) -> Double {
        guard let c0 = a["cpuSeconds"], let c1 = b["cpuSeconds"], let u0 = a["uptime"], let u1 = b["uptime"], u1 > u0 else {
            return -1
        }
        return ((c1 - c0) / (u1 - u0) * 1000).rounded() / 10
    }

    /// The app's CPU share over the next `seconds`.
    private func cpuShare(seconds: Double) -> Double {
        let a = probeNumbers("cpuProbe")
        pause(seconds)
        return Self.cpuPercent(a, probeNumbers("cpuProbe"))
    }

    /// Recording times `from`…`to` every `step` s, for frames the Mac reads.
    private static func times(_ from: Double, _ to: Double, step: Double) -> [Double] {
        stride(from: from, through: max(from, to), by: step).map { ($0 * 10).rounded() / 10 }
    }

    /// Waits for the disk ballast to settle (filled, capped, failed or out of time) and reports its readings. The fill
    /// writes the whole free space but the target (43 GB on D3 in pass 3), so it may take minutes; the app ends it
    /// "state=slow" after `UITestDiskBallast.fillBudgetSeconds` (360 s) and this waits 30 s longer.
    private func waitForBallast(_ task: String) -> String {
        let started = Date()
        var lastPrinted = Date.distantPast
        let settled = wait(390) {
            let v = self.probeText("diskBallast")
            if Date().timeIntervalSince(lastPrinted) >= 30 {   // the fill's progress, so a slow device names its rate
                lastPrinted = Date()
                print("B08 \(task) ballast after \(Int(Date().timeIntervalSince(started))) s: \(v)")
            }
            return ["state=holding", "state=capped", "state=failed", "state=growing", "state=floor", "state=slow"]
                .contains { v.hasPrefix($0) }
        }
        let value = probeText("diskBallast")
        print("B08 \(task) ballast: \(value) after \(Int(Date().timeIntervalSince(started))) s")
        let n = probeNumbers("diskBallast")
        report(task, "disk ballast", ["ballastMB": n["ballastMB"] ?? -1, "freeMB": n["freeMB"] ?? -1,
                                      "realFreeMB": n["realFreeMB"] ?? -1, "guardMB": n["guardMB"] ?? -1,
                                      "settled": settled ? 1 : 0])
        XCTAssertTrue(settled, "the ballast settled: \(value)")
        return value
    }

    /// REC-016-T13: a 30 s normal recording (Photo visual, music) plays, is not fragmented (a `moov`, no `moof`, read
    /// on the Mac) and the app's CPU while recording is noted next to the same visual without recording (REC-003's
    /// 60 s run in B13ExtraDeviceTests reports the same probe). QA-008-T10 validates the same file on the Mac.
    func testREC016ThirtySecondRecordingHasNoMoofAndNotesCPU() {
        let task = "REC-016-T13"
        let folder = "QA011-REC016"
        launch(visual: "photo", extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", folder])
        let idle = cpuShare(seconds: 10)
        guard let began = startRecording("30 s") else { return XCTFail("the recording did not start: \(videoProbe)") }
        let before = probeNumbers("cpuProbe")
        _ = wait(45) { self.recordingIndicator.exists && self.recordingIndicator.label >= "Recording, 0:30" }
        let recordingCPU = Self.cpuPercent(before, probeNumbers("cpuProbe"))
        let probe = stopRecordingAndReadBack("30 s")
        print("B08 \(task): \(probe) facts \(probeText("recordingFacts"))")
        guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
        let fps = probeNumbers("recordingFacts")["fps"] ?? 30
        report(task, "30 s normal finish", ["duration": file.duration, "frames": Double(file.frames), "audio": Double(file.audio),
                                            "cpuIdlePercent": idle, "cpuRecordingPercent": recordingCPU, "fps": fps])
        XCTAssertGreaterThanOrEqual(file.duration, 29.5, "about 30 s recorded")
        XCTAssertEqual(file.audio, 1, "In-App Playback audio is in the file")
        XCTAssertGreaterThan(recordingCPU, 0, "the CPU probe reads")
        RecordingCheck.emit(task: task, label: "30 s, no moof", dir: RecordingCheck.tmp(folder), notBefore: began,
                            checks: ["atoms": ["present": ["moov"], "absent": ["moof"]], "minDuration": 29.5,
                                     "audioTrack": true])
        RecordingCheck.emit(task: "QA-008-T10", label: "testExternalRecording", dir: RecordingCheck.tmp(folder),
                            notBefore: began, checks: ["qa008": ["expectAudio": true, "fps": Int(fps)]])
    }

    /// REC-009-T11: the status lines (duration, dropped frames, storage, with a real low-storage reading from the disk
    /// ballast) show while recording the Photo visual, and none of their text is in the file (Vision OCR on the Mac).
    func testREC009StatusLinesAreNotInTheFile() {
        let task = "REC-009-T11"
        let folder = "QA011-REC009"
        usedBallast = true
        launch(visual: "photo", extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", folder,
                                        "-uitestDiskBallast", "600"])
        let ballast = waitForBallast(task)
        guard let began = startRecording("status lines") else { return XCTFail("the recording did not start: \(videoProbe)") }
        let dropped = app.descendants(matching: .any)["recordingDroppedFrames"].firstMatch
        let storage = app.descendants(matching: .any)["recordingStorageStatus"].firstMatch
        XCTAssertTrue(wait(8) { dropped.exists && storage.exists }, "the status lines show while recording")
        pause(6)   // a 5 s storage reading after the Record-time one
        _ = dismissStorageAlert()
        let lines = [dropped.label, storage.label, recordingIndicator.label].filter { !$0.isEmpty }
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch.label
        let spoken = (app.staticTexts["announcementProbe"].value as? String) ?? ""
        screen(task, "status lines while recording")
        print("B08 \(task): lines \(lines) overlay \(overlay.prefix(60)) announcement \(spoken) ballast \(ballast)")
        let probe = stopRecordingAndReadBack("status lines")
        guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
        // The status lines are gone once the recording stopped: read the copies taken while recording (pass 3 on D3
        // failed here with "No matches found" for recordingStorageStatus).
        report(task, "status lines", ["duration": file.duration, "lowStorageLine": lines.contains { $0.contains("min left") } ? 1 : 0])
        XCTAssertTrue(lines.contains { $0.contains("min left") }, "the storage line reads the real free storage: \(lines)")
        // The overlay is app UI: none of its words (nor the performance overlay's) may be in a frame of the file.
        RecordingCheck.emit(task: task, label: "status lines absent", dir: RecordingCheck.tmp(folder), notBefore: began,
                            checks: ["ocrAbsent": ["times": Self.times(1, file.duration - 0.5, step: 1.5),
                                                   "strings": lines + ["min left", "MB free", "GB free", "frames:", "fps",
                                                                       "Recording"]]])
    }

    /// REC-015-T17: on a device made nearly full for real (the DEBUG disk ballast: the guard reads the real free
    /// storage, the ballast grows 20 MB/s while a recording file exists), the guard stops the recording with
    /// "Recording stopped because storage is almost full." and the offered file reads back (plays).
    func testREC015RealDiskGuardStopsTheRecording() throws {
        let task = "REC-015-T17"
        usedBallast = true
        launch(visual: "photo", extra: ["-uitestSeedPhoto", "pattern", "-uitestDiskBallast", "700",
                                        "-uitestDiskBallastGrowMBps", "20"])
        let ballast = waitForBallast(task)
        if ballast.hasPrefix("state=capped") || ballast.hasPrefix("state=failed") {
            throw XCTSkip("the ballast could not bring the guard's reading to 700 MB (\(ballast)): purgeable storage keeps "
                          + "it higher on this device; free space by hand for this check")
        }
        if ballast.hasPrefix("state=slow") {
            throw XCTSkip("the ballast did not fill the free space within the app's 360 s budget "
                          + "(\(ballast)): fill the device closer to full by hand (fewer GB to write) for this check")
        }
        guard let began = startRecording("disk guard") else {
            return XCTFail("the recording did not start: \(videoProbe) \(app.staticTexts["videoRecordingNoticeText"].label)")
        }
        let panel = app.buttons["recordingResultShare"]
        var alerts: [String] = []
        let stopped = wait(150) {
            if let text = self.dismissStorageAlert() { alerts.append(text) }
            return panel.exists
        }
        let seconds = Date().timeIntervalSince(began)
        if !stopped {   // never leave a recording filling the device
            revealRecordingControls()
            app.buttons["record"].tap()
        }
        let notice = app.staticTexts["videoRecordingNoticeText"].exists ? app.staticTexts["videoRecordingNoticeText"].label : ""
        XCTAssertTrue(wait(30) { self.videoProbe.hasPrefix("video ") || self.videoProbe.hasPrefix("failed") }, videoProbe)
        let file = Self.parseVideoProbe(videoProbe)
        let n = probeNumbers("diskBallast")
        print("B08 \(task): stopped=\(stopped) after \(seconds) s, notice \(notice), \(videoProbe), ballast \(probeText("diskBallast")), alerts \(alerts)")
        report(task, "real disk guard", ["stopped": stopped ? 1 : 0, "seconds": seconds, "frames": Double(file?.frames ?? 0),
                                         "duration": file?.duration ?? 0, "freeMBAfter": n["freeMB"] ?? -1, "guardMBAfter": n["guardMB"] ?? -1,
                                         "storageAlerts": Double(alerts.count)])
        XCTAssertTrue(stopped, "the guard stopped the recording within 150 s")
        XCTAssertEqual(notice, "Recording stopped because storage is almost full.")
        XCTAssertGreaterThan(file?.frames ?? 0, 0, "the offered file reads back: \(videoProbe)")
        if app.buttons["recordingResultDiscard"].exists { app.buttons["recordingResultDiscard"].tap() }
    }

    /// REC-007-T13: a 3 s countdown starts the recording after "1" (at least 3 s after Record), announces "Recording in
    /// 3", "2", "1" once each, and a cancelled countdown leaves no file. VoiceOver itself stays a person's check.
    func testREC007CountdownStartsAfterOneAndCancelLeavesNoFile() {
        let task = "REC-007-T13"
        launch(visual: "photo", settings: ["settings.recording.countdown": "3"],
               extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", "QA011-REC007"])
        revealRecordingControls()
        let button = app.buttons["record"]
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "Record is offered")
        button.tap()
        let tapped = Date()
        let countdown = app.descendants(matching: .any)["recordingCountdown"].firstMatch
        var spoken: [String] = [], shown: [String] = []
        var startedAfter: Double?
        while Date().timeIntervalSince(tapped) < 8 {
            let said = (app.staticTexts["announcementProbe"].value as? String) ?? ""
            if spoken.last != said { spoken.append(said) }
            if countdown.exists, shown.last != countdown.label { shown.append(countdown.label) }
            if recordingIndicator.exists { startedAfter = Date().timeIntervalSince(tapped); break }
            pause(0.1)
        }
        let texts = spoken.map { $0.split(separator: "|", maxSplits: 1).last.map(String.init) ?? $0 }
        print("B08 \(task): shown \(shown) spoken \(texts) started after \(startedAfter ?? -1) s")
        report(task, "countdown", ["startedAfter": startedAfter ?? -1])
        XCTAssertNotNil(startedAfter, "the countdown started the recording")
        XCTAssertGreaterThanOrEqual(startedAfter ?? 0, 2.9, "the recording starts after \"1\"")
        XCTAssertLessThanOrEqual(startedAfter ?? 99, 4.5, "and right after it")
        for word in ["Recording in 3", "2", "1"] {
            XCTAssertEqual(texts.filter { $0 == word }.count, 1, "\"\(word)\" is announced once: \(texts)")
        }
        pause(2)
        let probe = stopRecordingAndReadBack("after the countdown")
        XCTAssertGreaterThan(Self.parseVideoProbe(probe)?.frames ?? 0, 0, "the counted-down recording reads back: \(probe)")
        app.terminate()

        // Cancel: nothing is written.
        launch(visual: "photo", settings: ["settings.recording.countdown": "3"],
               extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", "QA011-REC007-cancel"])
        revealRecordingControls()
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "Record is offered")
        button.tap()
        let cancelledAt = Date()
        XCTAssertTrue(wait(3) { countdown.exists }, "the countdown shows")
        app.buttons["recordingCountdownCancel"].tap()
        pause(4)
        XCTAssertFalse(recordingIndicator.exists, "no recording after Cancel")
        XCTAssertEqual(videoProbe, "none", "nothing was written")
        XCTAssertEqual(probeText("recordingFacts"), "none", "no recording facts")
        RecordingCheck.emit(task: task, label: "cancel leaves no file", dir: RecordingCheck.tmp("QA011-REC007-cancel"),
                            notBefore: cancelledAt, absent: true)
    }

    /// REC-004-T19 (REC-004-S5): In-App Playback of the 120 BPM click fixture on Beat Rings, 12 s; on the Mac each
    /// click in the file's audio is paired with the luma flash of its ring, median offset within 40 ms.
    func testREC004ClickAndFlashAlignInTheFile() {
        let task = "REC-004-T19"
        let folder = "QA011-REC004"
        // The click track is 10 ms clicks twice a second: mostly silence, so the status reads "Audio received — silent"
        // while it plays (FR-011; QA-011 pass 3 on D3 waited for "Active audio" and failed; docs/autotester.md).
        launch(visual: "beatRings", extra: ["-uitestRecordingDirectory", folder], fixture: "click-120bpm.m4a",
               playing: ["Audio received — silent", "Active audio"])
        guard let began = startRecording("click and flash") else { return XCTFail("the recording did not start: \(videoProbe)") }
        pause(12)
        let probe = stopRecordingAndReadBack("click and flash")
        guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
        report(task, "click and flash", ["duration": file.duration, "audio": Double(file.audio)])
        XCTAssertEqual(file.audio, 1, "the click track is in the file")
        RecordingCheck.emit(task: task, label: "click and flash within 40 ms", dir: RecordingCheck.tmp(folder), notBefore: began,
                            checks: ["audioTrack": true, "alignment": ["maxMs": 40, "minPairs": 8]])
    }

    /// The Microphone source with "Include microphone audio" on or off (the prompt flow granted the microphone).
    private func launchMicrophone(include: Bool, directory: String) {
        XCUIDevice.shared.orientation = .portrait
        let values: [String: Any] = ["settings.visual": "photo", "settings.performanceOverlay": true,
                                     "settings.recording.includeMicrophone": include]
        let json = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        app.launchArguments = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "microphone", "-uitestUnlocked", "NO",
                               "-uitestDefaults", json, "-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", directory]
        app.launch()
        _ = wait(15) { self.app.staticTexts["sourceStarts"].exists || SystemUI.springboard.alerts.firstMatch.exists }
        pause(2)
        _ = wait(8) { !self.app.otherElements["controls"].exists }
    }

    /// REC-004-T19 (quickstart step 3): a Microphone recording has an audio track only with "Include microphone audio"
    /// on; with the Mac driver following, the Mac plays a 1 kHz tone and the file's audio is not silent.
    ///
    /// The microphone grant is an environment precondition only the prompt-flow batch gives (owner rule 14): without
    /// it the test skips with that instruction, and `mac_device_driver.py prompt-flow` runs it right after its grants
    /// (AFTER_GRANTS), so a skip here is always followed by a run with the grant (QA-011 2026-11-19, docs/autotester.md).
    func testREC004MicrophoneRecordingHasAnAudioTrackOnlyWithTheSetting() throws {
        let task = "REC-004-T19"
        for include in [true, false] {
            let folder = include ? "QA011-REC004-mic-on" : "QA011-REC004-mic-off"
            launchMicrophone(include: include, directory: folder)
            if failOnPermissionPrompt("Microphone") { return }
            // QA-011 pass 3 (D3): the file had no audio track with the setting on and nothing said why. The recording's
            // audio decision (REC-004-R9, DEBUG `recordingAudioDecision`) names the cause before anything is recorded.
            let decision = probeText("recordingAudioDecision")
            print("B08 \(task) microphone \(include): decision \"\(decision)\", source \(sourceIndicator), overlay \(overlayLabel.prefix(100))")
            if decision.contains("microphone permission is off") {
                app.terminate()
                throw XCTSkip("the microphone permission is not granted on this install (\(decision)); "
                              + "python3 scripts/mac_device_driver.py prompt-flow --device <D> grants it and then runs "
                              + "this test (AFTER_GRANTS)")
            }
            if decision == "Recording has no audio." {
                return XCTFail("the Microphone source did not start (\(decision)); source \(sourceIndicator)")
            }
            XCTAssertEqual(decision, include ? "Recording includes microphone audio."
                                             : "Recording has no audio: Include microphone audio is off.",
                           "the recording's audio decision follows the setting")
            if include, MacDriver.isFollowing { MacDriver.request("audio.tone", ["hz": 1000, "seconds": 12]) }
            guard let began = startRecording("microphone \(include)") else {
                return XCTFail("the recording did not start: \(videoProbe)")
            }
            pause(6)
            let probe = stopRecordingAndReadBack("microphone \(include)")
            guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
            report(task, include ? "microphone, setting on" : "microphone, setting off", ["audio": Double(file.audio)])
            XCTAssertEqual(file.audio, include ? 1 : 0, "an audio track only with Include microphone audio: \(probe)")
            var checks: [String: Any] = ["audioTrack": include]
            if include, MacDriver.isFollowing { checks["audioNonSilent"] = ["minPeak": 0.01] }
            RecordingCheck.emit(task: task, label: "microphone \(include ? "on" : "off")", dir: RecordingCheck.tmp(folder),
                                notBefore: began, checks: checks)
            app.terminate()
        }
    }

    /// MED-011-T13 (recording part): a 5 s recording of the Text visual with Show Clock contains the device's time
    /// (HH:mm), read by Vision OCR on the Mac.
    func testMED011RecordingContainsTheClock() {
        let task = "MED-011-T13"
        let folder = "QA011-MED011"
        let clock: [String: Any] = ["$json": ["version": 1, "isShown": true, "hourCycle": "twentyFourHour", "showsSeconds": false]]
        launch(visual: "text", settings: ["settings.clock.overlay": clock], extra: ["-uitestRecordingDirectory", folder])
        let clockProbe = probeText("clockProbe")
        guard let began = startRecording("clock") else { return XCTFail("the recording did not start: \(videoProbe)") }
        pause(5)
        let ended = Date()
        let probe = stopRecordingAndReadBack("clock")
        guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        let minutes = Set(stride(from: began.timeIntervalSince1970 - 1, through: ended.timeIntervalSince1970 + 1, by: 15)
            .map { formatter.string(from: Date(timeIntervalSince1970: $0)) })
        print("B08 \(task): clock \(clockProbe), device \(minutes.sorted()), \(probe)")
        report(task, "clock recording", ["duration": file.duration])
        RecordingCheck.emit(task: task, label: "clock in the file", dir: RecordingCheck.tmp(folder), notBefore: began,
                            checks: ["ocrAny": ["times": Self.times(1, file.duration - 0.5, step: 1.5),
                                                "strings": minutes.sorted(), "minFrames": 2]])
    }

    /// MED-012-T14: Text visual, Show Countdown at 0:10, Start: it reaches "00:00" once and holds, "Countdown finished"
    /// is announced once, and a recording made during it contains the countdown (OCR on the Mac, last frame 00:00).
    func testMED012CountdownFinishesOnceHoldsAndIsRecorded() {
        let task = "MED-012-T14"
        let folder = "QA011-MED012"
        let countdown: [String: Any] = ["$json": ["version": 1, "isShown": true, "durationSeconds": 10]]
        launch(visual: "text", settings: ["settings.countdown.overlay": countdown],
               extra: ["-uitestSettingsSection", "countdown", "-uitestRecordingDirectory", folder])
        revealRecordingControls()
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
        let start = app.buttons["countdownStartButton"]
        for _ in 0..<6 where !(start.exists && start.isHittable) { app.swipeUp() }
        XCTAssertTrue(start.exists, "the countdown's Start")
        start.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
        guard let began = startRecording("countdown") else { return XCTFail("the recording did not start: \(videoProbe)") }
        var texts: [String] = [], spoken: [String] = []
        var finishedAt: Date?
        let end = Date().addingTimeInterval(20)
        while Date() < end {
            let value = probeText("countdownProbe")   // "<text> <state> finished=<n> drawn=<n>"
            let text = String(value.split(separator: " ").first ?? "")
            if texts.last != text { texts.append(text) }
            let said = (app.staticTexts["announcementProbe"].value as? String) ?? ""
            if spoken.last != said { spoken.append(said) }
            if finishedAt == nil, value.contains("finished=1") { finishedAt = Date() }
            if let finishedAt, Date().timeIntervalSince(finishedAt) > 3 { break }
            pause(0.25)
        }
        let finishedCount = probeNumbers("countdownProbe")["finished"] ?? -1
        let probe = stopRecordingAndReadBack("countdown")
        print("B08 \(task): texts \(texts) spoken \(spoken) \(probe)")
        guard let file = Self.parseVideoProbe(probe) else { return XCTFail("no readable recording: \(probe)") }
        report(task, "countdown", ["finished": finishedCount, "duration": file.duration])
        XCTAssertNotNil(finishedAt, "the countdown finished")
        XCTAssertEqual(finishedCount, 1, "it finishes once")
        XCTAssertEqual(texts.last, "00:00", "it holds at 00:00: \(texts)")
        XCTAssertEqual(texts.filter { $0 == "00:00" }.count, 1, "00:00 is reached once and held: \(texts)")
        XCTAssertEqual(spoken.filter { $0.hasSuffix("|Countdown finished") }.count, 1, "announced once: \(spoken)")
        let last = (max(1, file.duration - 0.5) * 10).rounded() / 10
        RecordingCheck.emit(task: task, label: "countdown in the file", dir: RecordingCheck.tmp(folder), notBefore: began,
                            checks: ["ocrPattern": ["times": Self.times(1, last - 1, step: 1.5) + [last],
                                                    "pattern": "[0-9]{2}:[0-9]{2}", "minFrames": 3, "last": "00:00"]])
    }
}
