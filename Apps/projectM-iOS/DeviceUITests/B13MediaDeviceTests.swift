// B13MediaDeviceTests.swift — QA-011 MED-005-T20 (specs/284-med-005-video-reverse-playback), automated on the device.
// No picker: the DEBUG seed `-uitestSeedVideo hd30` writes a 1920 × 1080, 30 fps, 30 s clip in the app and imports it
// through the normal store path; `-uitestSeedVideo long120` a 640 × 360, 30 fps, 2-minute clip (UITestVideoFixture).
// * The 30 s 1080p clip reverses after preparation: the `videoReverse` probe goes from `preparing` to `playing <i>`
//   and the cached index goes down. Memory: the cache's peak accounted bytes (`videoReverseMemory`, MED-005-R3) must
//   be within the device class budget (AnimatedFrameBudget: 32 / 64 / 128 MB), and the process footprint
//   (`memoryProbe`, the number Xcode's memory gauge shows) is reported; MED-005-R3 bounds only the cache's accounted
//   bytes, so the footprint's peak is held to `maximumFootprintShare` of the device's memory (jetsam safety), not to
//   the budget (MED-005 Clarifications 2026-11-18: D3 grew 127 MB, D1 93 MB, with the cache at 61 MB of 64).
// * The 2-minute clip with Reverse on shows the 30-second sentence (MED-005-R5) and keeps playing forward (the shown
//   picture's media index rises), with the probe reading `unsupported`.
// Reverse is turned on with the real Settings switch. Nothing here raises a system prompt.
// QA-011 Batch 5 (2026-11-18): MED-002-T27/T28 play `-uitestSeedVideo uhd60` (the Mac's HEVC 3840 × 2160 60 fps 10 s
// fixture from Documents, else a generated counter of that shape) and `long600` (HEVC 640 × 360, 10 minutes; never
// played to the end) and read the clip's own rate from the `videoFrameRate` probe (distinct pictures per second,
// Debug/UITestMediaDeviceProbes.swift), the footprint from `memoryProbe` and the device's thermal state from the test
// runner's `ProcessInfo.thermalState` (the runner shares the device). PERF-006-T17 fills memory until the system's
// own warning arrives (DEBUG `memory:fill`) and reads the recovery counter (`-uitestMemoryPressure`).
import UIKit
import XCTest

@MainActor
final class B13MediaDeviceTests: DeviceAcceptanceCase {
    static let tooLongMessage = "Reverse playback is available for clips up to 30 seconds. This video plays forward."
    /// The peak footprint while preparing stays below this share of the device's physical memory.
    static let maximumFootprintShare = 0.25

    // MARK: Helpers

    private func probe(_ id: String) -> String {
        app.descendants(matching: .any)[id].firstMatch.value as? String ?? ""
    }

    private func footprintMB() -> Int? {
        Int(probe("memoryProbe").replacingOccurrences(of: "footprintMB=", with: ""))
    }

    private var videoValue: String { app.descendants(matching: .any)["videoVisual"].firstMatch.value as? String ?? "" }

    /// "playing <index>" → index; nil in any other state.
    private func reverseIndex() -> Int? {
        let parts = probe("videoReverse").split(separator: " ")
        guard parts.count == 2, parts[0] == "playing" else { return nil }
        return Int(parts[1])
    }

    /// "peak=<bytes> budget=<bytes>" → (peak, budget).
    private func reverseMemory() -> (peak: Int, budget: Int) {
        var peak = -1, budget = -1
        for part in probe("videoReverseMemory").split(separator: " ") {
            if part.hasPrefix("peak=") { peak = Int(part.dropFirst(5)) ?? -1 }
            if part.hasPrefix("budget=") { budget = Int(part.dropFirst(7)) ?? -1 }
        }
        return (peak, budget)
    }

    private func openSettings() {
        let controls = app.otherElements["controls"], area = app.otherElements["visualizerTapArea"].firstMatch
        if !controls.exists { area.tap(); _ = wait(3) { controls.exists } }
        app.buttons["settings"].tap()
        XCTAssertTrue(wait(5) { self.app.navigationBars["Settings"].exists }, "Settings opens")
    }

    private func closeSettings() {
        app.navigationBars["Settings"].buttons["Done"].tap()
        _ = wait(5) { !self.app.navigationBars["Settings"].exists }
    }

