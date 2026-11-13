// PERF-006-T02, T14: the memory pressure recovery policy with fake responders and a test clock
// (PERF-006-R2 to R5, R14; PERF-006-S5). No wall clock: every time is an argument. Runs on the macOS
// host and on Linux.
import XCTest
@testable import PresentationLifecycle

@MainActor
final class MemoryPressureRecoveryTests: XCTestCase {
    /// Holds `held` bytes until released; records every call into a shared log.
    final class FakeStep: MemoryPressureResponder {
        let memoryPressureName: String
        let memoryPressureTier: MemoryPressureTier
        var held: Int
        let estimated: Bool
        var releases = 0
        var restores = 0
        var log: Log
        var onRelease: (() -> Void)?

        final class Log { var calls: [String] = [] }

        init(_ name: String, tier: MemoryPressureTier = .cache, held: Int = 0, estimated: Bool = false, log: Log) {
            memoryPressureName = name
            memoryPressureTier = tier
            self.held = held
            self.estimated = estimated
            self.log = log
        }

        var reclaimableBytes: Int { held }

        func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
            releases += 1
            log.calls.append("release \(memoryPressureName)")
            onRelease?()
            guard held > 0 else { return .none }
            defer { held = 0 }
            return MemoryPressureRelease(bytes: held, items: 1, bytesEstimated: estimated)
        }

