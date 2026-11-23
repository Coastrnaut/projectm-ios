// B07DeviceSupport.swift — QA-011 Batch 7 (visuals, shows and accessibility): shared helpers for the B01, B02, B04 and
// B12 device tests that use the DEBUG probes of Apps/projectM-iOS/Debug/UITestVisualProbes.swift
// (`-uitestVisualProbes`). Methods live on a base class (no XCUIElement extensions), so they cannot collide with other
// files in this bundle. Waits poll; tests stay short (owner rule 7) and never wait on a person.
import UIKit
import XCTest

@MainActor
class B07DeviceCase: DeviceAcceptanceCase {
    static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    // MARK: Launch

    /// `launch(visual:…)` with the B07 probes on.
    func launchProbed(visual: String, settings: [String: Any] = [:], extra: [String] = [],
                      orientation: UIDeviceOrientation = .portrait, music: Bool = true) {
        launch(visual: visual, settings: settings, extra: ["-uitestVisualProbes"] + extra, orientation: orientation, music: music)
    }

    /// A launch without the music fixture or the overlay wait: for Settings-centred tests (editors, audits).
    /// `unlocked`: the fake entitlement (`-uitestUnlocked YES|NO`, never StoreKit).
    func launchPlain(_ extra: [String], settings: [String: Any] = [:], unlocked: Bool = false,
                     orientation: UIDeviceOrientation = .portrait) {
        XCUIDevice.shared.orientation = orientation
        var args: [String] = ["-uitestResetNotice", "-uitestDiagnostics", "-uitestVisualProbes", "-autostart", "inAppPlayback",
                              "-uitestUnlocked", unlocked ? "YES" : "NO"]
        if !settings.isEmpty {
            let json = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            args += ["-uitestDefaults", json]
        }
        app.launchArguments = args + extra
        app.launch()
        settleOrientation(orientation)
        XCTAssertTrue(wait(20) { self.app.staticTexts["sourceStarts"].exists }, "the source started")
    }

    // MARK: Elements and probes

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    /// A probe's value ("" while missing).
    func probe(_ id: String) -> String {
        let e = app.staticTexts[id]
        return e.exists ? value(e) : ""
    }

    /// `key=<number>` from a probe line.
    static func number(_ line: String, _ key: String) -> Double? {
        for part in line.split(whereSeparator: { $0 == " " || $0 == "|" }) where part.hasPrefix(key + "=") {
            return Double(part.dropFirst(key.count + 1))
        }
        return nil
    }

    /// `key=a,b,c` (numbers) from a probe line.
    static func numbers(_ line: String, _ key: String) -> [Double] {
        for part in line.split(separator: " ") where part.hasPrefix(key + "=") {
            return part.dropFirst(key.count + 1).split(separator: ",").compactMap { Double($0) }
        }
        return []
    }

    func appears(_ e: XCUIElement, _ seconds: Double = 5) -> Bool { wait(seconds) { e.exists } }

    // MARK: Controls and Settings

    var controls: XCUIElement { app.otherElements["controls"] }
    var tapArea: XCUIElement { app.otherElements["visualizerTapArea"].firstMatch }

    func showControls() {
        XCTAssertTrue(appears(tapArea, 15), "the visualizer is up")
        if !controls.exists { tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        // The second try lands lower: on D1 (iPhone 15, 2026-11-22, PERF-014-T22) both taps at 30 % hit the DEBUG
        // render-fault panel, whose readouts widened its backing across the phone's width (the backing no longer takes
        // taps either).
        if !appears(controls, 2) { tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).tap() }
        XCTAssertTrue(appears(controls, 3), "the controls are shown")
    }

    func hideControls() {
        for _ in 0..<4 where controls.exists {
            tapArea.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            if wait(1.5, { !self.controls.exists }) { break }
        }
    }

    /// Taps a control with the controls freshly shown (they hide 5 s after the last use).
    func tapFresh(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<3 {
            if !button.exists { showControls() }
            if appears(button, 2), button.isHittable { button.tap(); return }
            hideControls()
        }
        XCTFail("control \(id) could not be tapped")
    }

    func openSettings() {
        tapFresh("settings")
        XCTAssertTrue(appears(app.navigationBars["Settings"], 5), "Settings opened")
    }

