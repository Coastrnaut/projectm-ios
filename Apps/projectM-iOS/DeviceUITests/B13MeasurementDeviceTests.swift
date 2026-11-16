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
}
