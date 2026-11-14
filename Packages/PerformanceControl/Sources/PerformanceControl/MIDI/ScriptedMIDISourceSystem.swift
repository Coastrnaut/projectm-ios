// ScriptedMIDISourceSystem.swift — an in-memory MIDI system with endpoint handles (MIDI-011-R7, R9; research
// MIDI-011-D6; contracts/hotplug.md H1, H4).
//
// Used by the package and app tests and, through the app's DEBUG-only `-uitestFakeMIDI`, by UI tests. Every plug gives
// an endpoint a new handle (or a chosen one, to model a reused reference); unplugging drops the system's connections
// to it and notifies removal and a setup change, like CoreMIDI. Connections are counted per handle, so a duplicate
// subscription shows as 2 and `send` then delivers the message twice: the acceptance can see "one live listener".
// A Release build of the app never creates one.
import Synchronization

public final class ScriptedMIDISourceSystem: MIDISourceSystem {
    public typealias Receiver = @Sendable (_ bytes: [UInt8], _ timestamp: UInt64) -> Void

    private struct State {
        var endpoints: [MIDISourceSnapshot] = []
        var nextHandle: UInt32 = 0x100
        var connections: [UInt32: Int] = [:]
        var refused: Set<Int32> = []
        var connectCalls = 0
        var disconnectCalls = 0
        var onChange: (@Sendable () -> Void)?
        var onRemoved: (@Sendable (UInt32) -> Void)?
        var receiver: Receiver?
    }

    private let lockedState = Mutex(State())

    public init(records: [MIDIEndpointRecord] = []) {
        lockedState.withLock { (s: inout State) -> Void in
            for record in records { Self.append(record, handle: nil, to: &s) }
        }
    }

    private static func append(_ record: MIDIEndpointRecord, handle: UInt32?, to s: inout State) {
        let assigned: UInt32
        if let handle {
            assigned = handle
        } else {
            assigned = s.nextHandle
            s.nextHandle += 1
        }
        s.endpoints.append(MIDISourceSnapshot(handle: assigned, record: record))
    }

    // MARK: Wiring (the input provider)

    public func setNotificationHandlers(onChange: @escaping @Sendable () -> Void,
                                        onRemoved: @escaping @Sendable (UInt32) -> Void) {
        lockedState.withLock { (s: inout State) -> Void in
            s.onChange = onChange
            s.onRemoved = onRemoved
        }
    }

    public func setReceiver(_ receiver: Receiver?) {
        lockedState.withLock { (s: inout State) -> Void in s.receiver = receiver }
    }

    // MARK: MIDISourceSystem

    public func snapshot() -> [MIDISourceSnapshot] {
        lockedState.withLock { (s: inout State) -> [MIDISourceSnapshot] in
            s.endpoints.map { (item: MIDISourceSnapshot) -> MIDISourceSnapshot in
                item.record.direction == .source ? item : MIDISourceSnapshot(handle: 0, record: item.record)
            }
        }
    }

    public func connect(_ handle: UInt32) -> Bool {
        lockedState.withLock { (s: inout State) -> Bool in
            s.connectCalls += 1
            guard let item = s.endpoints.first(where: { (e: MIDISourceSnapshot) -> Bool in e.handle == handle }),
                  item.record.direction == .source, !s.refused.contains(item.record.uniqueID) else { return false }
            s.connections[handle, default: 0] += 1
            return true
        }
    }

    public func disconnect(_ handle: UInt32) {
        lockedState.withLock { (s: inout State) -> Void in
            s.disconnectCalls += 1
            guard let count = s.connections[handle] else { return }
            s.connections[handle] = count > 1 ? count - 1 : nil
        }
    }

    // MARK: Script

    /// Adds endpoints, each with a new handle; returns the handles. Notifies a setup change.
    @discardableResult
    public func plug(_ records: [MIDIEndpointRecord]) -> [UInt32] {
        let handles: [UInt32] = lockedState.withLock { (s: inout State) -> [UInt32] in
            var added: [UInt32] = []
            for record in records {
                Self.append(record, handle: nil, to: &s)
                added.append(s.endpoints[s.endpoints.count - 1].handle)
            }
            return added
        }
        notify(removed: [])
        return handles
    }

