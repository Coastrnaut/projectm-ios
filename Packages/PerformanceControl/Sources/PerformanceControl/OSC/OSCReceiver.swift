// OSCReceiver.swift — the OSC receiver's lifecycle over a transport (OSC-001-R1 to R3, R14;
// contract C5; research OSC-001-D5).
//
// * Off until `start(port:)`. Only one transport exists at a time: a port change or restart waits
//   for the previous transport's `.cancelled` before opening the new one, so the same port can be
//   reopened.
// * `stop()` cancels the transport (listener and every peer) and reports `off` only after the
//   transport confirms `.cancelled`.
// * Every transport gets a generation; events from an older generation are ignored, so a late
//   `ready` or datagram from a cancelled listener changes nothing.
// * A failure cancels the transport and stays `failed` until the next `start` or `stop` (no retry).
// * Datagrams are decoded and applied on the transport's queue (never the main thread or an audio
//   thread). State handlers run there too; callers hop to their own actor.
// * OSC-009: datagrams pass the dispatcher's rate limits (per source, global, per target); every
//   launch and stop starts the limiter afresh (held values discarded). `onActivity` lets the app
//   coalesce its main-thread refreshes (`OSCRefreshGate`) instead of hopping once per message.
import ParameterGraph
import Synchronization

public final class OSCReceiver: Sendable {
    public typealias StateHandler = @Sendable (OSCReceiverState) -> Void

    private struct Active {
        let transport: any OSCDatagramTransport
        let generation: UInt64
        var stopRequested = false
    }

    private struct State {
        var phase: OSCReceiverState = .off
        /// The port the user wants open; nil when stopped or after a failure.
        var desiredPort: UInt16?
        var active: Active?
        var generation: UInt64 = 0
        var handlers: [StateHandler] = []
    }

    /// What to do after the lock is released.
    private struct Effects {
        var stop: (any OSCDatagramTransport)?
        var start: (transport: any OSCDatagramTransport, port: UInt16, generation: UInt64)?
        var notify: OSCReceiverState?
    }

    public let dispatcher: OSCDispatcher
    private let makeTransport: @Sendable () -> (any OSCDatagramTransport)?
    private let lockedState = Mutex(State())

    public init(store: ParameterStore = OSCReceiverCatalog.makeStore(),
                routes: [OSCRoute] = OSCReceiverCatalog.routes,
                limits: OSCRateLimitConfiguration = .default,
                clock: OSCMonotonicClock = .continuous(),
                scheduler: OSCFlushScheduler = .sleepingTask,
                makeTransport: @escaping @Sendable () -> (any OSCDatagramTransport)?) {
        dispatcher = OSCDispatcher(store: store, routes: routes, limits: limits, clock: clock, scheduler: scheduler)
        self.makeTransport = makeTransport
    }

    /// The receiver with the system's UDP transport (`NetworkDatagramTransport`, the Network
    /// framework); where the framework does not exist, every start fails as `.unavailable`.
    /// OSC-003: `store` and `routes` give the app's route table (the registry's routable parameters).
    public static func system(store: ParameterStore = OSCReceiverCatalog.makeStore(),
                              routes: [OSCRoute] = OSCReceiverCatalog.routes) -> OSCReceiver {
        #if canImport(Network)
        OSCReceiver(store: store, routes: routes, makeTransport: { NetworkDatagramTransport() })
        #else
        OSCReceiver(store: store, routes: routes, makeTransport: { nil })
        #endif
    }

    /// A receiver released without `stop()` still closes its listener.
    deinit {
        let transport = lockedState.withLock { s -> (any OSCDatagramTransport)? in
            guard let active = s.active, !active.stopRequested else { return nil }
            return active.transport
        }
        transport?.stop()
    }

    // MARK: Reading

    public var state: OSCReceiverState { lockedState.withLock { $0.phase } }
    public var counters: OSCReceiverCounters { dispatcher.counters }
    public var store: ParameterStore { dispatcher.store }

    /// The current test value (`osc.receiver.testValue`), 0 when the catalog is not in use.
    public var testValue: Double { store.double(OSCReceiverCatalog.testValueID) ?? 0 }

    /// Calls `handler` on the transport's queue after every change of the test value.
    public func observeTestValue(_ handler: @escaping @Sendable (Double) -> Void) -> ParameterObservation {
        store.observe { change in
            if change.id == OSCReceiverCatalog.testValueID, let value = change.newValue.doubleValue { handler(value) }
        }
    }

