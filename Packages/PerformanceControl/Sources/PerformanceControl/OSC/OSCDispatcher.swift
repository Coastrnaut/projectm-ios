// OSCDispatcher.swift — decodes a datagram and applies it under the parameter's policy
// (OSC-001-R12, R13; contract C3; OSC-002-R10, contract P3).
//
// A bundle is decoded completely first, so a malformed element rejects the whole datagram and
// applies nothing. OSC-006 then applies its messages by time tag (see below).
// Called on the transport's serial queue (OSC-001-R14), never on the main thread or an audio
// thread. A value reaches the store only through a route to a registered parameter whose
// `ModulationPolicy.allowsExternalControl` is true; the store clamps it and refuses NaN/infinity.
// Counters live in memory and never hold payloads or peer addresses.
//
// OSC-009 (specs/041-osc-009-osc-rate-limiter, contract L2): before decoding, a datagram must pass its
// source's and the global token bucket (else `.rateLimited`, not decoded); before applying, a message
// must pass its target's bucket (else its value is held, `.coalesced`, and a single deferred flush
// applies the newest held value at the target's next token). Store writes happen under the
// dispatcher's lock so a flush and a new datagram never reorder one target's values; store observers
// therefore MUST NOT call back into the dispatcher. Work per datagram is bounded: O(1) limiter
// checks, one bounded decode, at most `OSCLimits` bundle elements applied.
//
// OSC-003 (specs/191-osc-003-parameter-routes, contract R2): the route table can be replaced while the
// receiver runs (`setRoutes`, route enables and aliases); an address not in it is ignored and counted in
// `unknownAddresses`. A `.normalized` route maps its 0…1 number over the parameter's range before the
// limiter, so a held value is already the parameter value. Every applied value of a routed parameter is
// kept in `liveValues` (memory only) for the app's live-value path; replacing the routes drops the live
// values of parameters no route reaches any more.
//
// OSC-004 (specs/274-osc-004-osc-learn, contract L1): `armLearn` arms a one-shot capture. The first message after
// it whose address and argument pass `OSCLearnEligibility` (so only after the allow list, the datagram rate check
// and a whole-datagram decode) is captured and the capture disarms in the same locked step, so a burst or bundle
// records one address. The handler runs after the lock is released, on the receiving side. The message is then
// dispatched with the routes as they are (learning only creates a route later).
//
// OSC-006 (specs/278-osc-006-osc-bundles, contract B1): a bundle's tag is mapped to the monotonic clock once at
// receipt (`OSCTimeMapping`, the injected wall clock); a message takes the latest of its enclosing bundles' tags.
// "Immediately", on-time (≤ 20 ms late) and late (≤ 1 s) messages apply at once in (due, arrival) order; older ones
// and those more than 10 s ahead are dropped; the rest wait in a bounded `OSCBundleSchedule` (256; a datagram that
// does not fit is dropped whole). One wake-up at a time runs on the flush scheduler, and every datagram first
// applies what is already due, so values never reorder. A due message goes through `apply(message:)` like any
// other (routes, policy, learn, per-target limit at dispatch); the allow list and datagram limits were checked at
// receipt. `clearScheduled` (receiver stop and start) drops everything pending.
import ParameterGraph
import Synchronization

public enum OSCDispatchOutcome: Sendable, Hashable {
    case applied(ParameterID, Double)
    case rejected(OSCDecodeError)
    case unknownAddress
    /// The route needs exactly one numeric argument.
    case wrongArguments
    /// The parameter is not registered or its policy does not allow external control.
    case notExternallyControllable
    /// The store refused the value (for example NaN).
    case refusedByStore
    /// OSC-009: the datagram was over its source's or the global rate; it was not decoded.
    case rateLimited
    /// OSC-009: the message's target was over its rate; the value is held for the target's next slot.
    case coalesced(ParameterID)
    /// OSC-006: the message waits for its time tag in the bundle schedule.
    case scheduled
    /// OSC-006: the message was too late, too far ahead or did not fit the schedule.
    case dropped(OSCBundleDrop)
    /// OSC-002: a bundle; one outcome per message, depth-first in packet order (never `.rejected`
    /// or `.bundle`). A scheduled message's later outcome is counted when it applies.
    indirect case bundle([OSCDispatchOutcome])
}