    /// Adds one endpoint with a chosen handle (a reference the system reused). Notifies a setup change.
    public func plug(_ record: MIDIEndpointRecord, handle: UInt32) {
        lockedState.withLock { (s: inout State) -> Void in Self.append(record, handle: handle, to: &s) }
        notify(removed: [])
    }

    /// Removes every endpoint with one of these unique numbers; the system drops its connections to them. Notifies
    /// each removed source, then a setup change.
    public func unplug(uniqueIDs: Set<Int32>) {
        let removed: [UInt32] = lockedState.withLock { (s: inout State) -> [UInt32] in
            var handles: [UInt32] = []
            for item in s.endpoints where uniqueIDs.contains(item.record.uniqueID) {
                if item.record.direction == .source { handles.append(item.handle) }
                s.connections[item.handle] = nil
            }
            s.endpoints.removeAll { (item: MIDISourceSnapshot) -> Bool in uniqueIDs.contains(item.record.uniqueID) }
            return handles
        }
        notify(removed: removed)
    }

    public func setOffline(uniqueID: Int32, _ offline: Bool) {
        lockedState.withLock { (s: inout State) -> Void in
            for index in s.endpoints.indices where s.endpoints[index].record.uniqueID == uniqueID {
                s.endpoints[index].record.isOffline = offline
            }
        }
        notify(removed: [])
    }

    /// Connect calls for this unique number fail from now on (true) or succeed again (false).
    public func refuseConnects(uniqueID: Int32, _ refuse: Bool) {
        lockedState.withLock { (s: inout State) -> Void in
            if refuse { s.refused.insert(uniqueID) } else { s.refused.remove(uniqueID) }
        }
    }

    /// `times` setup notifications with nothing changed (a burst).
    public func signal(times: Int = 1) {
        let handler: (@Sendable () -> Void)? = lockedState.withLock { (s: inout State) -> (@Sendable () -> Void)? in s.onChange }
        guard let handler, times > 0 else { return }
        for _ in 0..<times { handler() }
    }

    private func notify(removed: [UInt32]) {
        let handlers: (change: (@Sendable () -> Void)?, removed: (@Sendable (UInt32) -> Void)?) = lockedState.withLock {
            (s: inout State) -> (change: (@Sendable () -> Void)?, removed: (@Sendable (UInt32) -> Void)?) in
            (s.onChange, s.onRemoved)
        }
        if let onRemoved = handlers.removed {
            for handle in removed { onRemoved(handle) }
        }
        handlers.change?()
    }

    /// Delivers MIDI 1.0 bytes from the source with this unique number once per live connection to its current
    /// handle; returns the number of deliveries (0: absent or not connected; 2 would be a duplicate subscription).
    @discardableResult
    public func send(_ bytes: [UInt8], from uniqueID: Int32, timestamp: UInt64) -> Int {
        let delivery: (count: Int, receiver: Receiver?) = lockedState.withLock { (s: inout State) -> (count: Int, receiver: Receiver?) in
            var count = 0
            for item in s.endpoints where item.record.uniqueID == uniqueID && item.record.direction == .source {
                count += s.connections[item.handle] ?? 0
            }
            return (count, s.receiver)
        }
        guard let receiver = delivery.receiver, delivery.count > 0 else { return 0 }
        for _ in 0..<delivery.count { receiver(bytes, timestamp) }
        return delivery.count
    }

    // MARK: Reading