    /// Calls `handler` on the receiving side after every handled datagram, drop and deferred flush
    /// (OSC-009-R11). It must be cheap and must not call back into the receiver's counters
    /// synchronously; the app uses it to request a gated main-thread refresh.
    public func onActivity(_ handler: @escaping @Sendable () -> Void) {
        dispatcher.onActivity(handler)
    }

    /// Calls `handler` after every state change (on the transport's queue, or the caller's thread for
    /// changes made synchronously by `start`/`stop`).
    public func onStateChange(_ handler: @escaping StateHandler) {
        lockedState.withLock { $0.handlers.append(handler) }
    }

    // MARK: Lifecycle

    public func start(port: UInt16) {
        let effects = lockedState.withLock { s -> Effects in
            if s.desiredPort == port, s.active.map({ !$0.stopRequested }) == true { return Effects() }   // already on it
            s.desiredPort = port
            if var active = s.active {
                var e = Effects()
                if !active.stopRequested {
                    active.stopRequested = true
                    s.active = active
                    e.stop = active.transport
                }
                s.phase = .starting(port: port)
                e.notify = s.phase
                return e
            }
            return launch(port, &s)
        }
        perform(effects)
    }

    public func stop() {
        dispatcher.resetLimits()                      // held values are discarded (OSC-009-R5)
        let effects = lockedState.withLock { s -> Effects in
            s.desiredPort = nil
            guard var active = s.active else {
                if s.phase == .off { return Effects() }
                s.phase = .off
                return Effects(notify: .off)
            }
            var e = Effects()
            if !active.stopRequested {
                active.stopRequested = true
                s.active = active
                e.stop = active.transport
            }
            if s.phase != .stopping {
                s.phase = .stopping
                e.notify = .stopping
            }
            return e
        }
        perform(effects)
    }

    // MARK: Events

    private func handle(_ event: OSCTransportEvent, generation: UInt64) {
        // Datagrams are the hot path: check the generation, then dispatch outside the lock.
        switch event {
        case .datagram(let bytes, let source):
            if isCurrent(generation) { dispatcher.handle(bytes, source: source) }
            return
        case .oversized(let count):
            if isCurrent(generation) { dispatcher.noteOversized(count) }
            return
        case .droppedNonLocal:
            if isCurrent(generation) { dispatcher.noteDroppedNonLocal() }
            return
        case .ready, .failed, .cancelled:
            break
        }
        let effects = lockedState.withLock { s -> Effects in
            guard var active = s.active, active.generation == generation else { return Effects() }
            switch event {
            case .ready(let port):
                guard !active.stopRequested else { return Effects() }
                s.phase = .listening(port: port)
                return Effects(notify: s.phase)
            case .failed(let failure):
                var e = Effects()
                if !active.stopRequested {
                    active.stopRequested = true
                    s.active = active
                    e.stop = active.transport
                    let port = s.desiredPort ?? 0
                    s.desiredPort = nil                        // no automatic retry (OSC-001-R3)
                    s.phase = .failed(port: port, failure)
                    e.notify = s.phase
                }
                return e
            case .cancelled:
                s.active = nil
                if let port = s.desiredPort { return launch(port, &s) }
                if case .failed = s.phase { return Effects() }   // stays failed until start/stop
                s.phase = .off
                return Effects(notify: .off)
            case .datagram, .oversized, .droppedNonLocal:
                return Effects()
            }
        }
        perform(effects)
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        lockedState.withLock { s in
            guard let active = s.active else { return false }
            return active.generation == generation && !active.stopRequested
        }
    }

    /// Creates the next transport under the lock; it is started after the lock is released.
    private func launch(_ port: UInt16, _ s: inout State) -> Effects {
        guard let transport = makeTransport() else {
            s.desiredPort = nil
            s.phase = .failed(port: port, .unavailable)
            return Effects(notify: s.phase)
        }
        s.generation += 1
        s.active = Active(transport: transport, generation: s.generation)
        dispatcher.resetLimits()                      // every listener starts with full buckets (OSC-009-R5)
        s.phase = .starting(port: port)
        return Effects(start: (transport, port, s.generation), notify: s.phase)
    }

    private func perform(_ effects: Effects) {
        if let phase = effects.notify {
            let handlers = lockedState.withLock { $0.handlers }
            for handler in handlers { handler(phase) }
        }
        effects.stop?.stop()
        if let start = effects.start {
            let generation = start.generation
            start.transport.start(port: start.port) { [weak self] event in
                self?.handle(event, generation: generation)
            }
        }
    }
}