public struct OSCReceiverCounters: Sendable, Equatable {
    /// Datagrams handed to the dispatcher (oversized ones included).
    public var received = 0
    /// Messages applied (a bundle adds one per applied message).
    public var applied = 0
    /// Well-formed messages not applied (unknown address, wrong arguments, policy, store refusal);
    /// per message, like `applied`.
    public var ignored = 0
    /// OSC-002: accepted bundle datagrams.
    public var bundles = 0
    /// Datagrams rejected by the decoder.
    public var rejected = 0
    public var droppedNonLocal = 0
    /// OSC-008: datagrams from hosts not on the enabled allowlist (dropped before `received`; not decoded).
    public var droppedUnapproved = 0
    /// OSC-009: datagrams dropped at the source or global limit (not decoded).
    public var rateLimited = 0
    /// OSC-009: messages held for their target's next slot instead of applied at once.
    public var coalesced = 0
    /// OSC-003: messages to an address that is not on the route allowlist (also counted in `ignored`).
    public var unknownAddresses = 0
    /// OSC-006: bundle messages put in the schedule.
    public var scheduled = 0
    /// OSC-006: bundle messages applied at once although 20 ms to 1 s late.
    public var lateApplied = 0
    /// OSC-006: bundle messages dropped as more than 1 s late.
    public var lateDropped = 0
    /// OSC-006: bundle messages dropped as more than 10 s ahead.
    public var beyondHorizon = 0
    /// OSC-006: bundle messages dropped because the schedule was full.
    public var scheduleOverflow = 0
    /// `OSCDecodeError.reason` → count.
    public var rejectedByReason: [String: Int] = [:]

    public init() {}
}

public final class OSCDispatcher: Sendable {
    public typealias ActivityHandler = @Sendable () -> Void

    private struct State {
        var counters = OSCReceiverCounters()
        var limiter: OSCRateLimiter
        var flushScheduled = false
        var routes: [String: OSCRoute] {
            didSet { reached = Set(routes.values.map { (route: OSCRoute) -> ParameterID in route.parameter }) }
        }
        /// The parameters some route reaches (kept with `routes`).
        var reached: Set<ParameterID> = []
        /// OSC-003: the newest applied value per routed parameter (memory only).
        var liveValues: [ParameterID: Double] = [:]
        /// OSC-004: the one-shot learn capture.
        var learnHandler: LearnHandler?
        var learnCaptured: String?
        /// OSC-006: pending bundle messages, the arrival counter and the due time of the armed wake-up.
        var schedule = OSCBundleSchedule()
        var sequence: UInt64 = 0
        var armedWake: UInt64?
    }

    public typealias LearnHandler = @Sendable (String) -> Void

    public let store: ParameterStore
    public let limits: OSCRateLimitConfiguration
    public let timing: OSCBundleTiming
    private let clock: OSCMonotonicClock
    private let wallClock: OSCWallClock
    private let scheduler: OSCFlushScheduler
    private let state: Mutex<State>
    private let activityHandlers = Mutex<[ActivityHandler]>([])

    public init(store: ParameterStore, routes: [OSCRoute],
                limits: OSCRateLimitConfiguration = .default,
                clock: OSCMonotonicClock = .continuous(),
                scheduler: OSCFlushScheduler = .sleepingTask,
                wallClock: OSCWallClock = .system,
                timing: OSCBundleTiming = .default) {
        self.store = store
        self.limits = limits
        self.timing = timing
        self.clock = clock
        self.wallClock = wallClock
        self.scheduler = scheduler
        var initial = State(limiter: OSCRateLimiter(configuration: limits), routes: [:])
        initial.routes = Self.table(routes)
        state = Mutex(initial)
    }

    private static func table(_ routes: [OSCRoute]) -> [String: OSCRoute] {
        var table: [String: OSCRoute] = [:]
        for route in routes where table[route.address] == nil { table[route.address] = route }
        return table
    }

    public var counters: OSCReceiverCounters { state.withLock { $0.counters } }

    /// OSC-003: the addresses messages may use, in no order (tests and Settings).
    public var routedAddresses: Set<String> { state.withLock { Set($0.routes.keys) } }

    /// OSC-003-R6: replaces the allowlist. Live values of parameters no route reaches any more are dropped;
    /// a value held by the limiter for such a parameter is still applied to the store (it was admitted), but
    /// never re-enters `liveValues`.
    public func setRoutes(_ routes: [OSCRoute]) {
        state.withLock { s in
            s.routes = Self.table(routes)
            let reached: Set<ParameterID> = s.reached
            s.liveValues = s.liveValues.filter { (entry: (key: ParameterID, value: Double)) -> Bool in reached.contains(entry.key) }
        }
        notifyActivity()
    }