        func restoreAfterMemoryPressure() {
            restores += 1
            log.calls.append("restore \(memoryPressureName)")
        }
    }

    func testCacheStepsRunInRegistrationOrderBeforeOptionalOnes() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery()
        let optional = FakeStep("warm-up", tier: .optional, log: log)
        let pool = FakeStep("pool", held: 100, log: log)
        let archive = FakeStep("archive", held: 20, log: log)
        recovery.register(optional)
        recovery.register(pool)
        recovery.register(archive)
        recovery.register(pool)   // repeat: ignored
        let report = recovery.handle(.critical, at: 0)
        XCTAssertEqual(log.calls, ["release pool", "release archive", "release warm-up"])
        XCTAssertEqual(report?.steps.map(\.name), ["pool", "archive", "warm-up"])
        XCTAssertEqual(report?.freedBytes, 120)
        XCTAssertEqual(recovery.snapshot.map(\.name), ["warm-up", "pool", "archive"])
    }

    func testASingleWarningRunsOnlyCacheStepsAndIsIdempotent() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60)
        let pool = FakeStep("pool", held: 4096, log: log)
        let warmUp = FakeStep("warm-up", tier: .optional, log: log)
        recovery.register(pool)
        recovery.register(warmUp)
        XCTAssertEqual(recovery.reclaimableBytes, 4096)
        let first = recovery.handle(.warning, at: 100)
        XCTAssertEqual(first?.escalated, false)
        XCTAssertEqual(first?.steps.map(\.name), ["pool"])
        XCTAssertEqual(first?.freedBytes, 4096)
        XCTAssertNil(first?.shedUntil)
        XCTAssertEqual(warmUp.releases, 0, "optional work is not shed for one warning")
        XCTAssertFalse(recovery.isShedding)

        let later = recovery.handle(.warning, at: 200)   // outside the window
        XCTAssertEqual(later?.escalated, false)
        XCTAssertEqual(later?.freedBytes, 0, "nothing left: the step frees 0 and does not fail")
        XCTAssertEqual(pool.releases, 2)
        XCTAssertEqual(recovery.recoveries, 2)
        XCTAssertEqual(recovery.totalFreedBytes, 4096)
    }

    func testARepeatInsideTheWindowEscalatesAndTheCoolDownRestoresOnce() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60)
        let warmUp = FakeStep("warm-up", tier: .optional, log: log)
        let pool = FakeStep("pool", log: log)   // held strongly: the recovery holds responders weakly
        recovery.register(pool)
        recovery.register(warmUp)
        recovery.handle(.warning, at: 10)
        let second = recovery.handle(.warning, at: 40)   // exactly at the window's end: a repeat
        XCTAssertEqual(second?.escalated, true)
        XCTAssertEqual(second?.steps.map(\.name), ["pool", "warm-up"])
        XCTAssertEqual(second?.shedUntil, 100)
        XCTAssertEqual(recovery.escalations, 1)

        let third = recovery.handle(.warning, at: 50)   // still a repeat: extends, does not shed twice
        XCTAssertEqual(third?.escalated, true)
        XCTAssertEqual(third?.steps.map(\.name), ["pool"])
        XCTAssertEqual(recovery.shedUntil, 110)
        XCTAssertEqual(warmUp.releases, 1)

        XCTAssertEqual(recovery.restoreIfDue(at: 100), [], "the extension moved the end")
        XCTAssertEqual(warmUp.restores, 0)
        XCTAssertEqual(recovery.restoreIfDue(at: 110), ["warm-up"])
        XCTAssertEqual(recovery.restoreIfDue(at: 500), [], "restored exactly once")
        XCTAssertEqual(warmUp.restores, 1)
        XCTAssertFalse(recovery.isShedding)
        XCTAssertEqual(recovery.restores, 1)
    }

    func testCriticalEscalatesAtOnceAndAWarningAfterTheWindowDoesNot() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60)
        let warmUp = FakeStep("warm-up", tier: .optional, log: log)
        recovery.register(warmUp)
        XCTAssertEqual(recovery.handle(.critical, at: 0)?.escalated, true)
        XCTAssertEqual(recovery.restoreIfDue(at: 60), ["warm-up"])
        XCTAssertEqual(recovery.handle(.warning, at: 31)?.escalated, false, "31 s after the last signal")
        XCTAssertEqual(warmUp.releases, 1)
    }

    func testASignalRaisedInsideAStepIsHandledAfterTheRunningOne() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery()
        let first = FakeStep("first", held: 1, log: log)
        let second = FakeStep("second", held: 2, log: log)
        var nested: MemoryPressureReport?? = .none
        first.onRelease = { [unowned recovery] in
            if first.releases == 1 { nested = recovery.handle(.warning, at: 1) }
        }
        recovery.register(first)
        recovery.register(second)
        var reports: [MemoryPressureReport] = []
        recovery.onReport = { (report: MemoryPressureReport) in reports.append(report) }
        let outer = recovery.handle(.warning, at: 0)
        XCTAssertEqual(nested, .some(nil), "the nested call is queued, not run inside")
        XCTAssertEqual(log.calls, ["release first", "release second", "release first", "release second"])
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first?.freedBytes, 3)
        XCTAssertEqual(outer?.escalated, true, "the queued repeat ran last and escalated")
        XCTAssertEqual(recovery.recoveries, 2)
    }

    func testReleasedRespondersAreSkippedAndUnregisteredOnesAreNotRestored() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery()
        var gone: FakeStep? = FakeStep("gone", held: 5, log: log)
        recovery.register(gone!)
        let kept = FakeStep("kept", tier: .optional, log: log)
        recovery.register(kept)
        gone = nil
        XCTAssertEqual(recovery.handle(.critical, at: 0)?.steps.map(\.name), ["kept"])
        recovery.unregister(kept)
        XCTAssertEqual(recovery.restoreIfDue(at: 1_000), [])
        XCTAssertEqual(kept.restores, 0)
        XCTAssertTrue(recovery.snapshot.isEmpty)
    }

    func testAnOptionalResponderRegisteredWhileSheddingIsShedAtOnce() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery(repeatWindowSeconds: 30, coolDownSeconds: 60)
        recovery.handle(.critical, at: 0)
        let late = FakeStep("late", tier: .optional, log: log)
        recovery.register(late)
        XCTAssertEqual(late.releases, 1)
        let cache = FakeStep("cache", log: log)
        recovery.register(cache)
        XCTAssertEqual(cache.releases, 0, "cache responders wait for the next signal")
        XCTAssertEqual(recovery.restoreIfDue(at: 60), ["late"])
        XCTAssertEqual(late.restores, 1)
    }

    func testTheSummaryCarriesNamesAndCountsOnly() {
        let log = FakeStep.Log()
        let recovery = MemoryPressureRecovery()
        let steps = [FakeStep("shared texture pool", held: 1_048_576, log: log),
                     FakeStep("preset warm-up context", held: 262_144, estimated: true, log: log),
                     FakeStep("preset archive cache", log: log)]
        steps.forEach(recovery.register)
        let report = recovery.handle(.warning, at: 0)
        XCTAssertEqual(report?.summary,
                       "warning escalated=no freed 1310720 B 2 items [shared texture pool 1048576 B 1; preset warm-up context ~262144 B 1; preset archive cache 0 B 0]")
        XCTAssertEqual(report?.freedItems, 2)
        XCTAssertEqual(recovery.lastReport, report)
        XCTAssertEqual(MemoryPressureRelease(bytes: -3, items: -1), .none, "negative inputs clamp to 0")
    }
}
