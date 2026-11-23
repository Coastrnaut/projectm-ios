// DeviceAcceptanceCase.swift — QA-011 device acceptance: the owner sessions' steps, automated on D1/D2.
//
// Each test launches the signed app on the device with its settings as launch arguments (the UserDefaults argument
// domain; typed values in plist form), starts In-App Playback with the bundled music (`-autostart inAppPlayback`),
// and measures instead of looking:
// * the frame rate from the performance overlay ("NN fps"), sampled once a second;
// * screenshots: mean luminance, the share of non-black pixels, mean saturation, and the mean change between two
//   screenshots (motion). Screenshots are attached to the result bundle for review.
// Every measurement is printed as one `DEVICE-ACCEPT {json}` line for the matrix runner and the test report.
// Runs only on a physical device (simulator results are never evidence, Constitution X).
import UIKit
import XCTest

struct ScreenStats: Codable {
    var meanLuma: Double
    var nonBlack: Double
    var meanSaturation: Double
}

@MainActor
class DeviceAcceptanceCase: XCTestCase {
    let app = XCUIApplication()
    /// The sampled size (width, height) of the last screenshot.
    var lastSize: (Int, Int) = (0, 0)
    /// The last screenshot `screen` took (for `uprightPixels`).
    var lastShot: XCUIScreenshot?
    /// Screenshot sampling: every `sampleStep`-th pixel (8 by default; 2 for thin features such as scanlines).
    var sampleStep: Int = 8

    /// D1's QA-010 floor (thresholds.json version 2: fps1sP5 ≥ 55 on D1 and D2).
    static let minimumFPS: Double = 55
    /// "Unchanged within noise" for an effect: at most this many fps below the same visual without it.
    static let effectToleranceFPS: Double = 3

    override func setUp() async throws {
        continueAfterFailure = true
        #if targetEnvironment(simulator)
        // A rehearsal (`xcodebuild … TEST_RUNNER_SIMULATOR_REHEARSAL=1`) runs the steps on a simulator to debug a test
        // before a device run; its results are never evidence (QA-011 device run 2026-11-21, B10).
        if ProcessInfo.processInfo.environment["SIMULATOR_REHEARSAL"] != "1" {
            throw XCTSkip("device acceptance runs on D1/D2 only (simulator results are never evidence)")
        }
        #endif
    }

    override func tearDown() async throws {
        dismissLeftoverFilesSheet()
        XCUIDevice.shared.orientation = .portrait
    }

    /// Cancels a Files picker or mover a failed (or falsely passed) step left up. QA-011 D2 r10 (iPadOS 27.2.1,
    /// 2026-11-23): PRE-014's Save to Files mover stayed up after the test ended, and the next test's launch then
    /// failed after 60 s with "Failed to terminate org.projectmios.ProjectMiOS" (MED-001), which also restarted the
    /// runner. Only while the app is in front, so a test that ended elsewhere is not relaunched.
    func dismissLeftoverFilesSheet() {
        guard app.state == .runningForeground else { return }
        let action = app.buttons["DOCPicker.actionButton"].firstMatch
        guard action.exists || app.collectionViews["File View"].exists else { return }
        print("DEVICE-ACCEPT-NOTE teardown: a Files sheet is still up; cancelling it")
        SystemUI(app: app).cancelFilesPicker()
        _ = wait(3) { !action.exists }
    }

    // MARK: Launch

