// MIDIInputService.swift — the shared MIDI input (MIDI-002-R1, R2, R5, R11; contracts/midi-input.md C3;
// research MIDI-002-D4, D5).
//
// One input and one ring per process: MIDI-002's monitor uses it, MIDI-003 learn will share it. The service
// opens the provider on `start`, connects exactly the given MIDI-001 source IDs, follows `updateSources`, and
// on `stop` closes the provider (no message reaches the ring after `close` returns) and discards unread events.
// Start and stop are idempotent; an `unavailable` open is reported and retried only by the next `start`.
// The service never sees which source sent a message: the provider writes plain `MIDIEvent`s into the ring.
import Synchronization

public protocol MIDIInputProvider: AnyObject, Sendable {
    /// Opens the input (idempotent); received messages go into `ring` from the provider's own thread.
    func open(into ring: MIDIEventRing) -> MIDIProviderStartResult
    /// Connects exactly these listed sources (MIDI-001 IDs), disconnecting the rest.
    func connect(sources: Set<MIDIEndpointID>)
    /// Disconnects every source; no message reaches the ring after it returns.
    func close()
}

public enum MIDIInputState: Sendable, Hashable {
    case off
    case receiving
    /// The system MIDI service could not be reached; `code` is the system status (0 when none exists).
    case unavailable(code: Int32)

    public var isReceiving: Bool { self == .receiving }
}

public final class MIDIInputService: Sendable {
    public let provider: any MIDIInputProvider
    public let ring: MIDIEventRing
    private let lockedState = Mutex<MIDIInputState>(.off)

    public init(provider: any MIDIInputProvider, capacity: Int = MIDIEventRing.defaultCapacity) {
        self.provider = provider
        self.ring = MIDIEventRing(capacity: capacity)
    }

    deinit { provider.close() }

    public var state: MIDIInputState { lockedState.withLock { (s: inout MIDIInputState) -> MIDIInputState in s } }

    /// off or unavailable → receiving (connected to `sources`) or unavailable; while receiving, the same as
    /// `updateSources`.
    public func start(sources: Set<MIDIEndpointID>) {
        if state.isReceiving {
            provider.connect(sources: sources)
            return
        }
        let result: MIDIProviderStartResult = provider.open(into: ring)
        switch result {
        case .started:
            lockedState.withLock { (s: inout MIDIInputState) -> Void in s = .receiving }
            provider.connect(sources: sources)
        case .unavailable(let code):
            lockedState.withLock { (s: inout MIDIInputState) -> Void in s = .unavailable(code: code) }
        }
    }

    /// Follows MIDI-001's list while receiving; ignored otherwise.
    public func updateSources(_ sources: Set<MIDIEndpointID>) {
        guard state.isReceiving else { return }
        provider.connect(sources: sources)
    }

    /// → off: every source disconnected, unread events discarded. Call from the ring's consumer thread.
    public func stop() {
        let previous: MIDIInputState = lockedState.withLock { (s: inout MIDIInputState) -> MIDIInputState in
            let old: MIDIInputState = s
            s = .off
            return old
        }
        guard previous != .off else { return }
        if previous.isReceiving { provider.close() }
        ring.discardAll()
    }

    /// The input over the system MIDI service; where none exists (Linux), every start is `unavailable`.
    public static func system() -> MIDIInputService {
        #if canImport(CoreMIDI)
        MIDIInputService(provider: CoreMIDIInputProvider())
        #else
        MIDIInputService(provider: UnavailableMIDIInputProvider())
        #endif
    }
}

/// A provider for platforms without a system MIDI service (Linux): every open is `unavailable(code: 0)`.
public final class UnavailableMIDIInputProvider: MIDIInputProvider {
    public init() {}
    public func open(into ring: MIDIEventRing) -> MIDIProviderStartResult { .unavailable(code: 0) }
    public func connect(sources: Set<MIDIEndpointID>) {}
    public func close() {}
}
