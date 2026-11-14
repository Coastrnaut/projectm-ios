// ScriptedMIDIInputProvider.swift — an in-memory MIDI input (contract C3; research MIDI-002-D2).
//
// Used by the package and app tests and, through the app's DEBUG-only `-uitestFakeMIDI`, by UI tests. `send`
// parses MIDI 1.0 bytes (running status included) into the ring, but only while the input is open and at
// least one source is connected, like a port that receives only from connected sources. One sender at a time
// (the ring has one producer). A Release build of the app never creates one (MIDI-002-R12).
import Synchronization

public final class ScriptedMIDIInputProvider: MIDIInputProvider {
    private struct State {
        var ring: MIDIEventRing?
        var connected: Set<MIDIEndpointID> = []
        var parser = MIDIByteStreamParser()
        var failCode: Int32?
        var openCount = 0
        var closeCount = 0
    }

    private let lockedState = Mutex(State())

    public init() {}

    // MARK: MIDIInputProvider

    public func open(into ring: MIDIEventRing) -> MIDIProviderStartResult {
        lockedState.withLock { (s: inout State) -> MIDIProviderStartResult in
            s.openCount += 1
            if let code = s.failCode { return .unavailable(code: code) }
            s.ring = ring
            return .started
        }
    }

    public func connect(sources: Set<MIDIEndpointID>) {
        lockedState.withLock { (s: inout State) -> Void in s.connected = sources }
    }

    public func close() {
        lockedState.withLock { (s: inout State) -> Void in
            s.ring = nil
            s.connected = []
            s.parser = MIDIByteStreamParser()
            s.closeCount += 1
        }
    }

    // MARK: Script

    public var connectedSources: Set<MIDIEndpointID> {
        lockedState.withLock { (s: inout State) -> Set<MIDIEndpointID> in s.connected }
    }
    public var isOpen: Bool { lockedState.withLock { (s: inout State) -> Bool in s.ring != nil } }
    public var openCount: Int { lockedState.withLock { (s: inout State) -> Int in s.openCount } }
    public var closeCount: Int { lockedState.withLock { (s: inout State) -> Int in s.closeCount } }

    /// The next opens report `unavailable(code:)`; nil restores normal opens.
    public func failOpen(code: Int32?) {
        lockedState.withLock { (s: inout State) -> Void in s.failCode = code }
    }

    /// Delivers MIDI 1.0 bytes; returns false (nothing delivered) when closed or no source is connected.
    @discardableResult
    public func send(_ bytes: [UInt8], timestamp: UInt64) -> Bool {
        lockedState.withLock { (s: inout State) -> Bool in
            guard var ring = s.ring, !s.connected.isEmpty else { return false }
            var parser: MIDIByteStreamParser = s.parser
            bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
                parser.feed(buffer, timestamp: timestamp, into: &ring)
            }
            s.parser = parser
            return true
        }
    }
}
