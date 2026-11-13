// OSC-009-T02: the token-bucket limiter with a fake clock (OSC-009-R1, R2, R5 to R9; contract L1).
// Every time is an argument, so the counts are exact. Budget: well under 1 s.
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class OSCRateLimiterTests: XCTestCase {
    private let ms: UInt64 = 1_000_000
    private let a = OSCSourceID(rawValue: 1), b = OSCSourceID(rawValue: 2)
    private let x: ParameterID = "test.x", y: ParameterID = "test.y"

    private func admitted(_ limiter: inout OSCRateLimiter, _ source: OSCSourceID, at now: UInt64, times: Int) -> Int {
        (0..<times).reduce(0) { n, _ in n + (limiter.admitDatagram(from: source, now: now) ? 1 : 0) }
    }

    func testDefaultsAreTheRecordedNumbers() {
        let c = OSCRateLimitConfiguration.default
        XCTAssertEqual(c.perSource, OSCRateLimit(perSecond: 200, burst: 50))
        XCTAssertEqual(c.global, OSCRateLimit(perSecond: 500, burst: 100))
        XCTAssertEqual(c.perTarget, OSCRateLimit(perSecond: 60, burst: 10))
        XCTAssertEqual(c.maximumSources, 16)
        XCTAssertEqual(c.maximumTargets, 64)
        XCTAssertEqual(OSCRateLimit(perSecond: 0, burst: 5_000), OSCRateLimit(perSecond: 1, burst: 1_000), "clamped")
    }

    func testBurstThenExactRefill() {
        var limiter = OSCRateLimiter()
        XCTAssertEqual(admitted(&limiter, a, at: 0, times: 80), 50, "the burst at one instant")
        XCTAssertEqual(admitted(&limiter, a, at: 4 * ms, times: 5), 0, "200/s: no token before 5 ms")
        XCTAssertEqual(admitted(&limiter, a, at: 5 * ms, times: 5), 1, "exactly one token at 5 ms")
        XCTAssertEqual(admitted(&limiter, a, at: 55 * ms, times: 20), 10, "50 ms more refill 10 tokens")
    }

    func testClockJumpRefillsOnlyToTheBurstAndBackwardsRefillsNothing() {
        var limiter = OSCRateLimiter()
        _ = admitted(&limiter, a, at: 0, times: 50)
        XCTAssertEqual(admitted(&limiter, a, at: 10 * 3_600 * 1_000 * ms, times: 100), 50, "hours later: burst only, no overflow")
        XCTAssertEqual(admitted(&limiter, a, at: 1 * ms, times: 10), 0, "a clock that went backwards refills nothing")

        var bucket = OSCTokenBucket(limit: OSCRateLimit(perSecond: 1_000_000, burst: 1_000), now: 0)
        bucket.refill(now: .max)
        XCTAssertEqual(bucket.tokens, 1_000)
    }

    func testSourcesAreIsolated() {
        var limiter = OSCRateLimiter()
        XCTAssertEqual(admitted(&limiter, a, at: 0, times: 60), 50)
        XCTAssertEqual(admitted(&limiter, b, at: 0, times: 60), 50, "another source keeps its own bucket")
    }

    func testGlobalCapAcrossSourcesAndDroppedDatagramsSpendNoGlobalToken() {
        var limiter = OSCRateLimiter()
        // 4 sources × 50 burst = 200 > global burst 100.
        let total = (1...4).reduce(0) { n, s in n + admitted(&limiter, OSCSourceID(rawValue: UInt64(s)), at: 0, times: 50) }
        XCTAssertEqual(total, 100, "global burst")
        // One second later: global refilled to 100 (500/s capped at the burst), sources to 50 each.
        XCTAssertEqual(admitted(&limiter, a, at: 1_000 * ms, times: 200), 50, "the source limit binds first")
        XCTAssertEqual(admitted(&limiter, b, at: 1_000 * ms, times: 200), 50, "a's 150 refused datagrams spent no global token")
        XCTAssertEqual(admitted(&limiter, OSCSourceID(rawValue: 3), at: 1_000 * ms, times: 200), 0, "the global bucket is empty")

        // Steady state over 1 s: at most burst + rate × 1 s in all.
        var steady = OSCRateLimiter()
        var passed = 0
        for t in 0..<1_000 {
            for s in 1...8 { passed += admitted(&steady, OSCSourceID(rawValue: UInt64(s)), at: UInt64(t) * ms, times: 3) }
        }
        XCTAssertLessThanOrEqual(passed, 100 + 500)
        XCTAssertGreaterThanOrEqual(passed, 500, "the global rate is reached")
    }

    func testTargetLimitAndIsolation() {
        var limiter = OSCRateLimiter()
        var applied = 0
        for i in 0..<30 where limiter.submit(Double(i), to: x, now: 0).decision == .applyNow { applied += 1 }
        XCTAssertEqual(applied, 10, "target burst")
        XCTAssertEqual(limiter.heldValue(for: x), 29, "the newest value is held")
        XCTAssertEqual(limiter.submit(1, to: y, now: 0).decision, .applyNow, "another target is unaffected")
    }

    func testCoalescingDeliversOnlyTheLatestAtTheNextToken() throws {
        var limiter = OSCRateLimiter()
        for i in 0..<10 { _ = limiter.submit(Double(i), to: x, now: 0) }
        XCTAssertEqual(limiter.submit(100, to: x, now: 0).decision, .held)
        XCTAssertEqual(limiter.submit(101, to: x, now: 0).decision, .held)
        let wait = try XCTUnwrap(limiter.nextDue(now: 0))
        XCTAssertEqual(wait, 16_666_667, "60/s: ceil(1e9 / 60) ns")
        XCTAssertTrue(limiter.takeDue(now: wait - 1).isEmpty, "not before the token")
        let due = limiter.takeDue(now: wait)
        XCTAssertEqual(due.map { $0.0 }, [x])
        XCTAssertEqual(due.map { $0.1 }, [101], "only the latest value")
        XCTAssertNil(limiter.nextDue(now: wait))
        XCTAssertEqual(limiter.heldCount, 0)
    }

    func testDirectApplyDropsAnOlderHeldValue() {
        var limiter = OSCRateLimiter()
        for i in 0..<11 { _ = limiter.submit(Double(i), to: x, now: 0) }
        XCTAssertEqual(limiter.heldValue(for: x), 10)
        XCTAssertEqual(limiter.submit(42, to: x, now: 20 * ms).decision, .applyNow)
        XCTAssertNil(limiter.heldValue(for: x), "the newer value replaced the held one")
        XCTAssertTrue(limiter.takeDue(now: 1_000 * ms).isEmpty)
    }

    func testEvictionAtTheCaps() {
        var limiter = OSCRateLimiter(configuration: OSCRateLimitConfiguration(maximumSources: 3, maximumTargets: 2))
        for s in 1...3 { _ = limiter.admitDatagram(from: OSCSourceID(rawValue: UInt64(s)), now: 0) }
        _ = limiter.admitDatagram(from: OSCSourceID(rawValue: 1), now: 0)        // 1 is now the most recent
        _ = limiter.admitDatagram(from: OSCSourceID(rawValue: 4), now: 0)        // evicts 2
        XCTAssertEqual(limiter.sourceCount, 3)
        XCTAssertFalse(limiter.tracks(OSCSourceID(rawValue: 2)))
        XCTAssertTrue(limiter.tracks(OSCSourceID(rawValue: 1)))

        for i in 0..<11 { _ = limiter.submit(Double(i), to: x, now: 0) }       // x holds 10
        _ = limiter.submit(1, to: y, now: 0)
        let result = limiter.submit(1, to: "test.z", now: 0)                     // evicts x, least recently used
        XCTAssertEqual(limiter.targetCount, 2)
        XCTAssertEqual(result.evicted?.0, x)
        XCTAssertEqual(result.evicted?.1, 10, "an evicted target's held value is handed back to apply")
        XCTAssertNil(limiter.heldValue(for: x))

        let full = OSCRateLimitConfiguration.default
        var big = OSCRateLimiter()
        for s in 0..<1_000 { _ = big.admitDatagram(from: OSCSourceID(rawValue: UInt64(s)), now: 0) }
        for t in 0..<1_000 { _ = big.submit(0, to: ParameterID("t.\(t)"), now: 0) }
        XCTAssertEqual(big.sourceCount, full.maximumSources)
        XCTAssertEqual(big.targetCount, full.maximumTargets)
    }

    func testResetClearsEverything() {
        var limiter = OSCRateLimiter()
        _ = admitted(&limiter, a, at: 0, times: 60)
        for i in 0..<11 { _ = limiter.submit(Double(i), to: x, now: 0) }
        limiter.reset()
        XCTAssertEqual(limiter.sourceCount + limiter.targetCount + limiter.heldCount, 0)
        XCTAssertEqual(admitted(&limiter, a, at: 0, times: 60), 50, "fresh, full buckets")
    }
}