    /// Opens Settings (at the Video section) and turns Reverse on; the switch's value reads 1.
    private func turnReverseOn() {
        openSettings()
        let toggle = app.switches["videoReverseToggle"].firstMatch
        XCTAssertTrue(wait(5) { toggle.exists }, "the Reverse switch is offered while a video is stored")
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where !toggle.isHittable { list.scrollStep(up: true, velocity: .fast) }
        // A SwiftUI Toggle row's centre is its label; tap the switch at the trailing edge.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        if !wait(3, { (toggle.value as? String) == "1" }) { toggle.switches.firstMatch.tap() }
        XCTAssertTrue(wait(3) { (toggle.value as? String) == "1" }, "Reverse is on: \(String(describing: toggle.value))")
    }

    /// Launches the Video visual with `seed` and waits until the seeded clip plays (`size` in its VoiceOver value).
    private func launchVideo(_ task: String, seed: String, size: String) {
        launch(visual: "video", extra: ["-uitestSeedVideo", seed, "-uitestSettingsSection", "video"])
        XCTAssertTrue(wait(90) { self.videoValue.contains(size) }, "\(task): the seeded clip plays: \(videoValue)")
        XCTAssertTrue(wait(10) { self.probe("videoReverse").hasPrefix("off") }, "\(task): forward first: \(probe("videoReverse"))")
    }

    // MARK: MED-002-T27, T28 (QA-011 Batch 5)

    /// The clip's distinct pictures per second, once a second for `seconds` (the `videoFrameRate` probe).
    private func clipRates(seconds: Int) -> [Double] {
        var rates: [Double] = []
        for _ in 0..<seconds {
            pause(1)
            let fps = probe("videoFrameRate").split(separator: " ").first { $0.hasPrefix("fps=") }
            if let fps, let value = Double(fps.dropFirst(4)) { rates.append(value) }
        }
        return rates
    }

    /// Launches the Video visual with a Batch 5 seed and waits until it plays (`width` in its value).
    private func launchSeeded(_ task: String, seed: String, width: String, timeout: Double) {
        launch(visual: "video", extra: ["-uitestSeedVideo", seed])
        XCTAssertTrue(wait(timeout) { self.videoValue.contains(width) }, "\(task): the \(seed) clip plays: \(videoValue)")
        pause(3)
    }

    /// Footprint readings every `every` s for `seconds`; growth is the last third's mean over the first third's.
    private func footprints(seconds: Int, every: Int) -> (values: [Int], growth: Double) {
        var values: [Int] = []
        for _ in 0..<(seconds / every) {
            pause(Double(every))
            if let mb = footprintMB() { values.append(mb) }
        }
        let third = max(1, values.count / 3)
        let first = Double(values.prefix(third).reduce(0, +)) / Double(third)
        let last = Double(values.suffix(third).reduce(0, +)) / Double(third)
        return (values, first > 0 ? (last - first) / first : 0)
    }

