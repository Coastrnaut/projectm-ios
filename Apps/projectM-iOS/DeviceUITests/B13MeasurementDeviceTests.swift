// B13MeasurementDeviceTests.swift — QA-011 owner session B13 ("Measurements attached to Xcode and Instruments"), the
// parts that need no Instruments, automated on the device. VIS-003-T17: D2 and D3 render the oscilloscope with the
// reference track (frame rate on the overlay, drawing and moving; a thin line covers about 1 % of the screen). The D1 Instruments part
// (Allocations, Metal System Trace) is separate: the matrix's `xctrace-*` cases (scripts/mac_driver/xctrace.py).
// PERF-003-T15: the effect quality level at forced (DEBUG `-uitestThermalState`) and real thermal states.
import UIKit
import XCTest

@MainActor
final class B13MeasurementDeviceTests: DeviceAcceptanceCase {
    /// VIS-003-T17: the oscilloscope renders, in both orientations, within the frame-rate budget.
    func testVIS003OscilloscopeRenders() {
        let task = "VIS-003-T17"
        launch(visual: "oscilloscope")
        assertFrameRate(task, "portrait")
        assertDrawingAndMoving(task, "portrait", minimumDraw: 0.005)
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        assertFrameRate(task, "landscape")
        assertDrawingAndMoving(task, "landscape", minimumDraw: 0.005)
    }

    /// VIS-003-T17 (D1): 60 s of the oscilloscope with the reference track; the process footprint (Xcode's memory
    /// gauge, DEBUG `memoryProbe`, once a second) does not grow in the frame loop, and the frame rate stays within the
    /// VIS-001 budget at the start and the end. The last 10 s may exceed the 5-15 s median by at most 5 MB.
    func testVIS003SixtySecondsWithoutMemoryGrowth() {
        let task = "VIS-003-T17"
        launch(visual: "oscilloscope")
        assertFrameRate(task, "start")
        let probe = app.descendants(matching: .any)["memoryProbe"].firstMatch
        var samples: [Int] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 60 {
            let text = (probe.value as? String) ?? ""
            if let mb = Int(text.replacingOccurrences(of: "footprintMB=", with: "")), mb > 0 { samples.append(mb) }
            pause(1)
        }
        assertFrameRate(task, "after 60 s")
        guard samples.count >= 40 else { return XCTFail("too few memory samples: \(samples)") }
        func median(_ values: ArraySlice<Int>) -> Int { values.sorted()[values.count / 2] }
        let early = median(samples[5..<15]), late = median(samples[(samples.count - 10)...])
        print("VIS-003 footprint (MB): \(samples)")
        report(task, "footprint", ["earlyMB": Double(early), "lateMB": Double(late), "maxMB": Double(samples.max() ?? 0),
                                   "samples": Double(samples.count)])
        XCTAssertLessThanOrEqual(late, early + 5, "no memory growth over 60 s: \(early) MB early, \(late) MB late")
    }

    /// PERF-004-T14 (D1) / T15 (D3): 100 visual switches (Camera → Photo → Circular Spectrum); GPU memory
    /// (`MTLDevice.currentAllocatedSize` after each cycle) plateaus after the first cycle: the last cycles are within
    /// 10 % of the second cycle and never above the highest early value by more than 10 %.
    func testPERF004GPUMemoryPlateausOverVisualSwitches() {
        let task = UIDevice.current.userInterfaceIdiom == .pad ? "PERF-004-T15" : "PERF-004-T14"
        launch(visual: "circularSpectrum", extra: ["-uitestSeedPhoto", "pattern", "-uitestCycleVisuals", "100"])
        let probe = app.staticTexts["visualCycleProbe"]
        XCTAssertTrue(wait(90) { (probe.value as? String ?? "").contains("done=1") }, "100 switches: \(String(describing: probe.value))")
        let text = probe.value as? String ?? ""
        let mb = (text.components(separatedBy: "mb=").last ?? "").components(separatedBy: " ").first?
            .split(separator: ",").compactMap { Int($0) } ?? []
        print("PERF-004 memory per cycle (MB): \(mb)")
        guard mb.count >= 4 else { return XCTFail("too few cycles recorded: \(text)") }
        let early = mb[1], earlyMax = mb.prefix(3).max() ?? early, late = Array(mb.suffix(5))
        report(task, "gpu memory", ["firstMB": Double(mb[0]), "secondMB": Double(early), "lastMB": Double(mb.last ?? 0),
                                    "maxMB": Double(mb.max() ?? 0), "cycles": Double(mb.count)])
        XCTAssertLessThanOrEqual(Double(late.max() ?? 0), Double(earlyMax) * 1.1, "no growth past the early cycles: \(mb)")
        XCTAssertEqual(app.state, .runningForeground, "no crash")
    }