    public var connectCalls: Int { lockedState.withLock { (s: inout State) -> Int in s.connectCalls } }
    public var disconnectCalls: Int { lockedState.withLock { (s: inout State) -> Int in s.disconnectCalls } }
    /// Live connections to the current handle(s) of this unique number.
    public func liveConnections(uniqueID: Int32) -> Int {
        lockedState.withLock { (s: inout State) -> Int in
            var count = 0
            for item in s.endpoints where item.record.uniqueID == uniqueID { count += s.connections[item.handle] ?? 0 }
            return count
        }
    }
    /// Every live connection, present endpoints or not.
    public var totalConnections: Int {
        lockedState.withLock { (s: inout State) -> Int in s.connections.values.reduce(0, +) }
    }
    public func handles(uniqueID: Int32) -> [UInt32] {
        lockedState.withLock { (s: inout State) -> [UInt32] in
            s.endpoints.filter { (item: MIDISourceSnapshot) -> Bool in item.record.uniqueID == uniqueID }
                .map { (item: MIDISourceSnapshot) -> UInt32 in item.handle }
        }
    }
}

/// A MIDI input over a `ScriptedMIDISourceSystem`: connections go through `MIDISourceSubscriptions`, and delivered
/// bytes are parsed into the ring while open (one sender at a time: the ring has one producer).
public final class ScriptedMIDISourceInputProvider: MIDIInputProvider {
    private struct State {
        var ring: MIDIEventRing?
        var parser = MIDIByteStreamParser()
        var openCount = 0
        var closeCount = 0
    }

    public let system: ScriptedMIDISourceSystem
    public let subscriptions: MIDISourceSubscriptions
    private let lockedState = Mutex(State())

    public init(system: ScriptedMIDISourceSystem,
                scheduler: MIDIRefreshScheduler = .serialQueue(label: "projectm.midi.input.scripted"),
                coalescingDelayNanoseconds: UInt64 = MIDISourceSubscriptions.defaultCoalescingDelayNanoseconds) {
        self.system = system
        let subscriptions = MIDISourceSubscriptions(system: system, scheduler: scheduler,
                                                    coalescingDelayNanoseconds: coalescingDelayNanoseconds)
        self.subscriptions = subscriptions
        system.setNotificationHandlers(
            onChange: { [weak subscriptions] () -> Void in subscriptions?.setupChanged() },
            onRemoved: { [weak subscriptions] (handle: UInt32) -> Void in subscriptions?.sourceRemoved(handle: handle) })
        system.setReceiver { [weak self] (bytes: [UInt8], timestamp: UInt64) -> Void in self?.deliver(bytes, timestamp: timestamp) }
    }

    // MARK: MIDIInputProvider

    public func open(into ring: MIDIEventRing) -> MIDIProviderStartResult {
        lockedState.withLock { (s: inout State) -> MIDIProviderStartResult in
            s.openCount += 1
            s.ring = ring
            return .started
        }
    }

    public func connect(sources: Set<MIDIEndpointID>) {
        subscriptions.update(wanted: sources)
    }

    public func close() {
        lockedState.withLock { (s: inout State) -> Void in
            s.ring = nil
            s.parser = MIDIByteStreamParser()
            s.closeCount += 1
        }
        subscriptions.close()
    }

    public var sourceLossCount: Int { subscriptions.lossCount }

    // MARK: Script

    public var isOpen: Bool { lockedState.withLock { (s: inout State) -> Bool in s.ring != nil } }
    public var openCount: Int { lockedState.withLock { (s: inout State) -> Int in s.openCount } }
    public var closeCount: Int { lockedState.withLock { (s: inout State) -> Int in s.closeCount } }

    /// Sends bytes from a source (see `ScriptedMIDISourceSystem.send`); returns the deliveries.
    @discardableResult
    public func send(_ bytes: [UInt8], from uniqueID: Int32, timestamp: UInt64) -> Int {
        system.send(bytes, from: uniqueID, timestamp: timestamp)
    }

    private func deliver(_ bytes: [UInt8], timestamp: UInt64) {
        lockedState.withLock { (s: inout State) -> Void in
            guard var ring = s.ring else { return }
            var parser: MIDIByteStreamParser = s.parser
            bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
                parser.feed(buffer, timestamp: timestamp, into: &ring)
            }
            s.parser = parser
        }
    }
}
