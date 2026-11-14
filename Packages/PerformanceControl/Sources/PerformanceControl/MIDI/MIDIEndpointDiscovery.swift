// MIDIEndpointDiscovery.swift — MIDI endpoint discovery over a provider (MIDI-001-R5-R7, R12;
// contracts/midi-discovery.md C1, C2).
//
// * Off until `start()`. A start asks the provider to forward setup changes; `unavailable` (the system
//   MIDI service could not be reached) is reported and never retried by itself (spec Clarifications).
// * The first refresh after a start runs at once on the scheduler and its update is `isInitial`.
//   Every later provider signal goes through `MIDIRefreshCoalescer`: one refresh per burst, after the
//   coalescing delay (100 ms by default).
// * A refresh reads every endpoint, builds the ordered list, diffs it with the previous one and calls
//   the update handlers only when something changed (or for the initial list).
// * `stop()` stops the provider's forwarding, clears the list and bumps the generation, so a refresh
//   already scheduled does nothing.
// * Refreshes and update handlers run on the scheduler (a serial utility queue in the app), never on
//   the main thread and never inline from a provider signal. No MIDI message is received or parsed
//   (MIDI-001-R12), so nothing here runs per message.
import Synchronization

public enum MIDIProviderStartResult: Sendable, Equatable {
    case started
    /// The system MIDI service could not be reached; `code` is the system status (0 when none exists).
    case unavailable(code: Int32)
}

/// What discovery needs from the system (contract C1). Tests use `ScriptedMIDIEndpointProvider`.
public protocol MIDIEndpointProvider: AnyObject, Sendable {
    /// Begins forwarding setup changes as `onChange()` (any thread). Idempotent.
    func start(onChange: @escaping @Sendable () -> Void) -> MIDIProviderStartResult
    /// Stops forwarding; no `onChange` after it returns.
    func stop()
    /// Reads every source and destination now.
    func currentEndpoints() -> [MIDIEndpointRecord]
}

public enum MIDIDiscoveryState: Sendable, Hashable {
    case off
    case listening
    case unavailable(code: Int32)

    public var isListening: Bool { self == .listening }
}

/// One refresh's result.
public struct MIDIDiscoveryUpdate: Sendable, Hashable {
    public let endpoints: MIDIEndpointList
    public let changes: [MIDIEndpointChange]
    /// The first list after a start (its changes are all `appeared`; the app does not announce them).
    public let isInitial: Bool

    public init(endpoints: MIDIEndpointList, changes: [MIDIEndpointChange], isInitial: Bool) {
        self.endpoints = endpoints
        self.changes = changes
        self.isInitial = isInitial
    }
}

public final class MIDIEndpointDiscovery: Sendable {
    public typealias UpdateHandler = @Sendable (MIDIDiscoveryUpdate) -> Void
    public typealias StateHandler = @Sendable (MIDIDiscoveryState) -> Void

    public static let defaultCoalescingDelayNanoseconds: UInt64 = 100_000_000

    private struct State {
        var phase: MIDIDiscoveryState = .off
        var generation: UInt64 = 0
        var coalescer = MIDIRefreshCoalescer()
        var list: MIDIEndpointList = .empty
        var needsInitial = false
        var refreshCount = 0
        var updateHandlers: [UpdateHandler] = []
        var stateHandlers: [StateHandler] = []
    }

    public let provider: any MIDIEndpointProvider
    private let scheduler: MIDIRefreshScheduler
    private let delay: UInt64
    private let lockedState = Mutex(State())

    public init(provider: any MIDIEndpointProvider,
                scheduler: MIDIRefreshScheduler = .serialQueue(),
                coalescingDelayNanoseconds: UInt64 = MIDIEndpointDiscovery.defaultCoalescingDelayNanoseconds) {
        self.provider = provider
        self.scheduler = scheduler
        self.delay = coalescingDelayNanoseconds
    }

    deinit { provider.stop() }

    // MARK: Reading

    public var state: MIDIDiscoveryState { lockedState.withLock { (s: inout State) -> MIDIDiscoveryState in s.phase } }
    public var endpoints: MIDIEndpointList { lockedState.withLock { (s: inout State) -> MIDIEndpointList in s.list } }
    /// Refreshes run since launch (tests: a burst must cost one).
    public var refreshCount: Int { lockedState.withLock { (s: inout State) -> Int in s.refreshCount } }
    /// Signals absorbed by the coalescer since the last start.
    public var absorbedSignals: Int { lockedState.withLock { (s: inout State) -> Int in s.coalescer.absorbed } }

