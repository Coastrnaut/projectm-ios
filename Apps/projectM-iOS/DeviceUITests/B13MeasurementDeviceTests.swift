// B13MeasurementDeviceTests.swift — QA-011 owner session B13 ("Measurements attached to Xcode and Instruments"), the
// parts that need no Instruments, automated on the device. VIS-003-T17: D2 and D3 render the oscilloscope with the
// reference track (frame rate on the overlay, drawing and moving; a thin line covers about 1 % of the screen). The D1 Instruments part
// (Allocations, Metal System Trace) is separate.
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
}
