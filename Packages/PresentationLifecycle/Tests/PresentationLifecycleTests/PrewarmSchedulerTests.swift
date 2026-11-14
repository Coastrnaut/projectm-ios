// PrewarmSchedulerTests.swift — PERF-005-T05, T07: the roadmap acceptance "Queue cancellation releases stale work
// and respects memory budget" with heavy fake assets of known sizes and a live-buffer counter, plus the frame
// guarantees (executor spy, pauses, settle delay, Low Power, preset forwarding, memory pressure). Injected
// executor, clock and memory accounting; no wall clock.
import Dispatch
import Foundation
import PresentationLifecycle
import XCTest

/// Counts fake decoded buffers alive right now (each buffer increments on init, decrements on deinit).
final class LiveBufferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func add(_ delta: Int) { lock.lock(); value += delta; lock.unlock() }
}

final class FakeBuffer {
    let bytes: [UInt8]
    let counter: LiveBufferCounter
    init(size: Int, counter: LiveBufferCounter) {
        bytes = [UInt8](repeating: 1, count: size)   // a real allocation of the stated size
        self.counter = counter
        counter.add(1)
    }
    deinit { counter.add(-1) }
}

/// A loader of heavy fake assets: sizes by key id, a hook in the middle of each load, a graphics step, and a
/// record of the thread each load ran on.
final class FakeLoader: PrewarmLoading, @unchecked Sendable {
    let counter = LiveBufferCounter()
    private let lock = NSLock()
    private var sizesValue: [String: Int]
    private var loadedValue: [String] = []
    private var mainThreadLoads = 0
    private var graphicsStepsValue = 0
    /// Called after the decode and before the graphics step (the item is "in flight").
    var midLoad: ((PrewarmItem) -> Void)?

    init(sizes: [String: Int]) { sizesValue = sizes }

    var loaded: [String] { lock.lock(); defer { lock.unlock() }; return loadedValue }
    var loadsOnMainThread: Int { lock.lock(); defer { lock.unlock() }; return mainThreadLoads }
    var graphicsSteps: Int { lock.lock(); defer { lock.unlock() }; return graphicsStepsValue }

    func load(_ item: PrewarmItem, context: PrewarmLoadContext) -> PrewarmLoadResult {
        lock.lock()
        loadedValue.append(item.key.id)
        if Thread.isMainThread { mainThreadLoads += 1 }
        let size = sizesValue[item.key.id] ?? 0
        lock.unlock()
        guard size <= context.maxBytes else { return .refused }
        let buffer = FakeBuffer(size: size, counter: counter)   // the "decode"
        midLoad?(item)
        let uploaded: Bool? = context.graphicsStep { () -> Bool in
            lock.lock()
            graphicsStepsValue += 1
            lock.unlock()
            return true
        }
        guard uploaded != nil else { return .refused }   // cancelled or suspended before the GPU step
        return .loaded(bytes: size, payload: buffer)
    }
}

/// Holds jobs until the test runs them, each on a background thread (never the main thread).
final class SpyExecutor: PrewarmExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [@Sendable () -> Void] = []
    private let worker = DispatchQueue(label: "SpyExecutor worker")

    var pending: Int { lock.lock(); defer { lock.unlock() }; return jobs.count }

    func execute(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        jobs.append(work)
        lock.unlock()
    }

    /// Runs the oldest job on the worker thread and waits for it. False when none.
    @discardableResult
    func runNext() -> Bool {
        lock.lock()
        guard !jobs.isEmpty else { lock.unlock(); return false }
        let job = jobs.removeFirst()
        lock.unlock()
        let done = DispatchSemaphore(value: 0)
        worker.async {
            job()
            done.signal()
        }
        done.wait()
        return true
    }

    func runAll() { while runNext() {} }
}

/// A clock the test advances by hand.
final class ManualClock: PrewarmClock, @unchecked Sendable {
    final class Token: PrewarmClockToken, @unchecked Sendable {
        let lock = NSLock()
        var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    private let lock = NSLock()
    private var now: Duration = .zero
    private var scheduled: [(due: Duration, token: Token, action: @Sendable () -> Void)] = []
    private(set) var scheduleCalls = 0

    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any PrewarmClockToken {
        let token = Token()
        lock.lock()
        scheduleCalls += 1
        scheduled.append((now + delay, token, action))
        lock.unlock()
        return token
    }

