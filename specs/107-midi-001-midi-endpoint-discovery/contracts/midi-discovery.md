# Contract: MIDI Endpoint Discovery (MIDI-001)

## C1 Provider (`MIDIEndpointProvider`, PerformanceControl)

```swift
public enum MIDIProviderStartResult: Sendable, Equatable { case started; case unavailable(code: Int32) }

public protocol MIDIEndpointProvider: AnyObject, Sendable {
    /// Begins forwarding setup changes as `onChange()` (any thread). Idempotent.
    func start(onChange: @escaping @Sendable () -> Void) -> MIDIProviderStartResult
    /// Stops forwarding; no `onChange` after it returns.
    func stop()
    /// Reads every source and destination now (any thread except an audio thread).
    func currentEndpoints() -> [MIDIEndpointRecord]
}
```

- `CoreMIDIEndpointProvider` (`#if canImport(CoreMIDI)`): one client (`MIDIClientCreateWithBlock`)
  created on first start; forwards `msgSetupChanged`, `msgObjectAdded`, `msgObjectRemoved`,
  `msgPropertyChanged`; never creates ports, never touches network-session or Bluetooth APIs.
- `ScriptedMIDIEndpointProvider` (public, all platforms): `plug(_ records:)`, `unplug(uniqueIDs:)`,
  `rename(uniqueID:to:)`, `setOffline(uniqueID:_:)`, `setRecords(_:)`, `failStart(code:)`; every
  mutation calls `onChange` once while started (tests can also call `signal(times:)`).

## C2 Discovery (`MIDIEndpointDiscovery`)

```swift
public init(provider: any MIDIEndpointProvider,
            scheduler: MIDIRefreshScheduler = .serialQueue(),
            coalescingDelayNanoseconds: UInt64 = 100_000_000)
public func start()
public func stop()
public var state: MIDIDiscoveryState { get }
public var endpoints: MIDIEndpointList { get }
public func onUpdate(_ handler: @escaping @Sendable (MIDIDiscoveryUpdate) -> Void)
public func onStateChange(_ handler: @escaping @Sendable (MIDIDiscoveryState) -> Void)
```

- `start()` from `off`: provider start; `started` → `listening`, schedule the initial refresh
  (delay 0) whose update has `isInitial == true`; `unavailable` → `unavailable(code)`. `start()`
  while listening is a no-op.
- Each provider signal goes through `MIDIRefreshCoalescer`; at most one refresh is pending.
- A refresh reads records, builds the list, diffs with the previous list and calls `onUpdate`
  only when there are changes or it is the initial refresh.
- `stop()`: provider stop, list cleared, generation bumped (a pending refresh does nothing), state
  `off`. Handlers run outside the lock on the scheduler's queue (or the caller's thread for
  state changes made by `start`/`stop`).
- `MIDIRefreshScheduler`: `schedule(afterNanoseconds:_:)`; `.serialQueue()` uses one private
  `DispatchQueue` (utility QoS); tests use `ManualMIDIScheduler` (`runAll()`, `pendingCount`).

## C3 App (`MIDIDiscoveryCoordinator`)

- Runs discovery iff `settings.midiEnabled && appIsActive`; `setEnabled(_:)`, `sceneBecame(active:)`.
- `state`, `rows: [MIDIEndpointRow]` (id, title, detail, accessibility label) on the main actor.
- `statusText(state:enabled:count:)`: off → "Off"; enabled but inactive → "Paused while projectM is
  in the background."; listening 0 → "Listening — no MIDI devices"; 1 → "Listening — 1 device";
  n → "Listening — n devices"; unavailable → "MIDI isn't available on this device."
- Row detail: "Input" or "Output", then ", Virtual" and/or ", Offline"; accessibility label
  "<name>, <detail>".
- `announcement(for changes:)`: research MIDI-001-D7; `nil` for an initial update or no
  appear/disappear.
- Count in the status counts endpoints shown (inputs and outputs).

## C4 Settings UI (`MIDISettingsSection`)

| Element | Identifier | Text |
|---|---|---|
| Toggle | `midiListenToggle` | "Listen for MIDI devices" |
| Status | `midiStatus` | status text (label "MIDI status", value the text) |
| Row | `midiEndpoint.<id description>` | name + detail; one combined label |
| Footer | — | "Shows MIDI devices connected to this device and MIDI apps running on it. projectM only looks while this is on and the app is open, never uses the network, and keeps no device names." |
| DEBUG Plug / Unplug | `midiFakePlug` / `midiFakeUnplug` | "Plug Fake Keys" / "Unplug Fake Keys" (only with `-uitestFakeMIDI`) |

## C5 Guards

- `scripts/check_compliance.py`: `MIDINetworkSession`, `MIDINetworkHost`, `MIDINetworkConnection`,
  `CABTMIDICentralViewController`, `CABTMIDILocalPeripheralViewController` anywhere in Swift/ObjC
  sources → violation (MIDI-001-R2, R14).
- `scripts/check_network_symbols.py`: an imported symbol containing `MIDINetwork` → violation.
- `scripts/run_device_tests.py` `ALLOWED_KEYS` gains `settings.midi.enabled`.
- `scripts/check_status_events.py` `CHECKED` gains `Coordinators/MIDIDiscoveryCoordinator.swift`
  and `Views/MIDISettingsSection.swift` (no direct accessibility posts).
