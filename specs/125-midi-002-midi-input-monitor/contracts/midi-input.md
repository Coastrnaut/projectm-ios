# Contract: MIDI Input and Monitor (MIDI-002)

## C1 Decoders (PerformanceControl, pure)

```swift
public protocol MIDIEventSink { mutating func receive(_ event: MIDIEvent) }

public struct MIDIUMPDecoder: Sendable {
    public init()
    /// Decodes MIDI 1.0 protocol UMP words; SysEx7 lengths carry across calls.
    public mutating func decode<Sink: MIDIEventSink>(_ words: UnsafeBufferPointer<UInt32>,
                                                     timestamp: UInt64, into sink: inout Sink)
}

public struct MIDIByteStreamParser: Sendable {
    public init()
    public mutating func feed<Sink: MIDIEventSink>(_ bytes: UnsafeBufferPointer<UInt8>,
                                                   timestamp: UInt64, into sink: inout Sink)
}
```

`MIDIEventRing` and `MIDIEventCollector` (an array, tests only) conform to `MIDIEventSink`.

## C2 Ring

```swift
public final class MIDIEventRing: MIDIEventSink, @unchecked Sendable {
    public static let defaultCapacity = 512
    public init(capacity: Int = MIDIEventRing.defaultCapacity)
    public func push(_ event: MIDIEvent)              // producer; real-time safe
    public func drain(into: inout [MIDIEvent], maxCount: Int) -> Int   // consumer
    public func discardAll()                          // consumer
    public var dropped: Int, clockCount: Int, activeSensingCount: Int, availableToRead: Int
}
```

## C3 Provider and service

```swift
public protocol MIDIInputProvider: AnyObject, Sendable {
    /// Opens the input (idempotent); received messages go into `ring` from the provider's thread.
    func open(into ring: MIDIEventRing) -> MIDIProviderStartResult
    /// Connects exactly these listed sources (MIDI-001 IDs), disconnecting the rest.
    func connect(sources: Set<MIDIEndpointID>)
    /// Disconnects every source; no message reaches the ring after it returns.
    func close()
}

public final class MIDIInputService: Sendable {
    public init(provider: any MIDIInputProvider, capacity: Int = MIDIEventRing.defaultCapacity)
    public let ring: MIDIEventRing
    public var state: MIDIInputState { get }
    public func start(sources: Set<MIDIEndpointID>)   // off → receiving | unavailable
    public func updateSources(_ sources: Set<MIDIEndpointID>)   // only while receiving
    public func stop()                                // → off; discards unread events
}
```

- `CoreMIDIInputProvider` (`#if canImport(CoreMIDI)`); elsewhere `MIDIInputService.system()` uses
  `UnavailableMIDIInputProvider` (every open is `unavailable(code: 0)`).
- `ScriptedMIDIInputProvider`: `send(_ bytes: [UInt8], timestamp: UInt64)` parses and pushes only
  while open and at least one source is connected; `connectedSources`, `openCount`, `closeCount`.

## C4 App

- `MIDIInputCoordinator` (`@MainActor`): `addClient(_ name: String, handler:)`,
  `removeClient(_:)`, `drain()`; receives iff a client exists and discovery is listening; sources
  = online `.source` endpoints of discovery's list; `isReceiving`.
- `MIDIMonitorCoordinator` (`@MainActor @Observable`): `open()`, `close()`, `togglePause()`,
  `clear()`, `entries`, `isPaused`, `summaryText`, `statusText`; `entryLimit = 64`.
- `MIDIMonitorView`: identifiers `midiMonitorPause`, `midiMonitorClear`, `midiMonitorStatus`,
  `midiMonitorSummary`, rows `midiMonitorEntry.<id>` with the combined label; DEBUG with
  `-uitestFakeMIDI`: `midiFakeSendCC` (B0 07 64), `midiFakeSendNote` (90 3C 64).
- `MIDISettingsSection`: a "MIDI Monitor" navigation row, identifier `midiMonitorLink`.
