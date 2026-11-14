// PrewarmScheduler.swift — "Prioritize next likely scene assets without blocking active frame" (PERF-005-R1 to
// R10, R13; specs/179-perf-005-prewarm-scheduler, contracts/prewarm-scheduler.md; research PERF-005-D2, D4 to D6).
//
// * A plan lists media items in priority order (rank 0 = the next cue, rank 1 = the cue after it) and the live
//   scene's keys. `plan(_:live:)` replaces it: queued items it no longer names are dropped, the in-flight item
//   it no longer names is cancelled (its result is released when the load returns), and cached entries it no
//   longer names that the live scene does not use are released. Items it still names that are cached are kept
//   (their recency refreshed) and never loaded again; items the live scene already shows are never loaded.
// * Loads run one at a time on the injected executor (default: a serial queue at utility priority), never on
//   the caller's thread, and start only after the settle delay (injected clock; a newer plan restarts it) and
//   while no pause reason holds (presentation lost, thermal serious or critical).
// * A presentation pause cancels the in-flight item, releases every non-live entry and then waits for a running
//   graphics step to end: a loader does its GPU work inside `context.graphicsStep { }`, which refuses to start
//   once the item is cancelled or presentation is paused. On resume the remembered plan is queued again after
//   the settle delay.
// * Results are admitted to the budgeted `PrewarmCache` (rank-aware LRU, live keys pinned); a refused result is
//   released. `take` hands an entry to the live scene. A memory-pressure release drops every non-live entry and
//   the queue (the next plan starts again).
// * Preset picks are not loaded here: `forwardPresets` records them and calls the existing SC-104 warm-up path
//   synchronously, so its 2.5 s delay and behaviour are unchanged.
// State is guarded by one lock; payloads are dropped outside it. Plain Swift (Foundation and Dispatch): Linux.
import Dispatch
import Foundation

// MARK: - Seams

/// Runs prewarm loads off the caller's thread.
public protocol PrewarmExecutor: Sendable {
    func execute(_ work: @escaping @Sendable () -> Void)
}

/// The default executor: one serial queue at utility priority (one item at a time).
public struct DispatchPrewarmExecutor: PrewarmExecutor {
    private let queue: DispatchQueue

    public init(label: String = "PERF-005 media prewarm") {
        queue = DispatchQueue(label: label, qos: .utility)
    }

    public func execute(_ work: @escaping @Sendable () -> Void) { queue.async(execute: work) }
}

/// A scheduled action that can be cancelled.
public protocol PrewarmClockToken: Sendable {
    func cancel()
}

/// Schedules the settle delay (injected so tests never wait).
public protocol PrewarmClock: Sendable {
    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any PrewarmClockToken
}

/// The default clock: a utility queue's `asyncAfter`.
public struct DispatchPrewarmClock: PrewarmClock {
    private final class Token: PrewarmClockToken, @unchecked Sendable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    private let queue = DispatchQueue(label: "PERF-005 media prewarm clock", qos: .utility)

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> any PrewarmClockToken {
        let item = DispatchWorkItem(block: action)
        let parts = delay.components
        let seconds: Double = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        queue.asyncAfter(deadline: .now() + max(0, seconds), execute: item)
        return Token(item)
    }
}

/// What a load produced.
public enum PrewarmLoadResult: @unchecked Sendable {
    /// The asset and its size in bytes (decoded pixels, texture memory).
    case loaded(bytes: Int, payload: AnyObject)
    /// Not loaded on purpose: unsupported kind, cancelled, larger than `maxBytes`, graphics step refused.
    case refused
    /// The source could not be loaded (the step that shows it later reports the error as today).
    case failed
}

/// Loads one item on the executor's thread.
public protocol PrewarmLoading: Sendable {
    func load(_ item: PrewarmItem, context: PrewarmLoadContext) -> PrewarmLoadResult
}

