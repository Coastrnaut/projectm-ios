// PERF-014-T02: the plain-Swift fault model (PERF-014-R1, R2, R5, R6, R13, R15; S3). No Metal, no
// clock: ticks are given. Runs on the macOS host and in the Linux shape.
import Compositor
import XCTest

final class RenderHealthTests: XCTestCase {
    private let policy = RenderRecoveryPolicy.standard

    /// Drives a part that fails at every run from tick 0 and returns the ticks at which it ran again.
    private func retryTicks(until last: UInt64) -> (ticks: [UInt64], counted: Int, state: RenderRetryState) {
        var state = RenderRetryState()
        var counted = state.fault(atTick: 0, policy: policy) ? 1 : 0
        var ticks: [UInt64] = []
        for tick in UInt64(1)...last {
            if state.isRetryDue(atTick: tick) {
                state.beginRetry(atTick: tick)
                ticks.append(tick)
                if state.fault(atTick: tick, policy: policy) { counted += 1 }   // the retry failed
            } else if state.isHolding {
                XCTAssertFalse(state.fault(atTick: tick, policy: policy), "faults while waiting are coalesced")
            }
        }
        return (ticks, counted, state)
    }

    func testRetriesBackOffThenGiveUp() {
        XCTAssertEqual([0, 1, 2, 3].map { policy.delay(afterRetries: $0) }, [30, 60, 120, 240])
        let run = retryTicks(until: 450 + 1_000)
        XCTAssertEqual(run.ticks, [30, 90, 210, 450], "S3: retries at +30, +90, +210, +450 and none in the next 1,000 ticks")
        XCTAssertEqual(run.counted, 5, "the first fault and four failed retries")
        XCTAssertTrue(run.state.hasGivenUp)
        XCTAssertTrue(run.state.isHolding)
    }

    func testRecoveryCountsOnlyWorkEncodedAfterTheRetryBegan() {
        var state = RenderRetryState()
        state.fault(atTick: 10, policy: policy)
        XCTAssertFalse(state.succeeded(encodedAtTick: 9), "older work never ends a wait")
        XCTAssertFalse(state.isRetryDue(atTick: 39))
        XCTAssertTrue(state.isRetryDue(atTick: 40))
        state.beginRetry(atTick: 40)
        XCTAssertFalse(state.isHolding, "a retrying part runs")
        XCTAssertFalse(state.succeeded(encodedAtTick: 38), "a frame from before the retry is not a recovery")
        XCTAssertTrue(state.succeeded(encodedAtTick: 40))
        XCTAssertEqual(state.phase, .ok)
        XCTAssertEqual(state.retriesUsed, 0, "a recovery restores the budget")
        XCTAssertFalse(state.succeeded(encodedAtTick: 41), "healthy work is not a recovery")
    }

    func testResetRetriesAtOnceWithAFreshBudget() {
        var state = retryTicks(until: 500).state
        XCTAssertTrue(state.hasGivenUp)
        state.reset(atTick: 600)
        XCTAssertEqual(state.phase, .retrying(since: 600))
        XCTAssertEqual(state.retriesUsed, 0)
        XCTAssertTrue(state.fault(atTick: 600, policy: policy), "a failed reset retry counts")
        XCTAssertTrue(state.isRetryDue(atTick: 630), "and backs off from the first delay again")
        var healthy = RenderRetryState()
        healthy.reset(atTick: 5)
        XCTAssertEqual(healthy.phase, .ok, "a healthy part stays healthy")
    }

    func testZeroRetriesGivesUpAtTheFirstFailedRetry() {
        let none = RenderRecoveryPolicy(firstDelayTicks: 0, maxRetries: -1)
        XCTAssertEqual(none.firstDelayTicks, 1)
        XCTAssertEqual(none.maxRetries, 0)
        var state = RenderRetryState()
        state.fault(atTick: 0, policy: none)
        state.beginRetry(atTick: 1)
        XCTAssertTrue(state.fault(atTick: 1, policy: none))
        XCTAssertTrue(state.hasGivenUp)
    }

    func testStateDerivation() {
        var waiting = RenderRetryState(), gaveUp = RenderRetryState()
        waiting.fault(atTick: 0, policy: policy)
        gaveUp = retryTicks(until: 500).state
        let ok = RenderRetryState()
        XCTAssertEqual(RenderHealth.state(layers: [ok, ok], visual: ok), .healthy)
        XCTAssertEqual(RenderHealth.state(layers: [ok, waiting], visual: ok), .recovering)
        XCTAssertEqual(RenderHealth.state(layers: [ok, ok], visual: waiting), .recovering, "a GPU back-off draws black, not the placeholder")
        XCTAssertEqual(RenderHealth.state(layers: [gaveUp, ok], visual: ok), .degraded)
        XCTAssertEqual(RenderHealth.state(layers: [gaveUp, waiting], visual: ok), .degraded)
        XCTAssertEqual(RenderHealth.state(layers: [gaveUp, gaveUp], visual: ok), .placeholder)
        XCTAssertEqual(RenderHealth.state(layers: [ok], visual: gaveUp), .placeholder)
        XCTAssertEqual(RenderHealth.state(layers: [RenderRetryState](), visual: ok), .healthy, "no layers is not a failure")
    }

    func testRecordAndTextCarryIdentifiersAndCountsOnly() {
        var health = RenderHealth()
        XCTAssertTrue(health.isPristine)
        XCTAssertEqual(health.debugValue, "healthy none faults 0 recoveries 0 tick -")
        let start = health.revision
        health.recordFault(.layerPrepareFailed, atTick: 30)
        health.setState(.recovering)
        health.setState(.recovering)
        XCTAssertEqual(health.revision, start + 2, "an unchanged state does not bump the revision")
        health.recordRecovery()
        XCTAssertEqual(health.faultCount, 1)
        XCTAssertEqual(health.lastReason, .layerPrepareFailed)
        XCTAssertEqual(health.lastFaultTick, 30)
        XCTAssertEqual(health.summary(visual: "photo"), "photo recovering layerPrepareFailed faults 1 recoveries 1 tick 30")
        XCTAssertFalse(health.isPristine)
    }

    func testInjectionParsing() {
        let parsed = RenderFaultInjection.parse("prepare:photo, picture:video,render:spectrum,gpu:gpuTimeout,preset:2,present,bogus,gpu:presetLoadFailed,prepare:")
        XCTAssertEqual(parsed.failingPrepare, ["photo"])
        XCTAssertEqual(parsed.missingPictures, ["video"])
        XCTAssertEqual(parsed.failingRender, ["spectrum"])
        XCTAssertEqual(parsed.gpuFault, .gpuTimeout, "a non-GPU reason is not a GPU fault")
        XCTAssertEqual(parsed.failPresetLoads, 2)
        XCTAssertTrue(parsed.failPresentation)
        XCTAssertEqual(RenderFaultInjection.parse("preset").failPresetLoads, 1)
        XCTAssertTrue(RenderFaultInjection.parse("").isEmpty)
        XCTAssertTrue(RenderFaultReason.allCases.allSatisfy { !$0.rawValue.contains(" ") }, "identifiers, no prose")
    }
}
