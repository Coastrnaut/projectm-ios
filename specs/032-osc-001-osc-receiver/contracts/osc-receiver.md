# Contract: OSC receiver (PerformanceControl)

Module `PerformanceControl`. Everything here except the `OSCTransport/` types builds on Linux.

## C1 Decoder

```swift
public enum OSCDecoder {
    public static func decode(_ bytes: [UInt8]) -> Result<OSCMessage, OSCDecodeError>
}
public enum OSCEncoder {
    public static func encode(_ message: OSCMessage) -> [UInt8]
}
```

- C1.1 Size is checked first: more than `OSCLimits.maximumDatagramBytes` → `.oversized` with no
  further reads.
- C1.2 Every read checks the remaining length; the function never traps on any input.
- C1.3 For every `m` with a valid address and ≤ 16 float/int arguments,
  `decode(encode(m)) == .success(m)` (NaN floats compare by bit pattern in tests).
- C1.4 Any accepted input re-encodes to the same bytes.

## C2 Peer scope

`OSCPeerAddress.isLocal` as research OSC-001-D2. The transport drops non-local peers before reading.

## C3 Dispatcher

```swift
public final class OSCDispatcher: Sendable {
    public init(store: ParameterStore, routes: [OSCRoute])
    public func handle(_ datagram: [UInt8]) -> OSCDispatchOutcome
    public func noteOversized(_ byteCount: Int)
    public func noteDroppedNonLocal()
    public var counters: OSCReceiverCounters { get }
}
```

- C3.1 A message whose address matches a route and has exactly one `f` or `i` argument is applied
  with `store.setDouble`, only if the parameter's `modulation.allowsExternalControl` is true.
- C3.2 The store clamps; a non-finite value is refused by the store (`refusedByStore`).
- C3.3 Every call updates the counters; counters never hold payloads or addresses.

## C4 Transport protocol

```swift
public protocol OSCDatagramTransport: AnyObject, Sendable {
    /// Opens the port (0 = any free port) and reports events on the transport's own queue.
    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void)
    /// Cancels the listener and every peer; reports `.cancelled` exactly once afterwards.
    func stop()
}
```

- C4.1 After `stop()`, no `.datagram` event is delivered.
- C4.2 `NetworkDatagramTransport` (in `OSCTransport/`, `#if canImport(Network)`): UDP `NWListener`,
  cellular prohibited, peers checked with `OSCPeerAddress.isLocal`, at most 8 peers (oldest cancelled), datagrams over the
  limit reported as `.oversized` without copying.

## C5 Receiver

```swift
public final class OSCReceiver: Sendable {
    public init(store: ParameterStore = OSCReceiverCatalog.makeStore(),
                routes: [OSCRoute] = OSCReceiverCatalog.routes,
                makeTransport: @escaping @Sendable () -> (any OSCDatagramTransport)?)
    public static func system() -> OSCReceiver        // NetworkDatagramTransport where available
    public var state: OSCReceiverState { get }
    public var counters: OSCReceiverCounters { get }
    public var testValue: Double { get }
    public func start(port: UInt16)
    public func stop()
    public func onStateChange(_ handler: @escaping @Sendable (OSCReceiverState) -> Void)
    public func observeTestValue(_ handler: @escaping @Sendable (Double) -> Void) -> ParameterObservation
}
```

- C5.1 State machine as data-model.md; handlers run on the transport's queue (never the main
  thread); callers hop to their own actor.
- C5.2 `start` with no transport available → `failed(port, .unavailable)`.
- C5.3 `stop()` from `off` is a no-op; `stop()` while `failed` goes straight to `off`.

## C6 App

- `AppSettings.oscEnabled` (`settings.osc.enabled`, default false), `AppSettings.oscPort`
  (`settings.osc.port`, default 9000).
- `OSCReceiverCoordinator` (main actor): `isEnabled`, `port`, `statusText`, `testValue`,
  `portError`; `setEnabled(_:)`, `submitPort(_ text:)`, `sceneBecame(active:)`. Listening iff
  enabled ∧ scene active.
- Settings identifiers: `oscReceiverToggle`, `oscPortField`, `oscStatus`, `oscTestValue`,
  `oscPortError`.
- DEBUG launch argument for tests: none needed; UI tests set `-settings.osc.port <n>` and
  `-settings.osc.enabled NO` through the arguments domain.