    /// OSC-003-R5: the newest value OSC applied to each routed parameter since launch or the last clear.
    public var liveValues: [ParameterID: Double] { state.withLock { $0.liveValues } }

    /// OSC-003-R5: forgets every live value (OSC turned off by the user).
    public func clearLiveValues() {
        state.withLock { $0.liveValues.removeAll() }
        notifyActivity()
    }

    /// Values held for their target's next slot (tests).
    public var heldCount: Int { state.withLock { $0.limiter.heldCount } }
    /// Whether a deferred flush is scheduled (tests: never more than one).
    public var isFlushScheduled: Bool { state.withLock { $0.flushScheduled } }

    // MARK: Bundle schedule (OSC-006)

    /// Bundle messages waiting for their time tag.
    public var pendingScheduledCount: Int { state.withLock { $0.schedule.count } }

    /// Drops every pending bundle message (OSC-006-R10: the receiver stops or starts).
    public func clearScheduled() {
        state.withLock { s in
            s.schedule.removeAll()
            s.armedWake = nil
        }
    }

    /// Applies every pending bundle message that is due and arms the next wake-up (run by the scheduler; tests
    /// call it directly).
    public func flushScheduled() { wake(armedFor: nil) }

    private func wake(armedFor due: UInt64?) {
        let (next, flushDelay, learned) = state.withLock { s -> ((UInt64, UInt64)?, UInt64?, (LearnHandler, String)?) in
            if let due, s.armedWake == due { s.armedWake = nil }
            let now = clock.now()
            applyDue(now: now, &s)
            return (Self.claimWake(&s, now: now), Self.claimFlush(&s, now: now), Self.takeLearned(&s))
        }
        if let next { scheduleWake(next) }
        if let flushDelay { scheduleFlush(after: flushDelay) }
        if let (handler, address) = learned { handler(address) }
        notifyActivity()
    }

    /// Dispatches every due bundle message in (due, arrival) order, counted like an immediate message.
    private func applyDue(now: UInt64, _ s: inout State) {
        guard let earliest = s.schedule.earliestDue, earliest <= now else { return }
        for entry in s.schedule.takeDue(now: now) {
            Self.countMessage(apply(entry.message, now: now, &s), in: &s.counters)
        }
    }

    /// The due time and delay of a wake-up to schedule now: only when none is armed for the earliest due time or
    /// before it.
    private static func claimWake(_ s: inout State, now: UInt64) -> (UInt64, UInt64)? {
        guard let earliest = s.schedule.earliestDue else { return nil }
        if let armed = s.armedWake, armed <= earliest { return nil }
        s.armedWake = earliest
        return (earliest, earliest > now ? earliest - now : 0)
    }

    private func scheduleWake(_ next: (due: UInt64, delay: UInt64)) {
        let due = next.due
        scheduler.schedule(next.delay) { [weak self] in self?.wake(armedFor: due) }
    }

    // MARK: Learn (OSC-004)

    /// Arms the one-shot learn capture: `handler` receives the first eligible address, once. Arming again replaces
    /// the handler.
    public func armLearn(_ handler: @escaping LearnHandler) {
        state.withLock { s in
            s.learnHandler = handler
            s.learnCaptured = nil
        }
    }

    public func disarmLearn() {
        state.withLock { s in
            s.learnHandler = nil
            s.learnCaptured = nil
        }
    }

    public var isLearnArmed: Bool { state.withLock { $0.learnHandler != nil } }

    /// Called on the receiving side after every handled datagram, drop and flush (OSC-009-R11).
    public func onActivity(_ handler: @escaping ActivityHandler) {
        activityHandlers.withLock { $0.append(handler) }
    }

    @discardableResult
    public func handle(_ datagram: [UInt8], source: OSCSourceID = .unattributed) -> OSCDispatchOutcome {
        let (outcome, flushDelay, wake, learned) = state.withLock {
            s -> (OSCDispatchOutcome, UInt64?, (UInt64, UInt64)?, (LearnHandler, String)?) in
            let now = clock.now()
            s.counters.received += 1
            guard s.limiter.admitDatagram(from: source, now: now) else {
                s.counters.rateLimited += 1
                return (.rateLimited, nil, nil, nil)
            }
            applyDue(now: now, &s)                    // OSC-006: what is due goes first
            let outcome = apply(datagram, now: now, &s)
            switch outcome {
            case .rejected(let error):
                s.counters.rejected += 1
                s.counters.rejectedByReason[error.reason, default: 0] += 1
            case .bundle(let outcomes):
                s.counters.bundles += 1
                for element in outcomes { Self.countMessage(element, in: &s.counters) }
            default:
                Self.countMessage(outcome, in: &s.counters)
            }
            return (outcome, Self.claimFlush(&s, now: now), Self.claimWake(&s, now: now), Self.takeLearned(&s))
        }
        if let flushDelay { scheduleFlush(after: flushDelay) }
        if let wake { scheduleWake(wake) }
        if let (handler, address) = learned { handler(address) }
        notifyActivity()
        return outcome
    }

