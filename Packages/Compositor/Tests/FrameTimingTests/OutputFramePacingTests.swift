// OutputFramePacingTests.swift — OUT-013-T03, T04 (specs/281-out-013-frame-pacing): the gate's rules, and the acceptance
// model: a simulated main thread with an injected clock, a 120 Hz device loop and an external output that needs 100 ms
// per frame (OUT-013-S1 to S3). No wall clock anywhere.
import Dispatch
import FrameTiming
import XCTest

/// A discrete-event model of one main thread that serves the device's loop (HUD, controls, probes) and the external
/// output's display link. The output completes each submitted frame `outputLatency` after its encode (GPU or display
/// behind); completions arrive off the main thread.
private struct PacingSimulation {
    enum Policy {
        /// OUT-013: ask the gate; a full output drops the tick.
        case gate
        /// The control: wait on the main thread until a slot frees (what a semaphore or a blocking drawable does).
        case blocking
    }

    struct Result {
        var ticks = 0
        var maxDeviceLateness: Double = 0
        var deviceTicks = 0
        var maxPendingFirstSecond = 0
        var maxPending = 0
        var counts = OutputPacingCounts()
    }

    var deviceRate: Double = 120
    var outputRate: Double = 60
    var outputLatency: Double = 0.100
    var encodeCost: Double = 0.001
    var deviceCost: Double = 0.0002
    var duration: Double = 10

    func run(_ policy: Policy, gate: OutputFrameGate = OutputFrameGate()) -> Result {
        var result = Result()
        var pending: [Double] = []   // completion times of frames in flight
        var busyUntil: Double = 0
        var deviceIndex = 0
        var outputIndex = 0
        func completeDue(at time: Double) {
            while let first = pending.first, first <= time {
                pending.removeFirst()
                gate.complete()
            }
        }
        while true {
            let deviceTime: Double = Double(deviceIndex) / deviceRate
            let outputTime: Double = Double(outputIndex) / outputRate
            guard deviceTime < duration || outputTime < duration else { break }
            if deviceTime <= outputTime && deviceTime < duration {
                let start: Double = max(deviceTime, busyUntil)
                completeDue(at: start)
                result.maxDeviceLateness = max(result.maxDeviceLateness, start - deviceTime)
                result.deviceTicks += 1
                busyUntil = start + deviceCost
                deviceIndex += 1
            } else {
                var start: Double = max(outputTime, busyUntil)
                completeDue(at: start)
                result.ticks += 1
                if policy == .blocking, gate.counts.inFlight >= gate.policy.maxFramesInFlight, let free = pending.first {
                    start = max(start, free)   // the main thread waits for the output
                    completeDue(at: start)
                }
                if gate.tryBegin() {
                    busyUntil = start + encodeCost
                    pending.append(busyUntil + outputLatency)
                } else {
                    busyUntil = start
                }
                outputIndex += 1
            }
            result.maxPending = max(result.maxPending, pending.count)
            if min(deviceTime, outputTime) < 1 { result.maxPendingFirstSecond = result.maxPending }
        }
        result.counts = gate.counts
        return result
    }
}

final class OutputFramePacingTests: XCTestCase {
    // MARK: - The gate (OUT-013-T03)

    func testTheGateBoundsFramesInFlightAndCountsEachDrop() {
        let gate = OutputFrameGate()
        XCTAssertTrue(gate.tryBegin())
        XCTAssertTrue(gate.tryBegin())
        XCTAssertFalse(gate.tryBegin(), "two in flight: the third tick is dropped")
        XCTAssertEqual(gate.counts.inFlight, 2)
        gate.complete()
        XCTAssertTrue(gate.tryBegin())
        gate.abandon()   // no drawable came
        var expected = OutputPacingCounts()
        expected.begun = 3
        expected.completed = 1
        expected.droppedInFlight = 1
        expected.droppedNoDrawable = 1
        expected.inFlight = 1
        expected.maxInFlight = 2
        XCTAssertEqual(gate.counts, expected)
        XCTAssertEqual(gate.counts.dropped, 2)
    }