    // MARK: PERF-003-T15 (QA-011 Batch 2, 2026-11-18)

    /// The overlay's "effect quality …" line: the target level and its reason (PERF-003-R10).
    private func effectQuality() -> String {
        let label = app.descendants(matching: .any)["performanceOverlay"].firstMatch.label
        guard let range = label.range(of: #"effect quality [a-z]+( \([a-z ]+\))?"#, options: .regularExpression) else { return "" }
        return String(label[range])
    }

    /// PERF-003-T15 (D1), the policy at the states that cannot be reached safely on purpose: with the glow on and the
    /// DEBUG thermal state `serious`, the overlay names "reduced (thermal)" and the 60 fps cap stays (the glow steps
    /// down before the frame rate, PERF-003-R7); at `critical` it names "minimal (thermal)" and the frame rate is
    /// capped at 30. About 60 s.
    func testPERF003ForcedThermalStatesFollowThePolicy() {
        let task = "PERF-003-T15"
        for (state, level, low, high) in [("serious", "reduced", 50.0, 61.0), ("critical", "minimal", 20.0, 31.5)] {
            launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true],
                   extra: ["-uitestThermalState", state])
            XCTAssertTrue(wait(10) { self.effectQuality().hasPrefix("effect quality \(level)") },
                          "\(state): the overlay names \(level): \(effectQuality())")
            XCTAssertTrue(effectQuality().contains("(thermal)"), "\(state): the reason is the thermal state: \(effectQuality())")
            let samples = sampleFPS(seconds: 10)
            let median = Self.median(samples)
            report(task, "forced \(state)", ["fpsMedian": median, "fpsMax": samples.max() ?? 0, "samples": Double(samples.count)])
            XCTAssertGreaterThanOrEqual(samples.count, 5, "\(state): the overlay was readable")
            XCTAssertTrue((low...high).contains(median), "\(state): median \(median) fps, expected \(low)-\(high)")
            app.terminate()
        }
    }

    /// PERF-003-T15 (D1), the real thermal state: 150 s of the glow under sustained load (under the 3-minute test
    /// budget; the full 5 minutes is the B13 owner step). Every 5 s the overlay's level is checked against the policy
    /// for the device's thermal state at that moment (`ProcessInfo.thermalState` of the test runner is the device's):
    /// nominal or fair never shows a thermal reduction, serious shows reduced or minimal, critical shows minimal.
    func testPERF003SustainedGlowLevelFollowsTheRealThermalState() {
        let task = "PERF-003-T15"
        launch(visual: "circularSpectrum", settings: ["settings.circularSpectrum.glow": true])
        var states: [String: Int] = [:]
        var mismatches: [String] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 150 {
            pause(5)
            let thermal = ProcessInfo.processInfo.thermalState
            let quality = effectQuality()
            let name = ["nominal", "fair", "serious", "critical"][min(3, thermal.rawValue)]
            states[name, default: 0] += 1
            let ok: Bool
            switch thermal {
            case .nominal, .fair: ok = !quality.contains("(thermal)")
            case .serious: ok = quality.hasPrefix("effect quality reduced") || quality.hasPrefix("effect quality minimal")
            default: ok = quality.hasPrefix("effect quality minimal")
            }
            if !ok { mismatches.append("\(Int(Date().timeIntervalSince(start))) s \(name): \(quality)") }
        }
        print("PERF-003 thermal states seen (5 s samples): \(states)")
        report(task, "sustained glow", states.mapValues(Double.init).merging(["mismatches": Double(mismatches.count)]) { a, _ in a })
        XCTAssertTrue(mismatches.isEmpty, "the level follows the thermal state: \(mismatches)")
        assertFrameRate(task, "after 150 s", seconds: 5, minimum: 25)
    }
}
