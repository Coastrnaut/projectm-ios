// MIDISourceSubscriptions.swift — one live connection per present MIDI input, across unplug and replug (MIDI-011-R1-R4,
// R7; specs/166-midi-011-hotplug, contracts/hotplug.md H1-H3; research MIDI-011-D1-D5).
//
// * `MIDISourceSystem` hides the system's endpoint enumeration and connect calls (CoreMIDI in `MIDISystem/`, a scripted
//   system in tests and the app's DEBUG fake). A handle is the system's endpoint reference; it may change on a replug.
// * `MIDISubscriptionRegistry` is keyed by MIDI-001's stable ID (the unique number, or the name-based fallback when it is
//   missing or shared) and holds the current handle. An entry exists iff exactly one connection to that handle is live,
//   so a reconcile never connects a handle twice. Entries whose source is absent, whose handle changed or was reported
//   removed, or which went offline, are disconnected and reported **lost** (held keys must be released); the next reconcile reconnects a
//   source that is present again.
// * `MIDISourceSubscriptions` serialises reconciles under one lock, reconciles at once when the wanted set changes, and
//   coalesces system notifications with MIDI-001's coalescer (one reconcile per burst). Nothing here runs per message,
//   and nothing is logged or stored.
import Synchronization

/// One endpoint as the system lists it, with its current handle (0 for destinations, which are never connected).
public struct MIDISourceSnapshot: Sendable, Hashable {
    public var handle: UInt32
    public var record: MIDIEndpointRecord

    public init(handle: UInt32, record: MIDIEndpointRecord) {
        self.handle = handle
        self.record = record
    }
}

/// What the subscriptions need from the system (contract H1).
public protocol MIDISourceSystem: AnyObject, Sendable {
    /// Every source and destination now, in enumeration order.
    func snapshot() -> [MIDISourceSnapshot]
    /// Connects the input to this source; false when the system refused.
    func connect(_ handle: UInt32) -> Bool
    /// Disconnects the input from this source (harmless for a handle that no longer exists).
    func disconnect(_ handle: UInt32)
}

/// One reconcile's effect.
public struct MIDIReconcileResult: Sendable, Equatable {
    public var connected: [MIDIEndpointID] = []
    public var disconnected: [MIDIEndpointID] = []
    /// Disconnected because the source went away (absent, new handle or reported removed); ⊆ `disconnected`.
    public var lost: Set<MIDIEndpointID> = []

    public init() {}
}

/// The pure registry (contract H2).
public struct MIDISubscriptionRegistry: Sendable, Equatable {
    /// Stable ID → the handle with a live connection.
    public private(set) var entries: [MIDIEndpointID: UInt32] = [:]
    /// Handles the system reported removed since the last reconcile.
    public private(set) var removed: Set<UInt32> = []

    public init() {}

    public mutating func markRemoved(handle: UInt32) {
        removed.insert(handle)
    }

    /// The present inputs by stable ID (IDs assigned exactly as discovery assigns them).
    public static func presentSources(in snapshot: [MIDISourceSnapshot]) -> [MIDIEndpointID: MIDISourceSnapshot] {
        let listed: [MIDISourceSnapshot] = snapshot.filter { (item: MIDISourceSnapshot) -> Bool in item.record.transport != .network }
        let records: [MIDIEndpointRecord] = listed.map { (item: MIDISourceSnapshot) -> MIDIEndpointRecord in item.record }
        let ids: [MIDIEndpointID] = MIDIEndpointIdentity.assign(records)
        var present: [MIDIEndpointID: MIDISourceSnapshot] = [:]
        for (index, item) in listed.enumerated() where item.record.direction == .source && item.handle != 0 {
            present[ids[index]] = item
        }
        return present
    }

    /// Takes the live connections to: wanted ∩ present ∩ online, one per ID on its current handle.
    public mutating func reconcile(wanted: Set<MIDIEndpointID>, snapshot: [MIDISourceSnapshot],
                                   connect: (UInt32) -> Bool, disconnect: (UInt32) -> Void) -> MIDIReconcileResult {
        let present: [MIDIEndpointID: MIDISourceSnapshot] = Self.presentSources(in: snapshot)
        var result = MIDIReconcileResult()
        for (id, handle) in entries.sorted(by: { (a: (key: MIDIEndpointID, value: UInt32), b: (key: MIDIEndpointID, value: UInt32)) -> Bool in a.key < b.key }) {
            let current: MIDISourceSnapshot? = present[id]
            // Offline counts as gone: the source stopped delivering and its note-offs may be lost.
            let gone: Bool = current == nil || current?.handle != handle || removed.contains(handle)
                || current?.record.isOffline == true
            let keep: Bool = !gone && wanted.contains(id)
            if keep { continue }
            disconnect(handle)
            entries[id] = nil
            result.disconnected.append(id)
            if gone { result.lost.insert(id) }
        }
        removed.removeAll()
        for id in wanted.sorted() where entries[id] == nil {
            guard let source = present[id], !source.record.isOffline else { continue }
            if connect(source.handle) {
                entries[id] = source.handle
                result.connected.append(id)
            }
        }
        return result
    }

    /// Disconnects every entry (the input closed).
    public mutating func removeAll(disconnect: (UInt32) -> Void) {
        for handle in entries.values { disconnect(handle) }
        entries.removeAll()
        removed.removeAll()
    }
}

