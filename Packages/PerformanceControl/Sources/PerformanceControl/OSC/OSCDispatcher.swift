// OSCDispatcher.swift — decodes a datagram and applies it under the parameter's policy
// (OSC-001-R12, R13; contract C3; OSC-002-R10, contract P3).
//
// A bundle is decoded completely first, so a malformed element rejects the whole datagram and
// applies nothing. Its messages are then applied immediately, depth-first in packet order; the time
// tag is ignored (scheduling and the late-message policy are OSC-006).
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
    /// OSC-002: a bundle; one outcome per message, depth-first in packet order (never `.rejected`
    /// or `.bundle`).
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
    /// OSC-009: datagrams dropped at the source or global limit (not decoded).
    public var rateLimited = 0
    /// OSC-009: messages held for their target's next slot instead of applied at once.
    public var coalesced = 0
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
    }

    public let store: ParameterStore
    public let limits: OSCRateLimitConfiguration
    private let routes: [String: ParameterID]
    private let clock: OSCMonotonicClock
    private let scheduler: OSCFlushScheduler
    private let state: Mutex<State>
    private let activityHandlers = Mutex<[ActivityHandler]>([])

    public init(store: ParameterStore, routes: [OSCRoute],
                limits: OSCRateLimitConfiguration = .default,
                clock: OSCMonotonicClock = .continuous(),
                scheduler: OSCFlushScheduler = .sleepingTask) {
        self.store = store
        var table: [String: ParameterID] = [:]
        for route in routes { table[route.address] = route.parameter }
        self.routes = table
        self.limits = limits
        self.clock = clock
        self.scheduler = scheduler
        state = Mutex(State(limiter: OSCRateLimiter(configuration: limits)))
    }

    public var counters: OSCReceiverCounters { state.withLock { $0.counters } }

    /// Values held for their target's next slot (tests).
    public var heldCount: Int { state.withLock { $0.limiter.heldCount } }
    /// Whether a deferred flush is scheduled (tests: never more than one).
    public var isFlushScheduled: Bool { state.withLock { $0.flushScheduled } }

    /// Called on the receiving side after every handled datagram, drop and flush (OSC-009-R11).
    public func onActivity(_ handler: @escaping ActivityHandler) {
        activityHandlers.withLock { $0.append(handler) }
    }

    @discardableResult
    public func handle(_ datagram: [UInt8], source: OSCSourceID = .unattributed) -> OSCDispatchOutcome {
        let (outcome, flushDelay) = state.withLock { s -> (OSCDispatchOutcome, UInt64?) in
            let now = clock.now()
            s.counters.received += 1
            guard s.limiter.admitDatagram(from: source, now: now) else {
                s.counters.rateLimited += 1
                return (.rateLimited, nil)
            }
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
            return (outcome, Self.claimFlush(&s, now: now))
        }
        if let flushDelay { scheduleFlush(after: flushDelay) }
        notifyActivity()
        return outcome
    }

    private static func countMessage(_ outcome: OSCDispatchOutcome, in c: inout OSCReceiverCounters) {
        switch outcome {
        case .applied: c.applied += 1
        case .coalesced: c.coalesced += 1
        case .unknownAddress, .wrongArguments, .notExternallyControllable, .refusedByStore: c.ignored += 1
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

    /// Applies every held value whose target has a token now; schedules the next flush if values
    /// remain (OSC-009-R8). Run by the scheduler; tests call it directly.
    public func flush() {
        let flushDelay = state.withLock { s -> UInt64? in
            s.flushScheduled = false
            let now = clock.now()
            for (id, value) in s.limiter.takeDue(now: now) where (try? store.setDouble(value, for: id)) != nil {
                s.counters.applied += 1
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
        case .success(let bundle):
            var outcomes: [OSCDispatchOutcome] = []
            outcomes.reserveCapacity(bundle.messages.count)
            for message in bundle.messages { outcomes.append(apply(message, now: now, &s)) }
            return .bundle(outcomes)
        case .failure(let error):
            return .rejected(error)
        }
    }

    private func apply(_ message: OSCMessage, now: UInt64, _ s: inout State) -> OSCDispatchOutcome {
        guard let id = routes[message.address] else { return .unknownAddress }
        guard let descriptor = store.registry.descriptor(for: id), descriptor.modulation.allowsExternalControl else {
            return .notExternallyControllable
        }
        guard message.arguments.count == 1, let value = message.arguments[0].numericValue else { return .wrongArguments }
        guard value.isFinite else { return .refusedByStore }      // never held: the store would refuse it
        let (decision, evicted) = s.limiter.submit(value, to: id, now: now)
        if let (evictedID, evictedValue) = evicted, (try? store.setDouble(evictedValue, for: evictedID)) != nil {
            s.counters.applied += 1
        }
        guard decision == .applyNow else { return .coalesced(id) }
        do {
            let stored = try store.setDouble(value, for: id)
            return .applied(id, stored)
        } catch {
            return .refusedByStore
        }
    }
}
