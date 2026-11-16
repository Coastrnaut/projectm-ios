// B08RecordingDeviceTests.swift — QA-011 owner session B08 ("Recording"), the parts that need a real recording read
// back, automated on the device. Each test records the Photo visual (a recordable visual; projectM is not, REC-003-R12)
// with the reference track and reads the offered file back through the DEBUG `videoRecordingProbe`
// ("video <codec> <w>x<h> frames=<n> duration=<s> audio=<n>", RecordedVideoInspector).
// REC-014-T15: Square (D1) and Portrait (D2) for 5 s read back at the planned shape. REC-005-T14: each quality
// profile records and reads back (a profile the device cannot offer is reported as refused, not as a failure).
import UIKit
import XCTest

@MainActor
final class B08RecordingDeviceTests: DeviceAcceptanceCase {
    private var probe: String { (app.staticTexts["videoRecordingProbe"].value as? String) ?? "" }

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
    private func record(_ task: String, _ label: String, settings: [String: Any], seconds: Int)
        -> (codec: String, width: Int, height: Int, frames: Int, duration: Double)? {
        launch(visual: "photo", settings: settings,
               extra: ["-uitestSeedPhoto", "pattern", "-uitestRecordingDirectory", "B08RecordingDeviceTests"])
        showControls()
        let button = app.buttons["record"]
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "\(label): Record is offered (\(button.label))")
        button.tap()
        let indicator = app.descendants(matching: .any)["recordingIndicator"].firstMatch
        XCTAssertTrue(wait(5) { indicator.exists }, "\(label): the recording indicator")
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
        guard let file = record(task, kind, settings: ["settings.recording.aspect": kind], seconds: 5) else {
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
        report(task, "slots", ["written": Double(f.frames), "dropped": Double(f.dropped), "fps": Double(f.fps)])
        XCTAssertEqual(f.fps, 30, "recorded at 30 fps")
        XCTAssertEqual(frames, f.frames, "the file holds the written frames")
        XCTAssertEqual(f.frames + f.dropped, 300, accuracy: 1, "300 slots at 30 fps: written \(f.frames) + dropped \(f.dropped)")
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
        XCTAssertEqual(Double(f.frames + f.dropped), slots, accuracy: 1.5,
                       "written \(f.frames) + dropped \(f.dropped) fill \(file.duration) s at 24 fps")
        XCTAssertLessThanOrEqual(Double(f.dropped), slots * Self.maximumDroppedShare, "dropped slots stay bounded")
    }
}
