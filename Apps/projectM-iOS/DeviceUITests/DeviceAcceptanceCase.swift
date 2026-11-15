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

    /// D1's QA-010 floor (thresholds.json version 2: fps1sP5 ≥ 55 on D1 and D2).
    static let minimumFPS: Double = 55
    /// "Unchanged within noise" for an effect: at most this many fps below the same visual without it.
    static let effectToleranceFPS: Double = 3

    override func setUp() async throws {
        continueAfterFailure = true
        #if targetEnvironment(simulator)
        throw XCTSkip("device acceptance runs on D1/D2 only (simulator results are never evidence)")
        #endif
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
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
    func launch(visual: String, settings: [String: Any] = [:], extra: [String] = [],
                orientation: UIDeviceOrientation = .portrait, music: Bool = true) {
        XCUIDevice.shared.orientation = orientation
        var args: [String] = ["-uitestDiagnostics", "-autostart", "inAppPlayback", "-uitestUnlocked", "NO",
                              "-settings.visual", visual, "-settings.performanceOverlay", "<true/>"]
        if music { args += ["-uitestImportAudio", "music-fixture.m4a", "-uitestPlayImported", "YES"] }
        for (key, value) in settings.sorted(by: { $0.key < $1.key }) {
            args += ["-\(key)", Self.plist(value)]
        }
        app.launchArguments = args + extra
        app.launch()
        XCTAssertTrue(wait(15) { self.app.staticTexts["sourceStarts"].exists }, "the source started")
        XCTAssertTrue(wait(10) { self.overlayFPS() != nil }, "the performance overlay shows a frame rate")
        if music {
            let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
            XCTAssertTrue(wait(12) { overlay.label.contains("Active audio") }, "music is playing: \(overlay.label.prefix(120))")
        }
        pause(2)   // the visual's first frames and the music settle
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

    /// Samples the frame rate and checks the median against the floor; returns the median.
    @discardableResult
    func assertFrameRate(_ task: String, _ label: String, seconds: Int = 10, minimum: Double = minimumFPS) -> Double {
        let samples = sampleFPS(seconds: seconds)
        let median = Self.median(samples)
        report(task, label, ["fpsMedian": median, "fpsMin": samples.min() ?? 0, "samples": Double(samples.count)])
        XCTAssertGreaterThanOrEqual(samples.count, seconds / 2, "\(task) \(label): the overlay was readable")
        XCTAssertGreaterThanOrEqual(median, minimum, "\(task) \(label): median \(median) fps")
        return median
    }

    // MARK: Screenshots

    /// Takes a screenshot, attaches it, and returns its statistics (sampled every 8th pixel).
    @discardableResult
    func screen(_ task: String, _ label: String) -> (ScreenStats, [UInt8]) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(task) \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let pixels = Self.rgba(shot.image, step: 8)
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

    /// The visual is drawing: non-black content, and it moves between two screenshots 1 s apart.
    func assertDrawingAndMoving(_ task: String, _ label: String, minimumChange: Double = 0.002) {
        let (first, a) = screen(task, "\(label) a")
        pause(1)
        let (_, b) = screen(task, "\(label) b")
        let motion = Self.change(a, b)
        report(task, label, ["motion": motion])
        XCTAssertGreaterThan(first.nonBlack, 0.02, "\(task) \(label): the visual draws")
        XCTAssertGreaterThan(motion, minimumChange, "\(task) \(label): the visual moves with the music")
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
        for (k, v) in values { body[k] = (v * 1000).rounded() / 1000 }
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