/// What a running load may ask.
public final class PrewarmLoadContext: @unchecked Sendable {
    /// The budget: a larger result is never kept, so a loader may refuse before decoding.
    public let maxBytes: Int
    private let lock = NSLock()
    private var cancelled = false
    private let gate: NSLock
    private let presentationPaused: @Sendable () -> Bool

    init(maxBytes: Int, gate: NSLock, presentationPaused: @escaping @Sendable () -> Bool) {
        self.maxBytes = maxBytes
        self.gate = gate
        self.presentationPaused = presentationPaused
    }

    /// The item was cancelled (stale plan, suspension, memory pressure, shutdown).
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Runs `body` (GPU work: texture upload, mip generation) unless the item is cancelled or presentation is
    /// paused; nil when refused. A presentation pause waits for a running step to end.
    public func graphicsStep<T>(_ body: () -> T) -> T? {
        gate.lock()
        defer { gate.unlock() }
        guard !isCancelled, !presentationPaused() else { return nil }
        return body()
    }
}

/// Why work is held.
public enum PrewarmPauseReason: String, Sendable, Hashable {
    /// PERF-011: the app cannot present frames.
    case presentation
    /// PERF-003 signal: thermal state serious or critical.
    case thermal
}

/// Counters for tests and diagnostics (no user content).
public struct PrewarmStats: Equatable, Sendable {
    public var plans = 0
    public var loadsStarted = 0
    public var loadsAdmitted = 0
    /// In-flight items cancelled.
    public var cancelled = 0
    /// Queued items dropped by a replan before they started.
    public var dropped = 0
    /// Entries or results released (stale, refused, suspension, memory pressure, shutdown, eviction).
    public var released = 0
    public var rejected = 0
    public var taken = 0
    public var presetRequests = 0
    public var peakHeldBytes = 0
}

// MARK: - Scheduler

public final class PrewarmScheduler: @unchecked Sendable {
    public let budgetBytes: Int
    public let settleDelay: Duration
    private let executor: any PrewarmExecutor
    private let clock: any PrewarmClock
    private let loader: any PrewarmLoading

    private let lock = NSLock()
    private let gate = NSLock()
    private var planned: [PrewarmItem] = []
    private var effective: [PrewarmItem] = []
    private var live: Set<PrewarmKey> = []
    private var queue: [PrewarmItem] = []
    private var inFlight: (item: PrewarmItem, context: PrewarmLoadContext)?
    private var cache: PrewarmCache
    private var pauses: Set<PrewarmPauseReason> = []
    private var settled = false
    private var settleGeneration: UInt64 = 0
    private var settleToken: (any PrewarmClockToken)?
    private var isShutDown = false
    private var lowPowerValue = false
    private var statsValue = PrewarmStats()
    private var presetPicks: [String] = []

    public init(budgetBytes: Int, loader: any PrewarmLoading, executor: any PrewarmExecutor = DispatchPrewarmExecutor(),
                clock: any PrewarmClock = DispatchPrewarmClock(), settleDelay: Duration = .milliseconds(500)) {
        self.budgetBytes = max(0, budgetBytes)
        self.loader = loader
        self.executor = executor
        self.clock = clock
        self.settleDelay = settleDelay
        cache = PrewarmCache(budgetBytes: budgetBytes)
    }

    // MARK: Plan

    /// Replaces the plan (R2). `items` in any order; ranks decide priority. `live`: the live scene's keys.
    public func plan(_ items: [PrewarmItem], live: Set<PrewarmKey>) {
        lock.lock()
        guard !isShutDown else { lock.unlock(); return }
        planned = PrewarmItem.normalized(items)
        self.live = live
        statsValue.plans += 1
        let released = applyPlanLocked(requeue: true)
        restartSettleLocked()
        lock.unlock()
        drop(released)
    }