    func closeSettings() {
        let done = app.navigationBars["Settings"].buttons["Done"]
        if done.exists { done.tap() }
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    /// The list a drag scrolls: a side panel on an iPad, else the window (as UITestWaits' `scrollSurface`).
    private func surface() -> XCUIElement {
        let window = app.windows.firstMatch, list = app.collectionViews.firstMatch
        guard list.exists, list.frame.width > 0, list.frame.width < window.frame.width * 0.9 else { return window }
        return list
    }

    /// Scrolls (held drags in the right margin, never a pull at the top of a sheet) until `e` lies on screen below the
    /// navigation bar. Frames only, not `isHittable` (as UITestWaits' `reveal`): an ACC-005 slider row reports
    /// `isHittable` false even when it is fully on screen, so every slider reveal failed on D1-D3 (2026-11-18: Stop 2's
    /// position, the Warp amount and the emitter's Rate, each visible in the screenshots) and scrolled the list away.
    @discardableResult
    func reveal(_ e: XCUIElement, up: Bool = true, drags: Int = 12) -> Bool {
        let window = app.windows.firstMatch
        func visible() -> Bool {
            guard e.exists else { return false }
            let f = e.frame, bar = app.navigationBars.firstMatch
            let top: CGFloat = bar.exists ? bar.frame.maxY : window.frame.minY
            return f.height > 0 && f.minY >= top && f.maxY <= window.frame.maxY
        }
        var downward = !up
        for i in 0..<drags {
            if visible() { return true }
            if i == drags / 2 && !e.exists { downward.toggle() }
            let s = surface()
            let a = s.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: downward ? 0.42 : 0.85))
            let b = s.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: downward ? 0.72 : 0.2))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.1)
        }
        return visible()
    }

    func flip(_ toggle: XCUIElement) {
        // At the switch, not the row's centre (autotester lesson: a centre tap hit the label on D1).
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    /// Drags an ACC-005 slider row's thumb from `current` to `target` (0…1), as UITestSliders' `dragSlider`: the
    /// element's frame is the whole row; the line runs 27 pt above the row's bottom, 34 pt in from each side.
    func dragSlider(_ e: XCUIElement, from current: CGFloat, to target: CGFloat) {
        let rect: CGRect = e.frame
        let width: CGFloat = max(rect.width, 1)
        let y: CGFloat = rect.height > 50 ? rect.height - 27 : rect.height / 2
        let left: CGFloat = rect.height > 50 ? 34 : 14
        let track: CGFloat = max(width - 2 * left, 1)
        func x(_ p: CGFloat) -> CGFloat { left + min(max(p, 0), 1) * track }
        let origin = e.coordinate(withNormalizedOffset: .zero)
        let endX: CGFloat = target <= 0 ? -10 : (target >= 1 ? width + 10 : x(target))
        origin.withOffset(CGVector(dx: x(current), dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: endX, dy: y)), withVelocity: .slow,
                   thenHoldForDuration: 0.1)
    }

    /// One accessibility increment or decrement of slider `id` through its DEBUG probe button
    /// (`-uitestAccessibilityActions`, UITestAccessibilityActionProbe): the entry point VoiceOver's swipe calls.
    @discardableResult
    func accessibilityStep(_ id: String, up: Bool) -> Bool {
        let button = app.buttons[id + (up ? ".uitestIncrement" : ".uitestDecrement")]
        guard appears(button, 5), button.isHittable || reveal(button) else { return false }
        let before = value(button)   // each probe button numbers its taps: this tap's answer differs from the last
        button.tap()
        return wait(3) { self.value(button) != before && self.value(button).hasPrefix("performed") }
    }

    /// Luma (0…1) of a screen rectangle (window points), sampled every `step` points.
    func lumaGrid(_ s: Shot, _ rect: CGRect, step: CGFloat = 2) -> (values: [Double], columns: Int) {
        var values: [Double] = []
        var columns = 0
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var x = rect.minX + step / 2
            var n = 0
            while x < rect.maxX { values.append(s.luma(CGPoint(x: x, y: y))); x += step; n += 1 }
            columns = n
            y += step
        }
        return (values, columns)
    }

    static func meanDifference(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return zip(a, b).reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
    }

    /// Variance of the 4-neighbour Laplacian: high-frequency energy (more octaves → more fine detail).
    static func laplacianVariance(_ g: [Double], columns: Int) -> Double {
        guard columns > 2, g.count / columns > 2 else { return 0 }
        let rows = g.count / columns
        var values: [Double] = []
        for y in 1..<(rows - 1) {
            for x in 1..<(columns - 1) {
                let i = y * columns + x
                values.append(g[i - 1] + g[i + 1] + g[i - columns] + g[i + columns] - 4 * g[i])
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    /// The performance overlay's box in window points, grown by 8 pt (`.null` while it is not shown). Its text changes
    /// every second, so screen statistics leave it out (autotester "The performance overlay is part of every screenshot").
    func overlayBox() -> CGRect {
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        guard overlay.exists, overlay.frame.width > 0 else { return .null }
        return overlay.frame.insetBy(dx: -8, dy: -8)
    }

    /// `change(a, b)` of two `screen(…)` samples without the samples inside `excluded` (window points).
    func change(_ a: [UInt8], _ b: [UInt8], excluding excluded: CGRect) -> Double {
        let (w, h) = lastSize
        let window = app.windows.firstMatch.frame
        guard a.count == b.count, w > 0, h > 0, a.count >= w * h * 4, window.width > 0, !excluded.isNull else {
            return Self.change(a, b)
        }
        let perPoint: CGFloat = CGFloat(w) / window.width
        var sum = 0, n = 0
        for y in 0..<h {
            for x in 0..<w where !excluded.contains(CGPoint(x: CGFloat(x) / perPoint, y: CGFloat(y) / perPoint)) {
                let i = (y * w + x) * 4
                sum += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2]))
                n += 3
            }
        }
        return n > 0 ? Double(sum) / Double(n) / 255 : 0
    }

    /// Taps a point given in window points.
    func tapPoint(_ p: CGPoint) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).tap()
    }

    // MARK: The strobing fixture (`-uitestImportPreset fixture:strobe`)

    /// Plays the imported "Strobe" fixture from My Presets (Load Anyway when the May flash alert asks); true once the
    /// `presetFlashProbe` names it.
    @discardableResult
    func playStrobeFixture() -> Bool { playImportedFixture("Strobe") }

    /// Plays an imported fixture (`-uitestImportPreset fixture:strobe` or `fixture:calm`) from My Presets by its
    /// name ("Strobe", "Calm"); true once the `presetFlashProbe` names it.
    @discardableResult
    func playImportedFixture(_ name: String) -> Bool {
        func dismissImport() {
            let alert = app.alerts["Import Preset"]
            if alert.exists { alert.buttons["OK"].firstMatch.tap() }
        }
        dismissImport()
        tapFresh("presets")
        guard appears(app.buttons["node:included"], 10) else { XCTFail("library home"); return false }
        let myPresets = app.buttons["node:myPresets"]
        XCTAssertTrue(reveal(myPresets), "My Presets")
        myPresets.tap()
        let row = app.buttons["preset:\(name)"]
        XCTAssertTrue(wait(30) { dismissImport(); return row.exists }, "the imported fixture \(name) is listed")
        row.tap()
        let warning = app.alerts["May flash"]
        if appears(warning, 3) { warning.buttons["Load Anyway"].firstMatch.tap() }
        return wait(15) { self.probe("presetFlashProbe").hasPrefix("name=\(name)|") }
    }

    // MARK: Pixels

    /// A full-resolution screenshot (attached) as RGBA with its points-to-pixels scale.
    struct Shot {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat

        /// The colour (0…1) at a point in window points.
        func rgb(_ p: CGPoint) -> (Double, Double, Double) {
            let x = min(max(Int(p.x * scale), 0), width - 1), y = min(max(Int(p.y * scale), 0), height - 1)
            let i = (y * width + x) * 4
            guard i + 2 < pixels.count else { return (0, 0, 0) }
            return (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
        }

        func luma(_ p: CGPoint) -> Double { let c = rgb(p); return 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
    }

    func shot(_ task: String, _ label: String, step: Int = 1) -> Shot {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = "\(task) \(label)"
        a.lifetime = .keepAlways
        add(a)
        let pixels = Self.rgba(s.image, step: step)
        let w = (s.image.cgImage?.width ?? 0) / step, h = (s.image.cgImage?.height ?? 0) / step
        let points: CGFloat = max(app.windows.firstMatch.frame.width, 1)
        return Shot(pixels: pixels, width: w, height: h, scale: CGFloat(w) / points)
    }

    /// CIE76 ΔE between two sRGB colours (0…1), through CIELAB (D65).
    static func deltaE(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        func lab(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = lin(c.0), g = lin(c.1), bl = lin(c.2)
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * bl
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let p = lab(a), q = lab(b)
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }

    /// Hue (degrees) and chroma (max − min, 0…1) of a sampled RGBA pixel.
    static func hueChroma(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, chroma: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), c = mx - mn
        guard c > 1e-6 else { return (0, 0) }
        var h: Double
        if mx == r { h = (g - b) / c } else if mx == g { h = (b - r) / c + 2 } else { h = (r - g) / c + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return (h, c)
    }

    /// The circular mean of angles in degrees.
    static func circularMean(_ degrees: [Double]) -> Double {
        guard !degrees.isEmpty else { return 0 }
        let s = degrees.reduce(0.0) { $0 + sin($1 * .pi / 180) }, c = degrees.reduce(0.0) { $0 + cos($1 * .pi / 180) }
        var m = atan2(s, c) * 180 / .pi
        if m < 0 { m += 360 }
        return m
    }

    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// UIX-005-R3: the pad's targets are at least 60 pt, 72 pt when both size classes are regular (an iPad full screen).
    var performanceTargetSide: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 72 : 60 }
}
