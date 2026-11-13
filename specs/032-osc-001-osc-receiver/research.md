# Research: OSC-001 OSC Receiver

Decisions are numbered `OSC-001-D1…` (validate_docs.py reserves plain `R-nn` headings).

## OSC-001-D1 Transport API

- **Decision**: `NWListener` with `NWParameters.udp`, one `NWConnection` per peer (the framework's
  model for UDP listeners), `receiveMessage` per datagram, all on one private serial
  `DispatchQueue`.
- **Rationale**: the only networking API the owner ruling allows (FR-068 amendment). BSD sockets,
  CFNetwork and URLSession are forbidden everywhere. `NWListener` and `NWConnection` are `Sendable`
  in the Xcode 27.2 SDK (checked in `Network.swiftinterface`), so a queue-confined class is safe in
  Swift 6.
- **Alternatives**: `NWConnectionGroup` (multicast; not needed); the iOS 26 structured-concurrency
  `NetworkListener` (newer, less established in this codebase, and CI's Xcode 26 must compile the
  same code).

## OSC-001-D2 Local network only

- **Decision**: three layers. `NWParameters.acceptLocalOnly = true`, `prohibitedInterfaceTypes =
  [.cellular]`, and our own check of each peer's address (`OSCPeerAddress.isLocal`: IPv4 loopback,
  10/8, 172.16/12, 192.168/16, 169.254/16; IPv6 `::1`, `fe80::/10`, `fc00::/7`; IPv4-mapped IPv6
  is checked as IPv4). A non-local peer's connection is cancelled before any read.
- **Rationale**: the system flag is the primary control; the explicit check is pure, testable on
  Linux, and documents the rule. Carrier-grade NAT (100.64/10) is not a local network and is refused.
- **Alternatives**: binding to a specific interface address (fragile across Wi-Fi changes).

## OSC-001-D3 Decoder bounds

- **Decision**: maximum datagram 1,472 bytes (1,500-byte Ethernet MTU minus IPv4 and UDP headers);
  address at most 255 bytes, printable ASCII (0x21-0x7E), starting with `/`; at most 16 arguments;
  tags `f` and `i` only; strings must be null-terminated and zero-padded to 4 bytes; no bytes after
  the last argument. A packet starting with `#bundle\0` is `bundleUnsupported`.
- **Rationale**: OSC 1.0 framing. Every read checks remaining length first; arrays are reserved only
  from bounded counts (the type-tag count, itself ≤ 17 bytes), so allocation is proportional to the
  datagram (OSC-001-R10). OSC-002 adds strings, blobs and bundles behind the same enums.
- **Alternatives**: a third-party OSC library (new dependency and license review for ~150 lines).

## OSC-001-D4 Fuzz

- **Decision**: 20,000 packets from a fixed-seed SplitMix64: one third random bytes (0-64 long), one
  third valid messages with one to three bytes mutated, one third valid messages truncated at a
  random length. Assert no crash, and that every accepted packet re-encodes to the same bytes
  (accepted ⇒ well formed).
- **Rationale**: deterministic, fast (< 1 s), and covers the boundary paths. The larger corpus is
  OSC-002's.

## OSC-001-D5 Lifecycle and "disable closes listener"

- **Decision**: `OSCReceiver` owns a generation counter. `start(port:)` cancels any current transport
  and starts a new one tagged with the next generation; `stop()` cancels the transport and moves to
  `stopping`, then to `off` when that transport reports `cancelled`. Events from an older generation
  are ignored, so a late `ready` from a cancelled listener cannot report "Listening". The transport's
  `stop()` cancels the listener and every tracked connection.
- **Proof**: the loopback integration test (OSC-001-S2) sends after stop and sees no change, then
  binds a new listener on the same port, which succeeds only if the port was released.

## OSC-001-D6 Loopback sender for the integration test

- **Decision**: `OSCLoopbackSender` in `OSCTransport/`, compiled only under `DEBUG`, with the host
  fixed to `127.0.0.1` (no host parameter), `internal` and used through `@testable import`.
- **Rationale**: the compliance script scans test folders too, so test files cannot import the
  Network framework. Putting the sender in the allowed folder keeps the rule intact, and `#if DEBUG`
  keeps sending code out of the shipping Release build (checked with `nm` on a release build of the
  package, OSC-001-S5).

## OSC-001-D7 Foreground only and permission

- **Decision**: the app runs the listener only while the scene is active and the user has turned it
  on. iOS shows the Local Network permission prompt the first time the listener starts; a denial
  appears as the listener waiting or failing with a policy error (DNS-SD `-65570`,
  `kDNSServiceErr_PolicyDenied`), shown as "Local network access is off…". How a denial surfaces on
  each iOS version is an assumption to confirm on a device (the `{device}` task).
- **Rationale**: no background networking (no background mode is added; screen-capture's background
  mode is for capture only).

## OSC-001-D8 Test value

- **Decision**: parameter `osc.receiver.testValue` (continuous 0…1, default 0, step 0, unit none,
  policy `allowsExternalControl: true`, not modulatable) in a registry the receiver builds; OSC address
  `/projectm/test`. It is not in the visual catalog, so it cannot change rendering.