    /// R9: Low Power keeps only the next cue's items.
    public var lowPower: Bool {
        get { withLock { lowPowerValue } }
        set {
            lock.lock()
            guard newValue != lowPowerValue else { lock.unlock(); return }
            lowPowerValue = newValue
            let released = applyPlanLocked(requeue: true)
            let job = startNextLocked()
            lock.unlock()
            drop(released)
            run(job)
        }
    }

    /// Recomputes the effective plan, releases stale entries, cancels a stale in-flight item and rebuilds the
    /// queue. Returns the released assets (dropped by the caller outside the lock).
    private func applyPlanLocked(requeue: Bool) -> [PrewarmedAsset] {
        effective = lowPowerValue ? planned.filter { (i: PrewarmItem) -> Bool in i.rank == 0 } : planned
        let keys: Set<PrewarmKey> = Set(effective.map(\.key))
        let released: [PrewarmedAsset] = cache.release(keeping: keys, live: live)
        statsValue.released += released.count
        for item in effective { cache.touch(item.key, rank: item.rank) }
        if let current = inFlight, !keys.contains(current.item.key), !current.context.isCancelled {
            current.context.cancel()
            statsValue.cancelled += 1
        }
        let previous: Set<PrewarmKey> = Set(queue.map(\.key))
        let next: [PrewarmItem] = requeue ? effective.filter { (i: PrewarmItem) -> Bool in
            !cache.contains(i.key) && !live.contains(i.key) && i.key != inFlight?.item.key   // the live scene holds its own
        } : []
        statsValue.dropped += previous.subtracting(Set(next.map(\.key))).count
        queue = next
        return released
    }

    private func restartSettleLocked() {
        settleToken?.cancel()
        settleToken = nil
        settled = false
        settleGeneration &+= 1
        let generation = settleGeneration
        settleToken = clock.schedule(after: settleDelay) { [weak self] in self?.settle(generation) }
    }

    private func settle(_ generation: UInt64) {
        lock.lock()
        guard generation == settleGeneration, !isShutDown else { lock.unlock(); return }
        settled = true
        settleToken = nil
        let job = startNextLocked()
        lock.unlock()
        run(job)
    }

    /// The next load to hand to the executor, if one may start now.
    private func startNextLocked() -> (@Sendable () -> Void)? {
        guard !isShutDown, pauses.isEmpty, settled, inFlight == nil else { return nil }
        while !queue.isEmpty {
            let item = queue.removeFirst()
            if cache.contains(item.key) { continue }
            let context = PrewarmLoadContext(maxBytes: budgetBytes, gate: gate) { [weak self] () -> Bool in
                self?.isPausedFor(.presentation) ?? true
            }
            inFlight = (item, context)
            statsValue.loadsStarted += 1
            return { [self] in load(item, context: context) }
        }
        return nil
    }

    private func run(_ job: (@Sendable () -> Void)?) {
        guard let job else { return }
        executor.execute(job)
    }

    /// On the executor: loads one item, then admits or releases the result and starts the next.
    private func load(_ item: PrewarmItem, context: PrewarmLoadContext) {
        let result = loader.load(item, context: context)
        lock.lock()
        if inFlight?.context === context { inFlight = nil }
        var released: [PrewarmedAsset] = []
        if case let .loaded(bytes, payload) = result {
            let asset = PrewarmedAsset(key: item.key, bytes: bytes, payload: payload)
            let current: PrewarmItem? = effective.first { (i: PrewarmItem) -> Bool in i.key == item.key }
            if context.isCancelled || isShutDown || pauses.contains(.presentation) || current == nil {
                released.append(asset)
            } else if let current {
                switch cache.admit(asset, rank: current.rank, live: live) {
                case .success(let evicted):
                    statsValue.loadsAdmitted += 1
                    released += evicted
                    statsValue.peakHeldBytes = max(statsValue.peakHeldBytes, cache.peakBytes)
                case .failure:
                    statsValue.rejected += 1
                    released.append(asset)
                }
            }
        }
        statsValue.released += released.count
        let job = startNextLocked()
        lock.unlock()
        drop(released)
        run(job)
    }