    private static func countMessage(_ outcome: OSCDispatchOutcome, in c: inout OSCReceiverCounters) {
        switch outcome {
        case .applied: c.applied += 1
        case .coalesced: c.coalesced += 1
        case .unknownAddress:
            c.ignored += 1
            c.unknownAddresses += 1
        case .wrongArguments, .notExternallyControllable, .refusedByStore: c.ignored += 1
        case .scheduled, .dropped: break                  // counted when classified (OSC-006)
        case .rejected, .bundle, .rateLimited: break      // never produced per message
        }
    }

    /// A datagram over `OSCLimits.maximumDatagramBytes` that the transport did not copy.
    public func noteOversized(_ byteCount: Int) {
        state.withLock { s in
            s.counters.received += 1
            s.counters.rejected += 1
            s.counters.rejectedByReason[OSCDecodeError.oversized(byteCount: byteCount).reason, default: 0] += 1
        }
        notifyActivity()
    }

    public func noteDroppedNonLocal() {
        state.withLock { $0.counters.droppedNonLocal += 1 }
        notifyActivity()
    }

    /// OSC-008-R7: a datagram the peer allowlist refused (never decoded, never charged to a rate limit).
    public func noteDroppedUnapproved() {
        state.withLock { $0.counters.droppedUnapproved += 1 }
        notifyActivity()
    }

    /// Applies every held value whose target has a token now; schedules the next flush if values
    /// remain (OSC-009-R8). Run by the scheduler; tests call it directly.
    public func flush() {
        let flushDelay = state.withLock { s -> UInt64? in
            s.flushScheduled = false
            let now = clock.now()
            for (id, value) in s.limiter.takeDue(now: now) {
                Self.store(value, for: id, store: store, &s)
            }
            return Self.claimFlush(&s, now: now)
        }
        if let flushDelay { scheduleFlush(after: flushDelay) }
        notifyActivity()
    }

    /// Empty limiter tables and no held values; counters stay (OSC-009-R5). A flush already scheduled
    /// finds nothing to apply.
    public func resetLimits() {
        state.withLock { $0.limiter.reset() }
    }

    /// OSC-004: the captured address and its handler, disarming the capture.
    private static func takeLearned(_ s: inout State) -> (LearnHandler, String)? {
        guard let address = s.learnCaptured, let handler = s.learnHandler else { return nil }
        s.learnCaptured = nil
        s.learnHandler = nil
        return (handler, address)
    }

    /// The delay of the next flush when one must be scheduled now (never two at once).
    private static func claimFlush(_ s: inout State, now: UInt64) -> UInt64? {
        guard !s.flushScheduled, let delay = s.limiter.nextDue(now: now) else { return nil }
        s.flushScheduled = true
        return delay
    }

    private func scheduleFlush(after delay: UInt64) {
        scheduler.schedule(delay) { [weak self] in self?.flush() }
    }

    private func notifyActivity() {
        let handlers = activityHandlers.withLock { $0 }
        for handler in handlers { handler() }
    }

    private func apply(_ datagram: [UInt8], now: UInt64, _ s: inout State) -> OSCDispatchOutcome {
        switch OSCDecoder.decodePacket(datagram) {
        case .success(.message(let message)):
            return apply(message, now: now, &s)
        case .success(.bundle(let bundle)):
            return .bundle(schedule(bundle, now: now, &s))
        case .failure(let error):
            return .rejected(error)
        }
    }