    func testStrayCompletionsNeverGoBelowZero() {
        let gate = OutputFrameGate()
        gate.complete()
        gate.abandon()
        XCTAssertEqual(gate.counts, OutputPacingCounts())
    }

    func testASlowDrawableWaitSkipsExactlyTheNextTick() {
        let gate = OutputFrameGate()
        gate.noteDrawableWait(0.004, refreshInterval: 1.0 / 60)   // under half a refresh interval
        XCTAssertFalse(gate.isBackingOff)
        gate.noteDrawableWait(0.010, refreshInterval: 1.0 / 60)   // over half
        XCTAssertTrue(gate.isBackingOff)
        XCTAssertFalse(gate.tryBegin())
        XCTAssertTrue(gate.tryBegin(), "one tick only")
        XCTAssertEqual(gate.counts.droppedBackOff, 1)
        XCTAssertEqual(gate.counts.begun, 1)
    }

    func testThePolicyIsClamped() {
        XCTAssertEqual(OutputPacingPolicy(maxFramesInFlight: 0).maxFramesInFlight, 1)
        XCTAssertEqual(OutputPacingPolicy(maxFramesInFlight: 9).maxFramesInFlight, 3)
        XCTAssertEqual(OutputPacingPolicy.standard.maxFramesInFlight, 2)
    }

    func testConcurrentCompletionsKeepTheCountsConsistent() {
        let gate = OutputFrameGate(policy: OutputPacingPolicy(maxFramesInFlight: 3))
        DispatchQueue.concurrentPerform(iterations: 2_000) { (_: Int) in
            if gate.tryBegin() { gate.complete() }
        }
        let counts = gate.counts
        XCTAssertEqual(counts.begun + counts.droppedInFlight, 2_000)
        XCTAssertEqual(counts.completed, counts.begun)
        XCTAssertEqual(counts.inFlight, 0)
        XCTAssertLessThanOrEqual(counts.maxInFlight, 3)
    }

    // MARK: - Acceptance model (OUT-013-T04; S1-S3)

    /// A 100 ms external output against a 120 Hz device loop for 10 simulated seconds.
    func testASlowExternalOutputDoesNotDelayTheDeviceLoop() {
        let result = PacingSimulation().run(.gate)
        XCTAssertEqual(result.deviceTicks, 1_200)
        XCTAssertLessThanOrEqual(result.maxDeviceLateness, 0.001, "S1: no device tick late beyond 1 ms")
        XCTAssertLessThanOrEqual(result.counts.maxInFlight, 2, "S2: frames in flight bounded")
        XCTAssertLessThanOrEqual(result.maxPending, 2)
        XCTAssertEqual(result.maxPendingFirstSecond, result.maxPending, "S2: no depth grows after the first second")
        XCTAssertEqual(result.counts.begun + result.counts.droppedInFlight + result.counts.droppedBackOff, result.ticks,
                       "S3: every tick either rendered or counted as dropped")
        XCTAssertGreaterThan(result.counts.droppedInFlight, 300, "the slow output drops most of its 600 ticks")
        // Two slots, each free again 101 ms after its tick, reused at the next 60 Hz tick (7 ticks): 2 frames per ~117 ms.
        XCTAssertGreaterThanOrEqual(result.counts.begun, 160, "the output still gets every frame it can take")
    }

    /// The control: waiting for a slot on the main thread delays the device loop by most of the output's latency, so
    /// the model can tell the two designs apart.
    func testTheBlockingControlStallsTheDeviceLoop() {
        let result = PacingSimulation().run(.blocking)
        XCTAssertGreaterThanOrEqual(result.maxDeviceLateness, 0.050)
        XCTAssertEqual(result.counts.droppedInFlight, 0)
    }

    /// A fast output (well within its refresh) is never throttled by the gate.
    func testAFastOutputDropsNothing() {
        var simulation = PacingSimulation()
        simulation.outputLatency = 0.008
        let result = simulation.run(.gate)
        XCTAssertEqual(result.counts.dropped, 0)
        XCTAssertEqual(result.counts.begun, result.ticks)
        XCTAssertLessThanOrEqual(result.maxDeviceLateness, 0.001)
    }
}