    /// MED-002-T27 (D1, D3): the 4K60 HEVC clip plays at its rate (median ≥ 58 pictures per second; the clip loops
    /// every 10 s) and memory stays flat over 60 s (≤ 10 % growth).
    func testMED002UHD60PlaysAtItsRateWithFlatMemory() {
        let task = "MED-002-T27"
        launchSeeded(task, seed: "uhd60", width: "3840", timeout: 120)
        let rates = clipRates(seconds: 15)
        let memory = footprints(seconds: 45, every: 5)
        let median = Self.median(rates)
        report(task, "4K60", ["fpsMedian": median, "fpsMin": rates.min() ?? -1, "footprintFirstMB": Double(memory.values.first ?? -1),
                              "footprintPeakMB": Double(memory.values.max() ?? -1), "growth": memory.growth])
        XCTAssertGreaterThanOrEqual(rates.count, 10, "\(task): the probe reads (-uitestDiagnostics)")
        XCTAssertGreaterThanOrEqual(median, 58, "\(task): 4K60 at its rate: \(rates)")
        XCTAssertLessThanOrEqual(memory.growth, 0.10, "\(task): memory bounded: \(memory.values)")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    /// MED-002-T27 (D1, D3): the 10-minute clip plays at its rate (median ≥ 29 of 30), forward (the shown index rises,
    /// no wrap inside a minute), and memory stays flat over 60 s.
    func testMED002TenMinuteClipPlaysAtItsRateWithFlatMemory() {
        let task = "MED-002-T27"
        launchSeeded(task, seed: "long600", width: "640", timeout: 180)
        let firstIndex = Int(probe("videoMediaFrameIndex")) ?? -1
        let rates = clipRates(seconds: 15)
        let memory = footprints(seconds: 45, every: 5)
        let lastIndex = Int(probe("videoMediaFrameIndex")) ?? -1
        let median = Self.median(rates)
        report(task, "10 minutes", ["fpsMedian": median, "firstIndex": Double(firstIndex), "lastIndex": Double(lastIndex),
                                    "footprintPeakMB": Double(memory.values.max() ?? -1), "growth": memory.growth])
        XCTAssertGreaterThanOrEqual(median, 29, "\(task): the long clip at its rate: \(rates)")
        XCTAssertGreaterThan(lastIndex, firstIndex + 30 * 50, "\(task): it plays forward for the minute (\(firstIndex) → \(lastIndex))")
        XCTAssertLessThanOrEqual(memory.growth, 0.10, "\(task): memory bounded: \(memory.values)")
    }

    /// MED-002-T28 (D1, D3): 3 minutes of 4K60 playback with the thermal state below serious at every 10 s reading and
    /// the frame rate recorded (about 3.3 minutes with the launch; run with -default-test-execution-time-allowance 300).
    func testMED002ThreeMinutes4KThermal() {
        let task = "MED-002-T28"
        launchSeeded(task, seed: "uhd60", width: "3840", timeout: 120)
        var worst = ProcessInfo.ThermalState.nominal, rates: [Double] = []
        for step in 0..<18 {
            let window = clipRates(seconds: 10)
            rates += window
            let state = ProcessInfo.processInfo.thermalState
            if state.rawValue > worst.rawValue { worst = state }
            report(task, "t=\((step + 1) * 10) s", ["thermalState": Double(state.rawValue), "fpsMedian": Self.median(window),
                                                    "overlayFPS": overlayFPS() ?? -1])
        }
        report(task, "3 minutes", ["worstThermalState": Double(worst.rawValue), "fpsMedian": Self.median(rates),
                                   "fpsMin": rates.min() ?? -1])
        XCTAssertLessThan(worst.rawValue, ProcessInfo.ThermalState.serious.rawValue, "\(task): below serious (worst \(worst.rawValue))")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    // MARK: PERF-006-T17 (QA-011 Batch 5)

    /// PERF-006-T17: a real memory warning from the system: the DEBUG `memory:fill` grows dirty memory until UIKit
    /// posts its own warning (devicectl sendMemoryWarning fails with ENOENT on iPadOS 27.2, D2 2026-11-21); the app
    /// survives, counts a recovery, keeps rendering and the music keeps playing.
    func testPERF006RealMemoryWarning() throws {
        let task = "PERF-006-T17"
        launch(visual: "photo", extra: ["-uitestSeedPhoto", "pattern", "-uitestMemoryPressure"])
        let starts = probe("sourceStarts")
        let before = Int(probe("memoryRecoveries")) ?? -1
        XCTAssertGreaterThanOrEqual(before, 0, "\(task): the recovery readout (-uitestMemoryPressure)")
        app.buttons["memory:fill"].firstMatch.tap()
        let filled = wait(100) { !self.probe("memoryFill").hasPrefix("state=filling") && self.probe("memoryFill") != "state=idle" }
        let fill = probe("memoryFill")
        print("B13 \(task): \(fill)")
        XCTAssertTrue(filled && fill.hasPrefix("state=warned"), "\(task): the system's own warning arrived while filling: \(fill)")
        let recovered = wait(45) { (Int(self.probe("memoryRecoveries")) ?? -1) > before }
        XCTAssertTrue(recovered, "\(task): a recovery after the real warning (\(before) → \(probe("memoryRecoveries")))")
        XCTAssertEqual(app.state, .runningForeground, "\(task): the app survives")
        assertDrawingAndMoving(task, "after the warning")
        let overlay = app.descendants(matching: .any)["performanceOverlay"].firstMatch
        XCTAssertTrue(wait(10) { overlay.label.contains("Active audio") }, "\(task): the music plays: \(overlay.label.prefix(120))")
        XCTAssertEqual(probe("sourceStarts"), starts, "\(task): the source did not restart")
        report(task, "real warning", ["recoveries": Double(Int(probe("memoryRecoveries")) ?? -1),
                                      "freedBytes": Double(Int(probe("memoryFreedBytes")) ?? -1)])
    }

    // MARK: MED-005-T20

    /// A 30 s 1080p clip reverses after preparation, within the device class budget.
    func testMED005ThirtySecond1080pClipReversesWithinBudget() {
        let task = "MED-005-T20"
        launchVideo(task, seed: "hd30", size: "1920")
        pause(3)   // the forward decoder settles
        var before: [Int] = []
        for _ in 0..<3 { if let mb = footprintMB() { before.append(mb) }; pause(1) }
        let baseline = before.max() ?? -1
        XCTAssertGreaterThan(baseline, 0, "the memory probe reads (-uitestDiagnostics)")

        turnReverseOn()
        let started = Date()
        closeSettings()
        // Preparation: the clip plays forward until the cache is ready; sample the footprint meanwhile.
        var peakFootprint = baseline, states: Set<String> = []
        let ready = wait(120) {
            if let mb = self.footprintMB() { peakFootprint = max(peakFootprint, mb) }
            states.insert(String(self.probe("videoReverse").split(separator: " ").first ?? ""))
            return self.reverseIndex() != nil
        }
        let preparation = Date().timeIntervalSince(started)
        XCTAssertTrue(ready, "the cache plays: \(probe("videoReverse")) (states seen \(states.sorted()))")
        for _ in 0..<3 { if let mb = footprintMB() { peakFootprint = max(peakFootprint, mb) }; pause(1) }

        // Backwards: each change goes back by less than half the clip (900 cached pictures), modulo a wrap.
        var readings: [Int] = []
        for _ in 0..<4 {
            let previous = reverseIndex() ?? -1
            _ = wait(3) { (self.reverseIndex() ?? previous) != previous }
            readings.append(reverseIndex() ?? -1)
        }
        var downs = 0
        for (a, b) in zip(readings, readings.dropFirst()) {
            let back = (a - b + 900) % 900
            if back > 0, back < 450 { downs += 1 }
        }
        let memory = reverseMemory()
        let budgetMB = memory.budget / 1_048_576
        let growth = peakFootprint - baseline
        report(task, "30 s 1080p reverse", [
            "preparationSeconds": preparation, "peakCacheMB": Double(memory.peak) / 1_048_576, "budgetMB": Double(budgetMB),
            "baselineFootprintMB": Double(baseline), "peakFootprintMB": Double(peakFootprint), "footprintGrowthMB": Double(growth),
            "downs": Double(downs), "physicalMemoryGB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
        ])
        print("MED-005-T20 reverse indices \(readings), states \(states.sorted())")
        XCTAssertGreaterThanOrEqual(downs, 2, "the picture index goes down: \(readings)")
        XCTAssertTrue([32, 64, 128].contains(budgetMB), "the budget is a device class budget: \(budgetMB) MB")
        XCTAssertGreaterThan(memory.peak, 0, "the cache's peak is recorded")
        XCTAssertLessThanOrEqual(memory.peak, memory.budget, "peak accounted cache bytes within the budget")
        let physicalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        XCTAssertLessThanOrEqual(Double(peakFootprint), physicalMB * Self.maximumFootprintShare,
                                 "peak footprint \(peakFootprint) MB (growth \(growth) MB) below a quarter of \(Int(physicalMB)) MB")
        assertDrawingAndMoving(task, "reversed")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    /// A 2-minute clip with Reverse on shows the 30-second sentence and keeps playing forward.
    func testMED005TwoMinuteClipShowsThe30SecondMessageAndPlaysForward() {
        let task = "MED-005-T20"
        launchVideo(task, seed: "long120", size: "640")
        turnReverseOn()
        let status = app.staticTexts["videoReverseStatus"].firstMatch
        XCTAssertTrue(wait(10) { status.exists && status.label == Self.tooLongMessage },
                      "the 30-second message: \(status.exists ? status.label : "none")")
        let shown = status.exists && status.label == Self.tooLongMessage
        screen(task, "2-minute clip message")   // attached for review
        closeSettings()
        XCTAssertTrue(wait(5) { self.probe("videoReverse").hasPrefix("unsupported") }, "unsupported: \(probe("videoReverse"))")
        // Forward: the shown picture's media index rises (the clip wraps only after 3,600 pictures).
        var readings: [Int] = []
        for _ in 0..<4 {
            pause(1)
            readings.append(Int(probe("videoMediaFrameIndex")) ?? -1)
        }
        var ups = 0
        for (a, b) in zip(readings, readings.dropFirst()) where a >= 0 && b > a { ups += 1 }
        report(task, "2-minute clip", ["messageShown": shown ? 1 : 0, "forwardSteps": Double(ups),
                                       "unsupported": probe("videoReverse").hasPrefix("unsupported") ? 1 : 0])
        print("MED-005-T20 forward indices \(readings)")
        XCTAssertGreaterThanOrEqual(ups, 2, "the clip keeps playing forward: \(readings)")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }
}