    static func plist(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "<true/>" : "<false/>"
        case let i as Int: return "<integer>\(i)</integer>"
        case let d as Double: return "<real>\(d)</real>"
        case let s as String: return s
        default: return "\(value)"
        }
    }

    /// Launches with `visual` and `settings` (UserDefaults keys → values), overlay on, music playing.
    /// `music`: the generated music fixture (scripts/make_music_fixture.py, copied into the app's Documents by the
    /// runner) plays instead of the reference track, which is a test signal with a silent gap.
    /// `playing`: the overlay's audio states that count as "the fixture plays". A click or pulse fixture (10 ms clicks
    /// twice a second) is mostly silence, so it reads "Audio received — silent" by design (FR-011: Active audio needs
    /// −50 dBFS held for 250 ms; ReferenceToneCatalog's pulse fixtures say the same).
    func launch(visual: String, settings: [String: Any] = [:], extra: [String] = [],
                orientation: UIDeviceOrientation = .portrait, music: Bool = true, fixture: String = "music-fixture.m4a",
                playing: [String] = ["Active audio"]) {
        coolDownIfHot()
        XCUIDevice.shared.orientation = orientation
        // `-uitestResetNotice` clears the app's settings, media and committed scene first: otherwise launch restores
        // the last committed scene (SCN-002) and its effect values replace the test's settings.
        var args: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO"]
        if music { args += ["-uitestImportAudio", fixture, "-uitestPlayImported", "YES"] }
        // Typed values through `-uitestDefaults` (plain launch arguments arrive as strings, which settings that
        // read NSNumber ignore).
        var values: [String: Any] = ["settings.performanceOverlay": true]   // on unless the test's settings say otherwise
        values.merge(settings) { (_: Any, given: Any) -> Any in given }
        values["settings.visual"] = visual
        let json = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        args += ["-uitestDefaults", json]
        app.launchArguments = args + extra
        app.launch()
        settleOrientation(orientation)
        let started = wait(15) { self.app.staticTexts["sourceStarts"].exists }
        if !started, music, app.navigationBars["Choose source"].exists {
            XCTFail("the app stayed on Choose source: music-fixture.m4a is missing from the app's Documents on this "
                    + "device; run python3 scripts/install_test_fixtures.py --device all")
        }
        XCTAssertTrue(started, "the source started")
        if (values["settings.performanceOverlay"] as? Bool) ?? true {
            XCTAssertTrue(wait(10) { self.overlayFPS() != nil }, "the performance overlay shows a frame rate")
        }
        if music, (values["settings.performanceOverlay"] as? Bool) ?? true {
            let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
            XCTAssertTrue(wait(12) { playing.contains { overlay.label.contains($0) } },
                          "\(fixture) is playing (\(playing.joined(separator: " or "))): \(overlay.label.prefix(120))")
        }
        pause(2)   // the visual's first frames and the music settle
        // The controls show after launch and hide after 5 s without interaction; screenshots need them hidden.
        _ = wait(8) { !self.app.otherElements["controls"].exists }
    }

    /// Holds the interface in `orientation` after a launch. The orientation set before `app.launch()` does not always
    /// survive it: on D2 (full run 12, 2026-11-20) the first launch after the install took 9 s, the iPad's own sensor
    /// reported Landscape Right and then Face Up meanwhile, and the interface came up in landscape although the test set
    /// Portrait. A screenshot's pixels stay in the device's portrait frame (2064 × 2752 with a 1376 pt wide window), so
    /// every point-based sample was read from the wrong place (SHD-005-T13: "the palette strip was not found").
    /// When the window's shape does not match, the orientation is set again (through the other one, so the set is a
    /// real change) until it does. Face-up and unknown requests are left alone.
    func settleOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isPortrait || orientation.isLandscape else { return }
        let window = app.windows.firstMatch
        func matches() -> Bool {
            let f = window.frame
            guard f.width > 0, f.height > 0 else { return false }
            return orientation.isPortrait ? f.height > f.width : f.width > f.height
        }
        for _ in 0..<3 {
            if wait(2, matches) { return }
            XCUIDevice.shared.orientation = orientation.isPortrait ? .landscapeLeft : .portrait
            pause(0.5)
            XCUIDevice.shared.orientation = orientation
        }
        XCTAssertTrue(wait(2, matches), "the interface turned to \(orientation.isPortrait ? "portrait" : "landscape") "
                      + "(window \(window.frame.size))")
    }

    // MARK: Waiting

    func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func wait(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            pause(0.2)
        }
        return condition()
    }

    /// The label and value (as text) of each element in `ids` present in one snapshot of the app (every window). For
    /// elements that come and go within a poll: a query on the element itself retries for about 2 s once it is gone
    /// (REC-007, D1 2026-11-23), the app's own snapshot answers at once. Missing elements are absent from the result.
    static func windowValues(_ app: XCUIApplication, _ ids: Set<String>) -> [String: (label: String, value: String)] {
        guard let root = try? app.snapshot() else { return [:] }
        var out: [String: (label: String, value: String)] = [:]
        var pending: [any XCUIElementSnapshot] = [root]
        while let node = pending.popLast() {
            if ids.contains(node.identifier), out[node.identifier] == nil {
                let value: String
                switch node.value {
                case let text as String: value = text
                case let number as NSNumber: value = number.stringValue
                default: value = ""
                }
                out[node.identifier] = (node.label, value)
            }
            pending.append(contentsOf: node.children)
        }
        return out
    }

    // MARK: Notification banners

    /// Swipes away a notification banner that covers the top of the screen. MED-005-T20 on D1 (2026-11-23): a Messages
    /// banner sat over Settings' Done button ({8, 56, 377, 66}); XCUITest saw the interruption but could not handle it
    /// ("Failed to construct element query matching interruption"), the tap opened Messages and the app stayed in the
    /// background for the rest of the test (reverse cache "preparing", state runningBackground).
    func dismissNotificationBanner() {
        let banner = SystemUI.springboard.descendants(matching: .any)["NotificationShortLookView"].firstMatch
        for _ in 0..<3 where banner.exists {
            print("DEVICE-ACCEPT notification banner over the app: swiped away")
            banner.swipeUp()
            _ = wait(2) { !banner.exists }
        }
    }

    /// Brings the app back if something (a banner tap, a system sheet) sent it to the background. True when it was
    /// in front already.
    @discardableResult
    func returnToAppIfLeft(_ step: String) -> Bool {
        guard app.state != .runningForeground, app.state != .notRunning else { return true }
        print("DEVICE-ACCEPT \(step): the app had left the front (state \(app.state.rawValue)); activated again")
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 10)
        return false
    }

    /// The app's Settings is already open at its root: opening it again must not tap the controls' Settings button.
    /// MED-001-T24 on D1 (2026-11-23): the second pick opened Settings while it was still open after the first; on an
    /// iPhone the sheet covers the controls, the button was not hittable (hit point -1, -1) and XCUITest tapped its
    /// visible frame, on a Settings row behind it, which presented a sheet over Settings. The Settings list shrank to the
    /// stacked-sheet card ({16, 59, 361, 728}, its rows scaled to 0.92) and Choose from Files… was never reachable
    /// again. On an iPad the panel leaves the button uncovered, which is why D2 and D3 passed.
    func settingsAlreadyOpen() -> Bool {
        app.navigationBars["Settings"].exists
    }

    /// Closes the app's Settings sheet with Done, clear of notification banners (Done sits under the banner's place on
    /// an iPhone), and makes sure the app is still in front afterwards.
    func tapSettingsDone() {
        dismissNotificationBanner()
        let done = app.navigationBars["Settings"].buttons["Done"]
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
        returnToAppIfLeft("Settings › Done")
    }

    // MARK: Frame rate

    func overlayFPS() -> Double? {
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        guard overlay.exists else { return nil }
        let label: String = overlay.label
        guard let range = label.range(of: #"([0-9]+(\.[0-9]+)?) fps"#, options: .regularExpression) else { return nil }
        return Double(label[range].replacingOccurrences(of: " fps", with: ""))
    }

    /// One overlay reading per second.
    func sampleFPS(seconds: Int = 10) -> [Double] {
        var samples: [Double] = []
        for _ in 0..<seconds {
            pause(1)
            if let fps = overlayFPS() { samples.append(fps) }
        }
        return samples
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// The device is hot or in Low Power Mode: the app caps itself at 30 fps by design (FR-049, QualityGovernor), so
    /// a 55 fps floor would measure the room, not the app. The test runner's `ProcessInfo` is the device's.
    static var deviceIsCapped: Bool {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    /// FR-049's floor: capped, the visual never drops below 30 fps (a reading of 29.x is the overlay's rounding).
    static let cappedMinimumFPS: Double = 28

    /// Before a launch: a device at serious/critical thermal state cools at the Home Screen (the app not running) for
    /// up to 5 minutes, so frame-rate floors measure the app (D1 2026-11-23: after an hour of camera tests every fps
    /// check read exactly 30 at thermal 2, the FR-049 cap).
    func coolDownIfHot(maxSeconds: Double = 300) {
        guard ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue else { return }
        let start = Date()
        print("DEVICE-ACCEPT cool-down: thermal \(ProcessInfo.processInfo.thermalState.rawValue)")
        if app.state != .notRunning { app.terminate() }
        XCUIDevice.shared.press(.home)
        while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue,
              Date().timeIntervalSince(start) < maxSeconds {
            pause(10)
        }
        print("DEVICE-ACCEPT cool-down: thermal \(ProcessInfo.processInfo.thermalState.rawValue) after \(Int(Date().timeIntervalSince(start))) s")
    }

    /// Samples the frame rate and checks the median against the floor; returns the median. When the device is capped
    /// (FR-049) while sampling, the floor is FR-049's 30 fps instead of `minimum`, and the report says so.
    @discardableResult
    func assertFrameRate(_ task: String, _ label: String, seconds: Int = 10, minimum: Double = minimumFPS) -> Double {
        let samples = sampleFPS(seconds: seconds)
        let median = Self.median(samples)
        let capped = Self.deviceIsCapped && minimum > Self.cappedMinimumFPS
        report(task, label, ["fpsMedian": median, "fpsMin": samples.min() ?? 0, "samples": Double(samples.count),
                             "thermal": Double(ProcessInfo.processInfo.thermalState.rawValue), "capped": capped ? 1 : 0])
        XCTAssertGreaterThanOrEqual(samples.count, seconds / 2, "\(task) \(label): the overlay was readable")
        let floor = capped ? Self.cappedMinimumFPS : minimum
        XCTAssertGreaterThanOrEqual(median, floor, "\(task) \(label): median \(median) fps\(capped ? " (FR-049 cap: thermal/Low Power)" : "")")
        return median
    }

    // MARK: Screenshots

    /// Takes a screenshot, attaches it, and returns its statistics (sampled every 8th pixel).
    @discardableResult
    func screen(_ task: String, _ label: String) -> (ScreenStats, [UInt8]) {
        let shot = XCUIScreen.main.screenshot()
        lastShot = shot
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(task) \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let pixels = Self.rgba(shot.image, step: sampleStep)
        lastSize = ((shot.image.cgImage?.width ?? 0) / sampleStep, (shot.image.cgImage?.height ?? 0) / sampleStep)
        let stats = Self.stats(pixels)
        report(task, label, ["meanLuma": stats.meanLuma, "nonBlack": stats.nonBlack, "meanSaturation": stats.meanSaturation])
        return (stats, pixels)
    }

    /// Mean absolute change per channel (0…1) between two sampled screenshots: motion.
    static func change(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0
        for i in 0..<a.count where i % 4 != 3 { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count / 4 * 3) / 255
    }

    /// A part of the picture away from the performance overlay (top leading, its counters change every second),
    /// the visual's centred spectrum, the status pill and the eye button: where a still photo must stay still.
    var stillRegion: (Double, Double, Double, Double) {
        lastSize.0 > lastSize.1 ? (0.78, 0.12, 0.18, 0.25) : (0.04, 0.72, 0.25, 0.10)
    }

    /// Mean change between two sampled screenshots inside `stillRegion`.
    func stillChange(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let (w, h) = lastSize
        guard w > 0, h > 0 else { return Self.change(a, b) }
        let r = stillRegion
        func crop(_ p: [UInt8]) -> [UInt8] {
            var out: [UInt8] = []
            let x0 = Int(r.0 * Double(w)), y0 = Int(r.1 * Double(h))
            let x1 = min(w, x0 + Int(r.2 * Double(w))), y1 = min(h, y0 + Int(r.3 * Double(h)))
            for y in y0..<y1 { for x in x0..<x1 { let i = (y * w + x) * 4; if i + 4 <= p.count { out += p[i..<(i + 4)] } } }
            return out
        }
        return Self.change(crop(a), crop(b))
    }

    /// Statistics of `stillRegion` (the photo alone).
    func stillStats(_ p: [UInt8]) -> ScreenStats {
        Self.region(p, width: lastSize.0, height: lastSize.1, stillRegion)
    }

    /// The visual is drawing: non-black content, and it moves between two screenshots 1 s apart.
    /// `minimumDraw`: the non-black share that counts as drawing; a line visual (the oscilloscope) covers about 1 %.
    func assertDrawingAndMoving(_ task: String, _ label: String, minimumChange: Double = 0.002, minimumDraw: Double = 0.02) {
        let (first, a) = screen(task, "\(label) a")
        pause(1)
        let (_, b) = screen(task, "\(label) b")
        let motion = Self.change(a, b)
        report(task, label, ["motion": motion])
        XCTAssertGreaterThan(first.nonBlack, minimumDraw, "\(task) \(label): the visual draws")
        XCTAssertGreaterThan(motion, minimumChange, "\(task) \(label): the visual moves with the music")
    }

    /// Motion over several pairs (autotester lesson "Motion checks need several samples"): `pairs` screenshot pairs 1 s
    /// apart, `gap` seconds between pairs, asserted on the largest change, so one quiet passage of the music does not
    /// fail a moving visual. Returns the changes.
    @discardableResult
    func assertMovingSampled(_ task: String, _ label: String, pairs: Int = 3, gap: Double = 3,
                             minimumChange: Double = 0.002) -> [Double] {
        var motions: [Double] = []
        for i in 0..<pairs {
            let (_, a) = screen(task, "\(label) \(i) a")
            pause(1)
            let (_, b) = screen(task, "\(label) \(i) b")
            motions.append(Self.change(a, b))
            if i < pairs - 1 { pause(gap) }
        }
        report(task, "\(label) motion", ["max": motions.max() ?? 0, "min": motions.min() ?? 0])
        XCTAssertGreaterThan(motions.max() ?? 0, minimumChange, "\(task) \(label): the visual moves with the music \(motions)")
        return motions
    }

    static func rgba(_ image: UIImage, step: Int) -> [UInt8] {
        guard let cg = image.cgImage else { return [] }
        let width = cg.width / step, height = cg.height / step
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    /// The screenshot's pixels the way the screen shows them (every `step`-th pixel) and their sampled size.
    /// `rgba` reads `cgImage` as stored; a `UIImage` may carry a rotation in `imageOrientation` that `cgImage` does not
    /// apply, and then fraction rectangles meant for the landscape screen land elsewhere. Drawing the `UIImage` applies
    /// its orientation, so the rectangle means the screen as shown either way (CAM-007-T15 reports both sizes).
    static func uprightPixels(_ image: UIImage, step: Int) -> ([UInt8], (Int, Int)) {
        let width = max(Int(image.size.width * image.scale) / step, 1), height = max(Int(image.size.height * image.scale) / step, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (rgba(drawn, step: 1), (width, height))
    }

    static func stats(_ p: [UInt8]) -> ScreenStats {
        let n = p.count / 4
        guard n > 0 else { return ScreenStats(meanLuma: 0, nonBlack: 0, meanSaturation: 0) }
        var luma = 0.0, nonBlack = 0, saturation = 0.0
        for i in 0..<n {
            let r = Double(p[i * 4]) / 255, g = Double(p[i * 4 + 1]) / 255, b = Double(p[i * 4 + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            luma += y
            if y > 0.05 { nonBlack += 1 }
            let mx = max(r, g, b), mn = min(r, g, b)
            saturation += mx > 0 ? (mx - mn) / mx : 0
        }
        return ScreenStats(meanLuma: luma / Double(n), nonBlack: Double(nonBlack) / Double(n),
                           meanSaturation: saturation / Double(n))
    }

    /// Region statistics: a fraction rectangle (x, y, w, h in 0…1) of a sampled screenshot.
    static func region(_ p: [UInt8], width: Int, height: Int, _ r: (Double, Double, Double, Double)) -> ScreenStats {
        var sub: [UInt8] = []
        let x0 = Int(r.0 * Double(width)), y0 = Int(r.1 * Double(height))
        let x1 = min(width, x0 + Int(r.2 * Double(width))), y1 = min(height, y0 + Int(r.3 * Double(height)))
        for y in y0..<y1 { for x in x0..<x1 { let i = (y * width + x) * 4; sub += p[i..<(i + 4)] } }
        return stats(sub)
    }

    // MARK: Report

    func report(_ task: String, _ label: String, _ values: [String: Double]) {
        var body: [String: Any] = ["task": task, "step": label, "device": deviceModel()]
        // JSONSerialization raises an Objective-C exception (not a Swift error) on NaN or infinity, which ends the whole
        // test run (FILE-009-T12 on D3, 2026-11-19: a ratio over a -1 + 1 total). Non-finite values are written as null.
        for (k, v) in values { body[k] = v.isFinite ? (v * 1000).rounded() / 1000 : NSNull() }
        if let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("DEVICE-ACCEPT \(line)")
        }
    }

    func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { (raw: UnsafeRawBufferPointer) -> String in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