    func advance(by delta: Duration) {
        lock.lock()
        now += delta
        let due = scheduled.filter { $0.due <= now }
        scheduled.removeAll { $0.due <= now }
        lock.unlock()
        for entry in due where !entry.token.isCancelled { entry.action() }
    }
}

final class PrewarmSchedulerTests: XCTestCase {
    private let mb = 1024 * 1024
    private let settle: Duration = .milliseconds(500)

    private func item(_ id: String, rank: Int) -> PrewarmItem {
        PrewarmItem(key: PrewarmKey(kind: .photo, id: id), rank: rank, source: URL(fileURLWithPath: "/fake/\(id)"))
    }

    private func key(_ id: String) -> PrewarmKey { PrewarmKey(kind: .photo, id: id) }

    private func make(budget: Int, sizes: [String: Int]) -> (PrewarmScheduler, FakeLoader, SpyExecutor, ManualClock) {
        let loader = FakeLoader(sizes: sizes)
        let executor = SpyExecutor()
        let clock = ManualClock()
        let scheduler = PrewarmScheduler(budgetBytes: budget, loader: loader, executor: executor, clock: clock, settleDelay: settle)
        return (scheduler, loader, executor, clock)
    }

    // MARK: Acceptance (PERF-005-S1, S2)

    /// Cues A → B → C. A is live; the plan warms B (next) and C (after). Mid-way through B's load the performer
    /// jumps to C: B's work is cancelled, its decoded buffer released (the counter returns to baseline), C's
    /// cached picture becomes live, and held bytes never exceed the budget.
    func testJumpFromAToCMidPrewarmCancelsBAndReleasesItsBuffers() {
        let sizes = ["A": 30 * mb, "B1": 24 * mb, "B2": 16 * mb, "C": 20 * mb, "D": 12 * mb]
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: sizes)
        let baseline = loader.counter.count
        XCTAssertEqual(baseline, 0)

        // Cue A live: next is B (two photos: slideshow slides), then C.
        scheduler.plan([item("B1", rank: 0), item("B2", rank: 0), item("C", rank: 1)], live: [key("A")])
        XCTAssertEqual(executor.pending, 0, "nothing starts before the settle delay")
        clock.advance(by: settle)
        XCTAssertEqual(scheduler.inFlightKey, key("B1"), "the next cue first")

        // While B1 is decoded (in flight), the performer jumps to C: the new plan is C live, D next.
        loader.midLoad = { (loading: PrewarmItem) in
            guard loading.key == self.key("B1") else { return }
            scheduler.plan([self.item("D", rank: 0)], live: [self.key("C")])
            XCTAssertEqual(scheduler.queuedKeys, [self.key("D")], "B2 and C are dropped from the queue")
        }
        executor.runNext()   // B1's load: cancelled mid-way; its graphics step is refused, its buffer released
        loader.midLoad = nil
        XCTAssertEqual(loader.counter.count, baseline, "B1's decoded buffer is released")
        XCTAssertFalse(scheduler.isCached(key("B1")))
        XCTAssertEqual(scheduler.stats.cancelled, 1)
        XCTAssertEqual(loader.graphicsSteps, 0, "the cancelled item never reached its GPU step")

        clock.advance(by: settle)
        executor.runAll()
        XCTAssertEqual(loader.loaded, ["B1", "D"], "B2 and C never started (C is live now)")
        XCTAssertTrue(scheduler.isCached(key("D")))
        XCTAssertEqual(loader.counter.count, 1, "only D's buffer is held")
        XCTAssertLessThanOrEqual(scheduler.stats.peakHeldBytes, 64 * mb)

        // Moving on releases D when the plan no longer names it.
        scheduler.plan([], live: [key("D")])
        XCTAssertTrue(scheduler.isCached(key("D")), "the live scene's asset is never released by a replan")
        scheduler.plan([], live: [])
        XCTAssertEqual(loader.counter.count, baseline, "every prewarmed buffer is released: back to baseline")
        XCTAssertEqual(scheduler.heldBytes, 0)
    }

