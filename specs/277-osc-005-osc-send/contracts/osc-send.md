# Contract: OSC-005 OSC Send

## S1 Wire format (OSC 1.0 messages, one per UDP datagram)

| Event | Address | Type tags | Arguments |
|---|---|---|---|
| Scene applied, names off | `/projectm/scene` | `,` | none |
| Scene applied, names on | `/projectm/scene` | `,s` | scene name, ≤ 64 UTF-8 bytes, cut at a character boundary |
| Beat | `/projectm/beat` | `,i` | beat number n ≥ 1 since sending started (wraps to 1 after 2^31−1) |
| Source started / stopped | `/projectm/status` | `,s` | `started` / `stopped` |

Strings are NUL-terminated and zero-padded to 4 bytes; `i` is big-endian two's complement. Example: beat 1 =
`2f 70 72 6f 6a 65 63 74 6d 2f 62 65 61 74 00 00 2c 69 00 00 00 00 00 01` (24 bytes). Bytes come from
`OSCEncoder.encode(_:)` and decode back through `OSCDecoder` to the same message.

## S2 Package API (PerformanceControl)

- `OSCSendDestination.parse(host: String, port: String) -> Result<OSCSendDestination, OSCSendDestinationError>`; `OSCSendDestination.isSendable(_ host: OSCPeerAddress) -> Bool`.
- `OSCSendMessages.message(for: OSCSendEvent, includeSceneNames: Bool) -> OSCMessage`.
- `OSCSendRateCap(limit: 60, windowNanoseconds: 1e9)`: `mutating func admit(now:) -> Bool`.
- `OSCBeatGate`: `mutating func beat(anchor: UInt64?, period: UInt64?, now: UInt64) -> Int32?`; `mutating func reset()`.
- `protocol OSCSendTransport: AnyObject, Sendable { open(host:port:events:); send(_ bytes: [UInt8]); close() }` with events `OSCSendTransportEvent` (`.ready`, `.failed(OSCListenerFailure)`).
- `final class OSCSender: Sendable`: `init(transport:clock:)`, `configure(destination: OSCSendDestination?)` (nil = inactive: closes), `setOptions(kinds:includeSceneNames:)`, `post(_ event:) -> OSCSendOutcome` (`.sent`, `.inactive`, `.kindOff`, `.rateLimited`), `counters`, `state` (`.off`, `.connecting`, `.ready`, `.failed`), `onStateChange`.
- `NetworkOSCSender` (`OSCTransport/`, `#if canImport(Network)`): the real transport; refuses a non-local host.

## S3 App

- `OSCSendCoordinator` (main actor): five keys; `setEnabled`, `submitDestination(host:port:) -> Bool` (sets `destinationError`), `setKind(_:on:)`, `includeSceneNames`; `conditionsChanged()` (called by `OSCReceiverCoordinator.apply()`), `post(_:)`, `tick(now:)` for beats; `statusText`, `sentCount`, `droppedCount`.
- Settings › OSC: row "Send OSC" (identifier `oscSendLink`, value "Off"/"On") → `OSCSendView` (identifiers `oscSendToggle`, `oscSendHost`, `oscSendPort`, `oscSendApply`, `oscSendHostError`, `oscSendStatus`, `oscSendKind.scene|beat|status`, `oscSendSceneNames`, `oscSendCounts`).
