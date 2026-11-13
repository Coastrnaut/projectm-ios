# Data Model: OSC-001 OSC Receiver

## OSCArgument (enum, Sendable, Hashable)

| Case | Payload | Wire tag |
|---|---|---|
| `float` | `Float` (IEEE 754, big-endian on the wire) | `f` |
| `int` | `Int32` (two's complement, big-endian) | `i` |

`numericValue: Double?` converts either to `Double`. OSC-002 adds `string`, `blob` and others.

## OSCMessage (struct, Sendable, Hashable)

- `address: String`: starts with `/`, 1…255 bytes of printable ASCII (0x21-0x7E).
- `arguments: [OSCArgument]`: 0…16 entries.

## OSCDecodeError (enum, Sendable, Hashable)

`oversized(byteCount)`, `empty`, `notAligned`, `unterminatedString`, `badPadding`,
`invalidAddress`, `missingTypeTags`, `tooManyArguments`, `unsupportedTypeTag(UInt8)`,
`truncatedArgument`, `trailingBytes`, `bundleUnsupported`. Each has a stable `reason` string used as
a counter key.

## OSCLimits

`maximumDatagramBytes = 1472`, `maximumAddressBytes = 255`, `maximumArguments = 16`.

## OSCPeerAddress (enum, Sendable, Hashable)

`ipv4(UInt8, UInt8, UInt8, UInt8)`, `ipv6([UInt8])` (16 bytes). `isLocal` per research
OSC-001-D2. Built from raw bytes by the transport; never stored or logged.

## OSCPort

- `range = 1024...65535`, `defaultPort = 9000`.
- `parse(_ text: String) -> UInt16?`: trims whitespace; digits only; within range.

## OSCRoute and OSCReceiverCatalog

- `OSCRoute { address: String; parameter: ParameterID }`.
- Catalog: `testValueID = "osc.receiver.testValue"`, `testAddress = "/projectm/test"`, descriptor
  continuous 0…1 default 0, unit `.none`, group `osc.receiver` ("OSC receiver"), policy
  `ModulationPolicy(isModulatable: false, mixModes: [], allowsExternalControl: true)`.
  `makeRegistry()`, `routes = [OSCRoute(testAddress → testValueID)]`.

## OSCDispatchOutcome (enum)

`applied(ParameterID, Double)`, `rejected(OSCDecodeError)`, `unknownAddress`, `wrongArguments`,
`notExternallyControllable`, `refusedByStore`.

## OSCReceiverCounters (struct, Sendable, Equatable)

`received`, `applied`, `ignored` (unknown address, wrong arguments, policy, store refusal),
`rejected` (decode errors), `droppedNonLocal`, `rejectedByReason: [String: Int]` (keys are
`OSCDecodeError.reason`). In memory only.

## OSCListenerFailure (enum, Sendable, Hashable)

`portInUse`, `localNetworkDenied`, `unavailable` (no transport on this platform), `other(String)`
(a short code such as `posix 13`; never a peer address).

## OSCReceiverState (enum, Sendable, Hashable)

```text
off ──start(p)──▶ starting(p) ──ready(q)──▶ listening(q)
 ▲                   │  │                        │
 │                   │  └─failed(f)──▶ failed(p, f)
 │                   │                           │
 └──cancelled── stopping ◀──stop()───────────────┘ (from any non-off state)
```

- `start(p)` from any state cancels the current transport first (port change = stop + start).
- A failure leaves the transport cancelled; no automatic retry (OSC-001-R3).
- Events carry the generation that produced them; stale generations are ignored.
- `isListening` is true only in `listening`.

## OSCTransportEvent (enum, Sendable)

`ready(port: UInt16)`, `failed(OSCListenerFailure)`, `datagram([UInt8])`, `oversized(Int)`,
`droppedNonLocal`, `cancelled`.

## App settings (UserDefaults)

| Key | Type | Absent / invalid |
|---|---|---|
| `settings.osc.enabled` | Bool | off |
| `settings.osc.port` | Int | 9000 (any value outside 1024-65535 → 9000) |