    /// Drops the last references outside the lock (a payload's deinit may free a lot).
    private func drop(_ assets: [PrewarmedAsset]) {
        var assets = assets
        assets.removeAll()
    }

    // MARK: Pauses

    public func pause(_ reason: PrewarmPauseReason) {
        lock.lock()
        guard !isShutDown, pauses.insert(reason).inserted else { lock.unlock(); return }
        var released: [PrewarmedAsset] = []
        if reason == .presentation {
            if let current = inFlight, !current.context.isCancelled {
                current.context.cancel()
                statsValue.cancelled += 1
            }
            released = cache.release(keeping: [], live: live)
            statsValue.released += released.count
        }
        settleToken?.cancel()
        settleToken = nil
        settled = false
        lock.unlock()
        drop(released)
        if reason == .presentation {
            gate.lock()   // waits for a running graphics step; later ones see the pause and refuse
            gate.unlock()
        }
    }

    public func resume(_ reason: PrewarmPauseReason) {
        lock.lock()
        guard !isShutDown, pauses.remove(reason) != nil else { lock.unlock(); return }
        if pauses.isEmpty {
            _ = applyPlanLocked(requeue: true)
            restartSettleLocked()
        }
        lock.unlock()
    }

    public func isPausedFor(_ reason: PrewarmPauseReason) -> Bool { withLock { pauses.contains(reason) } }
    public var isPaused: Bool { withLock { !pauses.isEmpty } }

    // MARK: Live scene, memory pressure, presets

    /// Hands the entry for `key` to the live scene (R4); it leaves the prewarm accounting.
    public func take(_ key: PrewarmKey) -> PrewarmedAsset? {
        withLock {
            let asset = cache.take(key)
            if asset != nil { statsValue.taken += 1 }
            return asset
        }
    }

    /// R10: drops every non-live entry, cancels the in-flight item and clears the queue (the next plan starts
    /// again). Returns what was freed.
    public func releaseForMemoryPressure() -> (bytes: Int, items: Int) {
        lock.lock()
        if let current = inFlight, !current.context.isCancelled {
            current.context.cancel()
            statsValue.cancelled += 1
        }
        statsValue.dropped += queue.count
        queue.removeAll()
        let released = cache.release(keeping: [], live: live)
        statsValue.released += released.count
        lock.unlock()
        let bytes: Int = released.reduce(0) { (sum: Int, a: PrewarmedAsset) -> Int in sum + a.bytes }
        let count = released.count
        drop(released)
        return (bytes, count)
    }

    /// R8: records the preset picks and calls the existing warm-up path at once (no delay added here).
    public func forwardPresets(_ ids: [String], _ forward: () -> Void) {
        lock.lock()
        presetPicks = ids
        statsValue.presetRequests += 1
        lock.unlock()
        forward()
    }

    /// Ends all work for good and releases everything held.
    public func shutdown() {
        lock.lock()
        isShutDown = true
        inFlight?.context.cancel()
        queue.removeAll()
        settleToken?.cancel()
        settleToken = nil
        let released = cache.release(keeping: [], live: [])
        statsValue.released += released.count
        lock.unlock()
        drop(released)
    }

    // MARK: Readouts (tests, diagnostics)

    public var stats: PrewarmStats { withLock { statsValue } }
    public var heldBytes: Int { withLock { cache.heldBytes } }
    public var cachedKeys: Set<PrewarmKey> { withLock { cache.keys } }
    public var queuedKeys: [PrewarmKey] { withLock { queue.map(\.key) } }
    public var inFlightKey: PrewarmKey? { withLock { inFlight?.item.key } }
    public var plannedKeys: [PrewarmKey] { withLock { effective.map(\.key) } }
    public var lastPresetPicks: [String] { withLock { presetPicks } }
    public var isSettled: Bool { withLock { settled } }
    public func isCached(_ key: PrewarmKey) -> Bool { withLock { cache.contains(key) } }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