    /// OSC-006 contract B1, steps 2 to 6: one outcome per message in depth-first packet order.
    private func schedule(_ bundle: OSCBundle, now: UInt64, _ s: inout State) -> [OSCDispatchOutcome] {
        var items: [(message: OSCMessage, tag: OSCTimeTag)] = []
        Self.flatten(bundle, outer: .immediately, into: &items)
        let mapping = OSCTimeMapping(monotonicNow: now, wallNow: wallClock.now())
        var outcomes = [OSCDispatchOutcome](repeating: .scheduled, count: items.count)
        var applyNow: [(offset: Int64, sequence: UInt64, index: Int)] = []
        var future: [OSCScheduledMessage] = []
        var indexOf: [UInt64: Int] = [:]
        for (index, item) in items.enumerated() {
            s.sequence &+= 1
            let offset: Int64 = mapping.offset(for: item.tag) ?? 0
            if offset > 0 {
                if UInt64(offset) > timing.horizon {
                    s.counters.beyondHorizon += 1
                    outcomes[index] = .dropped(.beyondHorizon)
                } else {
                    indexOf[s.sequence] = index
                    future.append(OSCScheduledMessage(message: item.message, due: now &+ UInt64(offset), sequence: s.sequence))
                }
                continue
            }
            let lateness = UInt64(-offset)
            if lateness > timing.maximumLateness {
                s.counters.lateDropped += 1
                outcomes[index] = .dropped(.tooLate)
                continue
            }
            if lateness > timing.onTimeTolerance { s.counters.lateApplied += 1 }
            applyNow.append((offset, s.sequence, index))
        }
        // Due order, then arrival order (OSC-006-R5).
        applyNow.sort { (x: (offset: Int64, sequence: UInt64, index: Int), y: (offset: Int64, sequence: UInt64, index: Int)) -> Bool in
            x.offset != y.offset ? x.offset < y.offset : x.sequence < y.sequence
        }
        for entry in applyNow { outcomes[entry.index] = apply(items[entry.index].message, now: now, &s) }
        guard !future.isEmpty else { return outcomes }
        if s.schedule.count + future.count > timing.capacity {
            s.counters.scheduleOverflow += future.count          // OSC-006-R8: the newest datagram is dropped whole
            for entry in future { if let index = indexOf[entry.sequence] { outcomes[index] = .dropped(.queueFull) } }
        } else {
            s.counters.scheduled += future.count
            for entry in future { s.schedule.insert(entry) }
        }
        return outcomes
    }

    /// Messages depth-first with their effective tags: an inner tag earlier than its container's takes the
    /// container's (OSC-006-R4).
    private static func flatten(_ bundle: OSCBundle, outer: OSCTimeTag,
                                into items: inout [(message: OSCMessage, tag: OSCTimeTag)]) {
        let tag = OSCTimeTag.latest(outer, bundle.timeTag)
        for element in bundle.elements {
            switch element {
            case .message(let message): items.append((message, tag))
            case .bundle(let inner): flatten(inner, outer: tag, into: &items)
            }
        }
    }

    private func apply(_ message: OSCMessage, now: UInt64, _ s: inout State) -> OSCDispatchOutcome {
        if s.learnHandler != nil, s.learnCaptured == nil, let address = OSCLearnEligibility.address(of: message) {
            s.learnCaptured = address                 // OSC-004-R5: the first eligible message only
        }
        guard let route = s.routes[message.address] else { return .unknownAddress }   // OSC-003-R2: allowlist only
        let id: ParameterID = route.parameter
        guard let descriptor = store.registry.descriptor(for: id), descriptor.modulation.allowsExternalControl else {
            return .notExternallyControllable
        }
        guard message.arguments.count == 1, let number = message.arguments[0].numericValue else { return .wrongArguments }
        guard number.isFinite else { return .refusedByStore }      // never held: the store would refuse it
        let value: Double
        switch route.scale {
        case .raw:
            value = number
        case .normalized:
            guard let mapped = OSCParameterRoutes.value(normalized: number, for: descriptor) else { return .wrongArguments }
            value = mapped
        }
        let (decision, evicted) = s.limiter.submit(value, to: id, now: now)
        if let (evictedID, evictedValue) = evicted { Self.store(evictedValue, for: evictedID, store: store, &s) }
        guard decision == .applyNow else { return .coalesced(id) }
        guard let stored = Self.store(value, for: id, store: store, counted: false, &s) else { return .refusedByStore }
        return .applied(id, stored)
    }

    /// Writes one admitted value and records it as the parameter's live value while a route still reaches it
    /// (OSC-003-R5). `counted` adds it to `applied` (flushes and evictions; a direct apply is counted from
    /// its outcome).
    @discardableResult
    private static func store(_ value: Double, for id: ParameterID, store: ParameterStore, counted: Bool = true,
                              _ s: inout State) -> Double? {
        guard let stored = try? store.setDouble(value, for: id) else { return nil }
        if counted { s.counters.applied += 1 }
        if s.reached.contains(id) { s.liveValues[id] = stored }
        return stored
    }
}