    /// The budget holds across a sequence that overflows it; the live scene's entry is never evicted.
    func testHeldBytesNeverExceedTheBudgetAndLiveAssetsSurvive() {
        let sizes = ["L": 40 * mb, "N": 30 * mb, "M": 30 * mb, "X": 200 * mb]
        let (scheduler, loader, executor, clock) = make(budget: 96 * mb, sizes: sizes)
        scheduler.plan([item("L", rank: 0), item("N", rank: 1)], live: [])
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertEqual(scheduler.heldBytes, 70 * mb)

        // L becomes live (the performer stepped to it); M (rank 0) and an oversized X are planned.
        scheduler.plan([item("M", rank: 0), item("N", rank: 1), item("X", rank: 1)], live: [key("L")])
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertTrue(scheduler.isCached(key("L")), "the live asset is never evicted")
        XCTAssertTrue(scheduler.isCached(key("M")), "N (rank 1, not more important) was evicted for M")
        XCTAssertFalse(scheduler.isCached(key("N")))
        XCTAssertFalse(scheduler.isCached(key("X")), "an item larger than the budget is never kept")
        XCTAssertEqual(scheduler.heldBytes, 70 * mb)
        XCTAssertLessThanOrEqual(scheduler.stats.peakHeldBytes, 96 * mb)
        XCTAssertEqual(loader.counter.count, 2, "evicted and refused buffers are released")
    }

    // MARK: Frame guarantees (PERF-005-S3, S4, S6)

