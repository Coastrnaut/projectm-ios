// PeakCapTrackerTests.swift — VIS-002-T07: peak caps hold, then fall (VIS-002-R6, S3). The clock is
// injected: every step passes an explicit frame time, never wall time. No Metal: runs on Linux.
import XCTest
@testable import VisualGenerators

final class PeakCapTrackerTests: XCTestCase {
    private func step(_ tracker: PeakCapTracker, _ values: [Float], dt: Double) {
        values.withUnsafeBufferPointer { tracker.update(values: $0, count: values.count, frameTime: dt) }
    }

    func testHoldsThenFallsAtTheDocumentedRate() {
        let tracker = PeakCapTracker(holdSeconds: 0.5, fallPerSecond: 1.0)
        step(tracker, [1], dt: 0.01)
        XCTAssertEqual(tracker.peak(0), 1)
        // 0.25 s, 0.5 s: still held.
        for _ in 0..<25 { step(tracker, [0], dt: 0.01) }
        XCTAssertEqual(tracker.peak(0), 1, accuracy: 1e-9, "held at 0.25 s")
        for _ in 0..<25 { step(tracker, [0], dt: 0.01) }
        XCTAssertEqual(tracker.peak(0), 1, accuracy: 1e-6, "held until 0.5 s")
        // 0.75 s: fell 0.25.
        for _ in 0..<25 { step(tracker, [0], dt: 0.01) }
        XCTAssertEqual(tracker.peak(0), 0.75, accuracy: 1e-6, "1.0 per second after the hold")
        for _ in 0..<100 { step(tracker, [0], dt: 0.01) }
        XCTAssertEqual(tracker.peak(0), 0, "reaches the bar and stops")
    }

    func testNeverBelowTheBarAndAHigherValueRestartsTheHold() {
        let tracker = PeakCapTracker(holdSeconds: 0.5, fallPerSecond: 1.0)
        step(tracker, [0.8], dt: 0.1)
        for _ in 0..<6 { step(tracker, [0.6], dt: 0.1) }   // 0.6 s: held 0.5, fell 0.1 → 0.7
        XCTAssertEqual(tracker.peak(0), 0.7, accuracy: 1e-6)
        for _ in 0..<5 { step(tracker, [0.6], dt: 0.1) }
        XCTAssertEqual(tracker.peak(0), 0.6, accuracy: 1e-6, "never below the bar")
        step(tracker, [0.9], dt: 0.1)
        XCTAssertEqual(tracker.peak(0), 0.9, accuracy: 1e-6, "jumps to a higher value")
        for _ in 0..<5 { step(tracker, [0], dt: 0.1) }
        XCTAssertEqual(tracker.peak(0), 0.9, accuracy: 1e-6, "the hold restarted")
    }

    func testFrameTimeIsClampedAndHoldFlowsIntoTheFall() {
        let tracker = PeakCapTracker(holdSeconds: 0.5, fallPerSecond: 1.0)
        step(tracker, [1], dt: 0.016)
        step(tracker, [0], dt: 10)   // clamped to 0.1 s
        XCTAssertEqual(tracker.peak(0), 1, accuracy: 1e-6, "a 10 s hitch counts as 0.1 s (still held)")
        for _ in 0..<4 { step(tracker, [0], dt: 0.1) }   // 0.5 s of hold used
        step(tracker, [0], dt: 0.08)                      // all fall
        XCTAssertEqual(tracker.peak(0), 0.92, accuracy: 1e-6)
        let mid = PeakCapTracker(holdSeconds: 0.05, fallPerSecond: 2)
        step(mid, [1], dt: 0.01)
        step(mid, [0], dt: 0.08)   // 0.05 s hold, then 0.03 s of fall at 2/s
        XCTAssertEqual(mid.peak(0), 0.94, accuracy: 1e-6, "hold used up mid-frame flows into the fall")
        step(mid, [0], dt: -1)
        XCTAssertEqual(mid.peak(0), 0.94, accuracy: 1e-6, "negative frame time is 0")
        mid.reset()
        XCTAssertEqual(mid.peak(0), 0)
    }

    func testLayoutDrawsCapsAtThePeak() {
        let c = LinearSpectrumConfiguration(barCount: .b16)
        let layout = LinearSpectrumLayout(configuration: c)
        var bands = [Float](repeating: 0, count: 16)
        bands[3] = 1
        layout.layout(bands, frameTime: 0.016, width: 160, height: 100)
        bands[3] = 0.2
        for _ in 0..<10 { layout.layout(bands, frameTime: 0.1, width: 160, height: 100) }   // 0.5 s held, 0.5 s fall → 0.5
        XCTAssertEqual(Double(layout.peak(ofBar: 3)), 0.5, accuracy: 1e-5)
        let cap = try! XCTUnwrap(layout.rectangles(ofBar: 3).cap)
        XCTAssertEqual(cap.maxY, 100 - 0.5 * c.lengthScale * 100, accuracy: 1e-3, "cap starts at P·λ·L")
        XCTAssertNil(layout.rectangles(ofBar: 4).cap, "no cap at 0")
        layout.configuration.orientation = .horizontal
        layout.layout(bands, frameTime: 0.1, width: 160, height: 100)
        XCTAssertEqual(Double(layout.peak(ofBar: 3)), 0.2, accuracy: 1e-6, "an orientation change resets the caps")
    }
}