    public func onUpdate(_ handler: @escaping UpdateHandler) {
        lockedState.withLock { (s: inout State) -> Void in s.updateHandlers.append(handler) }
    }

    public func onStateChange(_ handler: @escaping StateHandler) {
        lockedState.withLock { (s: inout State) -> Void in s.stateHandlers.append(handler) }
    }

    // MARK: Lifecycle

    public func start() {
        let generation: UInt64? = lockedState.withLock { (s: inout State) -> UInt64? in
            guard s.phase == .off else { return nil }
            s.generation += 1
            s.phase = .listening
            s.coalescer.reset()
            s.list = .empty
            s.needsInitial = true
            return s.generation
        }
        guard let generation else { return }
        let result: MIDIProviderStartResult = provider.start { [weak self] () -> Void in
            self?.signal(generation: generation)
        }
        switch result {
        case .started:
            notify(.listening)
            scheduleRefresh(generation: generation, afterNanoseconds: 0)
        case .unavailable(let code):
            let changed: Bool = lockedState.withLock { (s: inout State) -> Bool in
                guard s.generation == generation else { return false }
                s.phase = .unavailable(code: code)
                s.needsInitial = false
                return true
            }
            if changed { notify(.unavailable(code: code)) }
        }
    }

    public func stop() {
        let wasOn: Bool = lockedState.withLock { (s: inout State) -> Bool in
            guard s.phase != .off else { return false }
            s.generation += 1
            s.phase = .off
            s.list = .empty
            s.coalescer.reset()
            s.needsInitial = false
            return true
        }
        guard wasOn else { return }
        provider.stop()
        notify(.off)
    }

    // MARK: Refresh

    private func signal(generation: UInt64) {
        let schedule: Bool = lockedState.withLock { (s: inout State) -> Bool in
            guard s.generation == generation, s.phase == .listening else { return false }
            return s.coalescer.signal()
        }
        if schedule {
            scheduler.schedule(delay) { [weak self] () -> Void in self?.refresh(generation: generation) }
        }
    }

    private func scheduleRefresh(generation: UInt64, afterNanoseconds: UInt64) {
        let schedule: Bool = lockedState.withLock { (s: inout State) -> Bool in
            guard s.generation == generation, s.phase == .listening else { return false }
            return s.coalescer.signal()
        }
        if schedule {
            scheduler.schedule(afterNanoseconds) { [weak self] () -> Void in self?.refresh(generation: generation) }
        }
    }

    private func refresh(generation: UInt64) {
        let current: Bool = lockedState.withLock { (s: inout State) -> Bool in
            guard s.generation == generation, s.phase == .listening else { return false }
            s.coalescer.beginRefresh()     // a signal from now on schedules the next refresh
            s.refreshCount += 1
            return true
        }
        guard current else { return }
        let records: [MIDIEndpointRecord] = provider.currentEndpoints()
        let list: MIDIEndpointList = MIDIEndpointList.make(from: records)
        let delivery: (update: MIDIDiscoveryUpdate, handlers: [UpdateHandler])? = lockedState.withLock {
            (s: inout State) -> (update: MIDIDiscoveryUpdate, handlers: [UpdateHandler])? in
            guard s.generation == generation, s.phase == .listening else { return nil }
            let changes: [MIDIEndpointChange] = MIDIEndpointDiff.changes(from: s.list, to: list)
            let initial: Bool = s.needsInitial
            s.needsInitial = false
            s.list = list
            guard initial || !changes.isEmpty else { return nil }
            return (MIDIDiscoveryUpdate(endpoints: list, changes: changes, isInitial: initial), s.updateHandlers)
        }
        guard let delivery else { return }
        for handler in delivery.handlers { handler(delivery.update) }
    }

    private func notify(_ state: MIDIDiscoveryState) {
        let handlers: [StateHandler] = lockedState.withLock { (s: inout State) -> [StateHandler] in s.stateHandlers }
        for handler in handlers { handler(state) }
    }
}

/// A provider for platforms without a system MIDI service (Linux): every start is `unavailable`.
public final class UnavailableMIDIEndpointProvider: MIDIEndpointProvider {
    public init() {}
    public func start(onChange: @escaping @Sendable () -> Void) -> MIDIProviderStartResult { .unavailable(code: 0) }
    public func stop() {}
    public func currentEndpoints() -> [MIDIEndpointRecord] { [] }
}
