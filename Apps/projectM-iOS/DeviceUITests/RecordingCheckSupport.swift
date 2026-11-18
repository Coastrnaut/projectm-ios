// RecordingCheckSupport.swift — QA-011 Batch 6: what the recording and share device tests share.
//
// * `RecordingCheck.emit(...)` prints one `RECORDING-CHECK {json}` line per file a test leaves in the app's container
//   (a `-uitestRecordingDirectory` folder under tmp/, Documents for Files saves, the Recordings library). After the run
//   `python3 scripts/recording_frame_check.py run --log <log> --device D1` pulls each file (devicectl) and checks what
//   is in it (atoms, codec, OCR, centre, A/V alignment, QA-008's validator). The test itself never waits on the Mac.
// * `RecordingCheck.stamp(_:)`: the "2026-11-18 at 14.05.32" the app puts in its file names (en_US_POSIX, the device's
//   time zone), so the Mac picks this run's file and not an older one.
// * `centreGrid`: block-mean luma of a screenshot's centre crop (REC-014's centre check, compared on the Mac).
// * Recording helpers on DeviceAcceptanceCase (controls, probes, Record and Stop) for both B08 classes.
import UIKit
import XCTest

enum RecordingCheck {
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// One file for the Mac to pull and check. `dir` is relative to the app's container ("tmp/<name>", "Documents").
    static func emit(task: String, label: String, dir: String, prefix: String = "Visualizer Recording",
                     suffix: String = ".mp4", notBefore: Date? = nil, name: String? = nil, absent: Bool = false,
                     checks: [String: Any] = [:]) {
        var body: [String: Any] = ["task": task, "label": label, "dir": dir, "prefix": prefix, "suffix": suffix,
                                   "checks": checks]
        if let notBefore { body["notBefore"] = stamp(notBefore.addingTimeInterval(-2)) }
        if let name { body["name"] = name }
        if absent { body["absent"] = true }
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        print("RECORDING-CHECK \(String(decoding: data, as: UTF8.self))")
    }

    /// The `-uitestRecordingDirectory <name>` folder as the Mac addresses it.
    static func tmp(_ name: String) -> String { "tmp/\(name)" }

    /// Block-mean luma (0…255) of the centre crop of `image` with the aspect `width`:`height`, `cols` × `rows` blocks,
    /// row-major from the top (the same layout recording_inspect's `grid` returns for a frame).
    static func centreGrid(_ image: UIImage, width: Int, height: Int, cols: Int, rows: Int) -> [Int] {
        guard let cg = image.cgImage, width > 0, height > 0 else { return [] }
        let w = Double(cg.width), h = Double(cg.height)
        var crop = CGRect(x: 0, y: 0, width: w, height: h)
        if w / h > Double(width) / Double(height) {
            crop.size.width = h * Double(width) / Double(height)
            crop.origin.x = (w - crop.width) / 2
        } else {
            crop.size.height = w * Double(height) / Double(width)
            crop.origin.y = (h - crop.height) / 2
        }
        guard let part = cg.cropping(to: crop.integral) else { return [] }
        var data = [UInt8](repeating: 0, count: cols * rows)
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: buffer.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: cols, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(part, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        }
        return data.map(Int.init)
    }
}

extension DeviceAcceptanceCase {
    var videoProbe: String { (app.staticTexts["videoRecordingProbe"].value as? String) ?? "" }

    /// "key=value" pairs of a probe's value (non-numbers dropped).
    func probeNumbers(_ identifier: String) -> [String: Double] {
        let text = (app.descendants(matching: .any)[identifier].firstMatch.value as? String) ?? ""
        var values: [String: Double] = [:]
        for part in text.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2, let v = Double(kv[1]) { values[String(kv[0])] = v }
        }
        return values
    }

    func probeText(_ identifier: String) -> String {
        (app.descendants(matching: .any)[identifier].firstMatch.value as? String) ?? ""
    }

    func revealRecordingControls() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if controls.exists { area.tap() }
        area.tap()
        if !wait(2, { controls.exists }) { area.tap() }
        XCTAssertTrue(wait(5) { controls.exists }, "the controls are shown")
    }

    var recordingIndicator: XCUIElement { app.descendants(matching: .any)["recordingIndicator"].firstMatch }

    /// Taps Record (the controls first); returns when the indicator shows (nil when it never did).
    @discardableResult
    func startRecording(_ label: String) -> Date? {
        revealRecordingControls()
        let button = app.buttons["record"]
        XCTAssertTrue(wait(5) { button.exists && button.label == "Record" }, "\(label): Record is offered (\(button.label))")
        button.tap()
        let tapped = Date()
        return wait(8, { self.recordingIndicator.exists }) ? tapped : nil
    }

    /// Taps Stop recording and waits for the read-back (`-uitestRecordingDirectory` or `-uitestStorage`/ballast runs).
    func stopRecordingAndReadBack(_ label: String) -> String {
        revealRecordingControls()
        app.buttons["record"].tap()
        XCTAssertTrue(wait(30) { self.videoProbe.hasPrefix("video ") || self.videoProbe.hasPrefix("failed") },
                      "\(label): the file is read back: \(videoProbe)")
        return videoProbe
    }

    /// The parsed "video <codec> WxH frames= duration= audio= offGrid=" probe.
    static func parseVideoProbe(_ probe: String) -> (codec: String, width: Int, height: Int, frames: Int, duration: Double,
                                                     audio: Int)? {
        let parts = probe.split(separator: " ").map(String.init)
        guard parts.count >= 6, parts[0] == "video" else { return nil }
        let size = parts[2].split(separator: "x").compactMap { Int($0) }
        func value(_ key: String) -> String? { parts.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } }
        guard size.count == 2 else { return nil }
        return (parts[1], size[0], size[1], Int(value("frames") ?? "") ?? 0, Double(value("duration") ?? "") ?? 0,
                Int(value("audio") ?? "") ?? -1)
    }

    /// A springboard alert about storage (iOS's "Storage Almost Full" while a ballast fills the disk): dismissed, its
    /// text returned. Never a permission prompt (those belong to the prompt flow, owner rule 14).
    func dismissStorageAlert() -> String? {
        let alert = SystemUI.springboard.alerts.firstMatch
        guard alert.exists, alert.label.localizedCaseInsensitiveContains("storage") else { return nil }
        let text = alert.label
        for name in ["OK", "Close", "Not Now", "Dismiss"] where alert.buttons[name].exists {
            alert.buttons[name].tap()
            break
        }
        return text
    }

    /// A permission prompt on screen means the prompt flow was not run on this device (owner rule 14): the test stops
    /// and leaves the prompt for that flow.
    func failOnPermissionPrompt(_ what: String) -> Bool {
        let alert = SystemUI.springboard.alerts.firstMatch
        guard alert.exists, !alert.label.localizedCaseInsensitiveContains("storage") else { return false }
        XCTFail("\(what): a system prompt appeared (\(alert.label)); run the prompt flow first "
                + "(python3 scripts/mac_device_driver.py prompt-flow --device <D>), never answered here")
        return true
    }
}
