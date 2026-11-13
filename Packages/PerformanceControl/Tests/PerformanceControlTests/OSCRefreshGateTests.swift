// OSC-009-T07: the refresh gate that keeps an OSC flood off the main thread (OSC-009-R11, S4 rate
// part; research OSC-009-D7). Simulated time only. Budget: well under 1 s.
@testable import PerformanceControl
import XCTest

final class OSCRefreshGateTests: XCTestCase {
    func testOnePendingAndTheInterval() {
        let gate = OSCRefreshGate()
        XCTAssertEqual(gate.request(now: 0), 0, "the first refresh runs at once")
        XCTAssertNil(gate.request(now: 1), "one refresh pending at a time")
        gate.begin(now: 5)
        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.request(now: 10), 5 + OSCRefreshGate.defaultInterval - 10, "waits out 1/30 s from the last run")
        XCTAssertNil(gate.request(now: 11))
        gate.begin(now: 5 + OSCRefreshGate.defaultInterval)
        XCTAssertEqual(gate.request(now: 1_000_000_000), 0, "long after the last run: at once")
    }

    func testFloodOfRequestsStartsAtMostThirtyRefreshesPerSecond() {
        let gate = OSCRefreshGate()
        var scheduledAt: UInt64?
        var runs = 0
        // 10,000 requests over 1 simulated second (one per 100 µs); a scheduled refresh runs when due.
        for i in 0..<10_000 {
            let now = UInt64(i) * 100_000
            if let due = scheduledAt, due <= now {
                gate.begin(now: due)
                runs += 1
                scheduledAt = nil
            }
            if let delay = gate.request(now: now) {
                XCTAssertNil(scheduledAt, "never two pending")
                scheduledAt = now + delay
            }
        }
        XCTAssertLessThanOrEqual(runs, 31, "≤ 30 per second + 1")
        XCTAssertGreaterThanOrEqual(runs, 29, "the latest state still reaches the screen about 30 times a second")
    }
}