/// The input's subscriptions: a registry, the wanted IDs and coalesced system notifications (contract H3).
public final class MIDISourceSubscriptions: Sendable {
    public static let defaultCoalescingDelayNanoseconds: UInt64 = MIDIEndpointDiscovery.defaultCoalescingDelayNanoseconds

    private struct State {
        var registry = MIDISubscriptionRegistry()
        var wanted: Set<MIDIEndpointID> = []
        var isOpen = false
        var generation: UInt64 = 0
        var coalescer = MIDIRefreshCoalescer()
        var connectCalls = 0
        var disconnectCalls = 0
        var reconcileCount = 0
        var lossCount = 0
    }

    public let system: any MIDISourceSystem
    private let scheduler: MIDIRefreshScheduler
    private let delay: UInt64
    private let lockedState = Mutex(State())

    public init(system: any MIDISourceSystem,
                scheduler: MIDIRefreshScheduler = .serialQueue(label: "projectm.midi.input"),
                coalescingDelayNanoseconds: UInt64 = MIDISourceSubscriptions.defaultCoalescingDelayNanoseconds) {
        self.system = system
        self.scheduler = scheduler
        self.delay = coalescingDelayNanoseconds
    }

    // MARK: Reading (tests and diagnostics; never logged)

    public var activeHandles: [MIDIEndpointID: UInt32] {
        lockedState.withLock { (s: inout State) -> [MIDIEndpointID: UInt32] in s.registry.entries }
    }
    public var wanted: Set<MIDIEndpointID> { lockedState.withLock { (s: inout State) -> Set<MIDIEndpointID> in s.wanted } }
    public var isOpen: Bool { lockedState.withLock { (s: inout State) -> Bool in s.isOpen } }
    public var connectCalls: Int { lockedState.withLock { (s: inout State) -> Int in s.connectCalls } }
    public var disconnectCalls: Int { lockedState.withLock { (s: inout State) -> Int in s.disconnectCalls } }
    public var reconcileCount: Int { lockedState.withLock { (s: inout State) -> Int in s.reconcileCount } }
    /// Reconciles that lost at least one source since init (monotonic; MIDI-011-R5).
    public var lossCount: Int { lockedState.withLock { (s: inout State) -> Int in s.lossCount } }
    public var absorbedSignals: Int { lockedState.withLock { (s: inout State) -> Int in s.coalescer.absorbed } }

    // MARK: Lifecycle

    /// Opens (if closed) and reconciles now on the caller's thread.
    @discardableResult
    public func update(wanted: Set<MIDIEndpointID>) -> MIDIReconcileResult {
        lockedState.withLock { (s: inout State) -> MIDIReconcileResult in
            if !s.isOpen {
                s.isOpen = true
                s.generation += 1
                s.coalescer.reset()
            }
            s.wanted = wanted
            return reconcileLocked(&s)
        }
    }

    /// Any thread (the system's notification thread): one coalesced reconcile per burst; ignored while closed.
    public func setupChanged() {
        let generation: UInt64? = lockedState.withLock { (s: inout State) -> UInt64? in
            guard s.isOpen, s.coalescer.signal() else { return nil }
            return s.generation
        }
        guard let generation else { return }
        scheduler.schedule(delay) { [weak self] () -> Void in self?.scheduledReconcile(generation: generation) }
    }

    /// The system reported this source removed: its connection is dropped by the next reconcile even if the same
    /// handle is back by then.
    public func sourceRemoved(handle: UInt32) {
        let open: Bool = lockedState.withLock { (s: inout State) -> Bool in
            guard s.isOpen else { return false }
            s.registry.markRemoved(handle: handle)
            return true
        }
        if open { setupChanged() }
    }

    /// Disconnects everything; scheduled reconciles do nothing until the next `update`.
    public func close() {
        lockedState.withLock { (s: inout State) -> Void in
            let system: any MIDISourceSystem = self.system
            var calls = 0
            s.registry.removeAll { (handle: UInt32) -> Void in
                calls += 1
                system.disconnect(handle)
            }
            s.disconnectCalls += calls
            s.wanted = []
            s.isOpen = false
            s.generation += 1
            s.coalescer.reset()
        }
    }

    private func scheduledReconcile(generation: UInt64) {
        lockedState.withLock { (s: inout State) -> Void in
            guard s.isOpen, s.generation == generation else { return }
            s.coalescer.beginRefresh()
            _ = reconcileLocked(&s)
        }
    }

    private func reconcileLocked(_ s: inout State) -> MIDIReconcileResult {
        let system: any MIDISourceSystem = self.system
        let snapshot: [MIDISourceSnapshot] = system.snapshot()
        var connects = 0
        var disconnects = 0
        let result: MIDIReconcileResult = s.registry.reconcile(
            wanted: s.wanted, snapshot: snapshot,
            connect: { (handle: UInt32) -> Bool in
                connects += 1
                return system.connect(handle)
            },
            disconnect: { (handle: UInt32) -> Void in
                disconnects += 1
                system.disconnect(handle)
            })
        s.connectCalls += connects
        s.disconnectCalls += disconnects
        s.reconcileCount += 1
        if !result.lost.isEmpty { s.lossCount += 1 }
        return result
    }
}
