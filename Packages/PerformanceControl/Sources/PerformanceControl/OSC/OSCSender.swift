// OSCSender.swift — the optional OSC sender's engine (OSC-005-R4 to R9; contracts/osc-send.md S2; research
// OSC-005-D4, D5).
//
// * Pure Swift: the network lives behind `OSCSendTransport`; the one real transport (`NetworkOSCSender`) is in
//   `OSCTransport/`, the only folder FR-068 (amended, ADR-0008) allows the Network framework; ADR-0088.
// * `configure(destination:)` is the whole on/off: a destination means "send now" (the app passes nil unless
//   Send OSC, the OSC network switch, the foreground and the allow list all agree). nil closes the transport at
//   once: the transport drops sends it has queued but not run, and no message is made afterwards (R5).
// * `post` encodes one event with `OSCEncoder` only when active and its kind is chosen, then applies the 60/s cap
//   (R9). All state sits under one lock; the transport call is a hand-off to its own queue.
import Synchronization

/// What a send transport reports, on its own queue.
public enum OSCSendTransportEvent: Sendable, Hashable {
    /// The path to the destination is usable.
    case ready
    /// The system refused or lost the path (for example Local Network is off); no automatic retry.
    case failed(OSCListenerFailure)
}

/// A one-destination UDP sender (contract S2).
public protocol OSCSendTransport: AnyObject, Sendable {
    /// Opens a flow to `host:port` (already validated); reports events on the transport's queue.
    func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void)
    /// Sends one datagram on the open flow; dropped when nothing is open.
    func send(_ bytes: [UInt8])
    /// Cancels the flow at once: sends not yet handed to the system are dropped and no event follows.
    func close()
}

public enum OSCSenderState: Sendable, Hashable {
    case off
    case connecting(OSCSendDestination)
    case ready(OSCSendDestination)
    case failed(OSCSendDestination, OSCListenerFailure)
}

/// What `post` did with an event.
public enum OSCSendOutcome: Sendable, Hashable {
    case sent
    /// No destination is configured (sending is off or paused).
    case inactive
    /// The user did not choose this kind.
    case kindOff
    /// Over the 60/s cap; dropped and counted.
    case rateLimited
}

public struct OSCSenderCounters: Sendable, Hashable {
    public var sent = 0
    public var dropped = 0
    public init() {}
}

public final class OSCSender: Sendable {
    private struct State {
        var destination: OSCSendDestination?
        var state: OSCSenderState = .off
        var kinds: Set<OSCSendKind> = OSCSendKind.defaults
        var includeSceneNames = false
        var cap = OSCSendRateCap()
        var counters = OSCSenderCounters()
        /// Bumped on every configure, so a late event from an earlier flow is ignored.
        var generation: UInt64 = 0
        var onStateChange: (@Sendable (OSCSenderState) -> Void)?
    }

    private let transport: any OSCSendTransport
    private let clock: OSCMonotonicClock
    private let lock = Mutex(State())

    public init(transport: any OSCSendTransport, clock: OSCMonotonicClock = .continuous()) {
        self.transport = transport
        self.clock = clock
    }

    public var state: OSCSenderState { lock.withLock { $0.state } }
    public var destination: OSCSendDestination? { lock.withLock { $0.destination } }
    public var counters: OSCSenderCounters { lock.withLock { $0.counters } }

    /// Called on the transport's queue (or the caller's) after each state change.
    public func onStateChange(_ handler: (@Sendable (OSCSenderState) -> Void)?) {
        lock.withLock { $0.onStateChange = handler }
    }

    public func setOptions(kinds: Set<OSCSendKind>, includeSceneNames: Bool) {
        lock.withLock { s in
            s.kinds = kinds
            s.includeSceneNames = includeSceneNames
        }
    }

    /// nil stops sending at once (R5); a destination opens a flow to it (a different one replaces the old flow).
    public func configure(destination: OSCSendDestination?) {
        let change: (close: Bool, open: (OSCSendDestination, UInt64)?, handler: (@Sendable (OSCSenderState) -> Void)?, state: OSCSenderState?) =
            lock.withLock { s in
                guard s.destination != destination else { return (false, nil, nil, nil) }
                let wasOpen: Bool = s.destination != nil
                s.destination = destination
                s.generation &+= 1
                s.cap.reset()
                if let destination {
                    s.state = .connecting(destination)
                    return (wasOpen, (destination, s.generation), s.onStateChange, s.state)
                }
                s.state = .off
                return (wasOpen, nil, s.onStateChange, s.state)
            }
        if change.close { transport.close() }
        if let (destination, generation) = change.open {
            transport.open(host: destination.host, port: destination.port) { [weak self] (event: OSCSendTransportEvent) -> Void in
                self?.transportEvent(event, generation: generation)
            }
        }
        if let state = change.state { change.handler?(state) }
    }

    private func transportEvent(_ event: OSCSendTransportEvent, generation: UInt64) {
        let update: (handler: (@Sendable (OSCSenderState) -> Void)?, state: OSCSenderState)? = lock.withLock { s in
            guard s.generation == generation, let destination = s.destination else { return nil }
            switch event {
            case .ready: s.state = .ready(destination)
            case .failed(let failure): s.state = .failed(destination, failure)
            }
            return (s.onStateChange, s.state)
        }
        if let update { update.handler?(update.state) }
    }

    /// Encodes and sends `event` when active and chosen, within the cap (R4, R6, R9).
    @discardableResult
    public func post(_ event: OSCSendEvent) -> OSCSendOutcome {
        let now: UInt64 = clock.now()
        let transport: any OSCSendTransport = self.transport
        return lock.withLock { s -> OSCSendOutcome in
            guard s.destination != nil else { return .inactive }
            guard s.kinds.contains(event.kind) else { return .kindOff }
            guard s.cap.admit(now: now) else {
                s.counters.dropped += 1
                return .rateLimited
            }
            s.counters.sent += 1
            let message: OSCMessage = OSCSendMessages.message(for: event, includeSceneNames: s.includeSceneNames)
            // Under the lock, so a send never overtakes a concurrent configure(nil); `send` only enqueues.
            transport.send(OSCEncoder.encode(message))
            return .sent
        }
    }
}
