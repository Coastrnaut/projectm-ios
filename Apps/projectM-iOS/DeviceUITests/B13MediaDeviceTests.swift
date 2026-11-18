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
        for _ in 0..<4 where !toggle.isHittable { list.swipeUp() }
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