    func testLoadsRunOnlyOnTheExecutorNeverOnTheMainThread() {
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: ["B": mb, "C": mb])
        XCTAssertTrue(Thread.isMainThread)
        scheduler.plan([item("B", rank: 0), item("C", rank: 1)], live: [])
        clock.advance(by: settle)
        XCTAssertTrue(loader.loaded.isEmpty, "planning and settling start no load on the calling thread")
        XCTAssertEqual(executor.pending, 1, "one item at a time, handed to the executor")
        executor.runAll()
        XCTAssertEqual(loader.loaded, ["B", "C"])
        XCTAssertEqual(loader.loadsOnMainThread, 0)
    }

    func testNothingStartsWhileSuspendedOrHotAndSuspensionReleasesEntries() {
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: ["B": mb, "C": mb, "A": mb])
        scheduler.plan([item("B", rank: 0)], live: [key("A")])
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertTrue(scheduler.isCached(key("B")))

        scheduler.pause(.presentation)
        XCTAssertFalse(scheduler.isCached(key("B")), "suspension releases non-live entries")
        XCTAssertEqual(loader.counter.count, 0)
        scheduler.plan([item("C", rank: 0)], live: [key("A")])
        clock.advance(by: .seconds(10))
        XCTAssertEqual(executor.pending, 0, "nothing starts while the app cannot present")

        scheduler.pause(.thermal)
        scheduler.resume(.presentation)
        clock.advance(by: .seconds(10))
        XCTAssertEqual(executor.pending, 0, "nothing starts at a serious or critical thermal state")

        scheduler.resume(.thermal)
        XCTAssertEqual(executor.pending, 0, "resuming waits for the settle delay again")
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertEqual(loader.loaded, ["B", "C"])
    }

    func testSuspensionDuringALoadRefusesItsGraphicsStep() {
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: ["B": mb])
        scheduler.plan([item("B", rank: 0)], live: [])
        clock.advance(by: settle)
        loader.midLoad = { (_: PrewarmItem) in scheduler.pause(.presentation) }
        executor.runNext()
        XCTAssertEqual(loader.graphicsSteps, 0, "no GPU work once presentation is lost")
        XCTAssertFalse(scheduler.isCached(key("B")))
        XCTAssertEqual(loader.counter.count, 0)
        loader.midLoad = nil
        scheduler.resume(.presentation)
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertTrue(scheduler.isCached(key("B")), "on resume the remembered plan runs again")
    }

    func testANewerPlanRestartsTheSettleDelay() {
        let (scheduler, _, executor, clock) = make(budget: 64 * mb, sizes: ["B": mb, "C": mb])
        scheduler.plan([item("B", rank: 0)], live: [])
        clock.advance(by: .milliseconds(400))
        scheduler.plan([item("C", rank: 0)], live: [])
        clock.advance(by: .milliseconds(400))
        XCTAssertEqual(executor.pending, 0)
        clock.advance(by: .milliseconds(100))
        XCTAssertEqual(executor.pending, 1)
        XCTAssertEqual(scheduler.inFlightKey, key("C"))
    }

    func testLowPowerKeepsOnlyTheNextCue() {
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: ["B": mb, "C": mb])
        scheduler.lowPower = true
        scheduler.plan([item("B", rank: 0), item("C", rank: 1)], live: [])
        clock.advance(by: settle)
        executor.runAll()
        XCTAssertEqual(loader.loaded, ["B"])
        scheduler.lowPower = false
        executor.runAll()
        XCTAssertEqual(loader.loaded, ["B", "C"])
    }

    func testPresetPicksAreForwardedAtOnceWithoutAnyDelay() {
        let (scheduler, _, executor, clock) = make(budget: 64 * mb, sizes: [:])
        var forwarded: [String] = []
        scheduler.forwardPresets(["random", "next"]) { forwarded = ["random", "next"] }
        XCTAssertEqual(forwarded, ["random", "next"], "the existing warm-up is called before forwardPresets returns")
        XCTAssertEqual(clock.scheduleCalls, 0, "the scheduler adds no delay: PresetWarmUpController keeps its own 2.5 s")
        XCTAssertEqual(executor.pending, 0)
        XCTAssertEqual(scheduler.lastPresetPicks, ["random", "next"])
        XCTAssertEqual(scheduler.stats.presetRequests, 1)
    }

    func testMemoryPressureReleasesEverythingButLiveAndTakeHandsOver() {
        let (scheduler, loader, executor, clock) = make(budget: 64 * mb, sizes: ["B": 3 * mb, "C": 5 * mb])
        scheduler.plan([item("B", rank: 0), item("C", rank: 1)], live: [])
        clock.advance(by: settle)
        executor.runAll()
        let taken = scheduler.take(key("B"))
        XCTAssertEqual(taken?.bytes, 3 * mb)
        XCTAssertEqual(scheduler.heldBytes, 5 * mb, "a taken entry leaves the accounting")
        let freed = scheduler.releaseForMemoryPressure()
        XCTAssertEqual(freed.bytes, 5 * mb)
        XCTAssertEqual(freed.items, 1)
        XCTAssertEqual(loader.counter.count, 1, "only the live scene's taken buffer remains")
        XCTAssertNil(scheduler.take(key("C")))
    }

    func testLookaheadAndBudget() {
        XCTAssertEqual(PrewarmLookahead.upcoming(activeIndex: nil, count: 3), [0, 1], "standby: cue 1 next")
        XCTAssertEqual(PrewarmLookahead.upcoming(activeIndex: 0, count: 3), [1, 2])
        XCTAssertEqual(PrewarmLookahead.upcoming(activeIndex: 1, count: 3), [2])
        XCTAssertEqual(PrewarmLookahead.upcoming(activeIndex: 2, count: 3), [], "no wrap")
        XCTAssertEqual(PrewarmLookahead.upcoming(activeIndex: nil, count: 0), [])
        let gb: UInt64 = 1024 * 1024 * 1024
        XCTAssertEqual(PrewarmBudget.bytes(physicalMemory: 3 * gb), 48 * mb)
        XCTAssertEqual(PrewarmBudget.bytes(physicalMemory: 6 * gb), 96 * mb)
        XCTAssertEqual(PrewarmBudget.bytes(physicalMemory: 16 * gb), 192 * mb)
        let duplicated = PrewarmItem.normalized([item("C", rank: 1), item("B", rank: 0), item("C", rank: 0)])
        XCTAssertEqual(duplicated.map(\.key.id), ["B", "C"])
        XCTAssertEqual(duplicated.map(\.rank), [0, 0], "a key keeps its most important rank")
    }
}
