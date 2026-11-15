# ADR-0100: Local Peer Discovery Uses Opt-In Bonjour on the Local Link Only

- **Status**: Accepted 2026-11-15 (decided by Claude under the owner's best-judgement rule, owner rule 4)
- **Feature**: OSC-011 (`specs/289-osc-011-local-peer-discovery`)
- **Constitution**: I (public APIs only), VI (modular boundaries); Platform, Security & Privacy
- **Amends**: the FILE-012 network symbol scan (until now `NWBrowser` failed everywhere and `NWListener.Service`
  passed as a plain listener API), `check_compliance.py` (new discovery rules), OSC-001's "no Bonjour" note and
  `NSLocalNetworkUsageDescription`

## Context

The roadmap row OSC-011 asks the app to "discover nearby compatible devices using permitted Bonjour service", with
the acceptance "Discovery disabled by default and no central relay is used". FR-068 as amended by ADR-0008 allows
the Network framework only in `PerformanceControl/OSCTransport/`, for local OSC that is off by default. OSC-001's
listener announced nothing, and `NSBonjourServices` was absent.

## Decision

1. **One mechanism, one type.** Discovery is Bonjour (DNS-SD over multicast DNS) on the local link for exactly one
   service type, `_projectm-osc._udp` in `local.`. There is no server, relay, cloud lookup, unicast DNS, hard-coded
   host, Bluetooth or peer-to-peer Wi-Fi (`includePeerToPeer = false`, cellular prohibited). `NSBonjourServices`
   declares only that type.
2. **Two opt-in switches.** "Find nearby devices" (browse) and "Let nearby devices find this one" (announce) are
   separate, both off by default, and each runs only while the OSC receiver switch (OSC-007) is on and the app is in
   the foreground. Announcing reveals the device to its network, so it needs its own explicit choice.
3. **Reviewed code.** `NetworkOSCPeerBrowser` (`OSCTransport/NetworkOSCPeerBrowser.swift`) is the only browser; it
   resolves each found service with a short IPv4 UDP flow that sends nothing and keeps only local addresses.
   Announcing is `NWListener.service` on OSC-001's own listener (`NetworkDatagramTransport`), so it carries the
   real port and ends with the listener.
4. **Generic name.** The announced name is "projectM" and 4 random hexadecimal digits chosen per launch, in memory;
   never the device or user name.
5. **No automatic trust.** Found devices are memory only. Only the user's "Allow" (OSC-008) or "Use as send
   destination" (OSC-005) tap changes anything; neither turns another switch on.
6. **Scan rules.** `check_network_symbols.py` allows `NWBrowser*`, `NWListener.Service*`, `NWListener.service`,
   `NWConnection(to:using:)`, `NWConnection.currentPath`, `NWPath.remoteEndpoint` and `NWProtocolIP*` only in an image
   that defines both the OSC transport and `NetworkOSCPeerBrowser`. `check_compliance.py` keeps `NWBrowser` in the
   browser file and `NWListener.Service` in the listener file, requires the browser to browse exactly
   `.bonjour(type: OSCDiscovery.serviceType, domain: OSCDiscovery.domain)` with no host, address, URL or other
   endpoint, allows no other Bonjour type string in Swift sources, and requires `NSBonjourServices` to be exactly
   `[_projectm-osc._udp]`.
7. **Stored data.** Only the two switches (`settings.osc.discovery.browse`, `settings.osc.discovery.advertise`), on
   this device: excluded from the FILE-005 backup, removed by the FILE-011 Settings erase. The privacy policy and
   the Local Network usage string describe discovery.

## Consequences

- Two devices running projectM on one Wi-Fi can find each other and pick a send destination without typing an
  address; the end-to-end LAN check is OSC-011-T19 `{device}`.
- A host loopback test (announce through the real listener, find it with the real browser) passes on the macOS host
  and skips rather than fails where multicast DNS does not answer.
- Any other discovery mechanism, service type or browsing code elsewhere fails the scans and needs a new ADR.

## Alternatives rejected

- `NSNetService` / `DNSServiceBrowse`: deprecated or C-level, rejected by the symbol scan.
- MultipeerConnectivity: peer-to-peer Wi-Fi and Bluetooth, a forbidden library.
- A rendezvous server: a relay, against the acceptance and FR-068.
- One switch for both browse and announce: announcing is a separate disclosure.
