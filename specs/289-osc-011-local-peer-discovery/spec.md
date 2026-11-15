# Feature Specification: OSC-011 Local Peer Discovery

**Feature Branch**: `feature/osc-011` (spec directory `289-osc-011-local-peer-discovery`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement roadmap row OSC-011 (Local peer discovery) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Discover nearby compatible devices using permitted Bonjour service."
Acceptance, verbatim: "Discovery disabled by default and no central relay is used." P3, effort L,
depends on OSC-007 (integrated)."

Identifiers carry the roadmap ID: requirements `OSC-011-R1…`, success criteria `OSC-011-S1…`, research
decisions `OSC-011-D1…`, tasks `OSC-011-T01…`. FR-068 as amended on 2026-11-12 (ADR-0008, networking for
OSC only in the OSC transport folder), ADR-0088 (the reviewed OSC-005 sender) and every OSC-001, OSC-005,
OSC-007, OSC-008 and OSC-009 requirement stay in force. This row is the first time the app browses for or
announces a service on the local network; ADR-0100 records that policy change.

## Baseline: what exists today (audit of 2026-11-15, commit `8e746cbc`)

| Area | Today | Gap |
|---|---|---|
| Receiver (OSC-001) | `NetworkDatagramTransport`: one UDP `NWListener` in `PerformanceControl/OSCTransport/`, listens only, cellular prohibited, every peer checked with `OSCPeerAddress.isLocal`; "no Bonjour (OSC-011 adds discovery)" | **gap**: no service is announced |
| Network switch (OSC-007) | `settings.osc.enabled` ("OSC receiver", off by default) plus the badge's Stop; the listener runs only while it is on and the app is in the foreground | none: discovery follows it |
| Allow list (OSC-008) | `OSCPeersCoordinator.allow(_:)`, up to 16 approved local hosts, device only | none: reused for "Allow" |
| Send (OSC-005) | `OSCSendCoordinator.submitDestination(host:port:)` validates a literal local address and port | none: reused for "Use as send destination" |
| Local-address rule | `OSCPeerAddress.isLocal`, `OSCSendDestination.isSendable` | none: reused for resolved peers |
| Compliance | `check_compliance.py` allows the Network framework (including `NWBrowser`) only in `OSCTransport/` | none in source; **gap**: no rule pins the service type or forbids other endpoints in discovery code |
| Symbol scan | `check_network_symbols.py` allows listener-side APIs (any `NWListener.*`, so also `NWListener.Service`) and the outbound pair next to the reviewed sender | **gap**: `NWBrowser` is rejected; service advertising is not tied to a reviewed file |
| Info.plist | `NSLocalNetworkUsageDescription`; no `NSBonjourServices` | **gap**: iOS requires the service type to be declared |
| Permission catalog | `PermissionCatalog` `.localNetwork` mirrors the usage string; privacy policy section "OSC control on your local network" | wording must cover discovery |

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which discovery mechanism? → A: Bonjour (DNS-SD over multicast DNS) on the local link only, for one app-specific service type `_projectm-osc._udp` in the `local.` domain. No other mechanism: no server, relay, cloud lookup, unicast DNS, hard-coded host, Bluetooth or peer-to-peer Wi-Fi (OSC-011-R1, R2).
- Q: Where is it configured? → A: Settings › OSC › "Nearby Devices" (one new row in the OSC section): two switches and the list of discovered devices (OSC-011-R3).
- Q: Is announcing this device a separate choice from finding others? → A: Yes. "Find nearby devices" (browse) and "Let nearby devices find this one" (announce) are separate switches, both off by default and on a fresh install. Announcing reveals the device to everyone on the network, so it needs its own explicit choice (OSC-011-R4).
- Q: What do both switches need? → A: The OSC receiver switch (OSC-007's network access switch) on and the app active in the foreground. While OSC is off the switches are shown disabled with a note; their stored values stay (OSC-011-R5).
- Q: When do browsing and announcing stop? → A: At once when their switch is turned off, when the OSC receiver switch is turned off (Settings or the badge's Stop), or when the app leaves the foreground; the found list is cleared (OSC-011-R6).
- Q: What name is announced? → A: "projectM" plus a space and 4 random hexadecimal digits, chosen fresh at each launch and kept in memory only; never the device name, the user's name or any identifier. The announced port is the receiver's listening port (OSC-011-R7).
- Q: What is shown for a found device? → A: Its announced name (control characters removed, at most 63 characters) and its resolved local address and port. A device whose address is not local (`OSCPeerAddress.isLocal`) is not shown. At most 16 devices; this device's own announcement is left out (OSC-011-R8).
- Q: Is a found device trusted automatically? → A: Never. Each row offers "Allow" (adds the address to OSC-008's approved devices) and "Use as send destination" (sets OSC-005's destination to the address and port). Both are explicit taps; nothing else changes, and Send OSC is not turned on (OSC-011-R9).
- Q: Is anything stored? → A: Only the two switches, on this device: excluded from the FILE-005 backup, removed by the FILE-011 Settings erase and by the UI-test reset. Found devices and the announced name are memory only (OSC-011-R10).
- Q: Permission? → A: The existing Local Network permission; its usage string and the privacy policy mention discovery and announcing. `NSBonjourServices` declares only `_projectm-osc._udp` (OSC-011-R11).

### Session 2026-11-15 (speckit-clarify)

- Q: When is this device announced: as soon as the switch is on, or only while the receiver is actually listening? → A: Only while the receiver is listening: the announcement is part of the listening port, so it carries the real port and disappears with the listener (OSC-011-R5, R7).
- Q: Are newly found devices announced to VoiceOver? → A: No. Discovery is not an event; the list and the status line ("Looking for nearby devices…", "2 devices found") are ordinary accessible labels, so nothing is spoken per change.
- Q: Which address is shown when a device has both IPv4 and IPv6? → A: IPv4 is preferred. If only an address that OSC-005 cannot send to is found (IPv6 link-local), the device is listed with "Allow" only and "Use as send destination" is disabled (OSC-011-R8, R9).
- Q: Does discovery follow PERF-010's recovery, which turns OSC off after an abnormal exit? → A: Yes, automatically: OSC off stops both activities (R5); the two switches keep their stored values.
- Q: Is "Allow" offered while "Only approved devices" is off? → A: Yes. It adds the device to Approved Devices for when the user turns the allow list on; it never turns the allow list on.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find another projectM or OSC controller nearby (Priority: P3)

A performer has two iPads running projectM on the same Wi-Fi. On iPad B they turn on the OSC receiver and
"Let nearby devices find this one". On iPad A they turn on the OSC receiver and "Find nearby devices"; within a
few seconds "projectM 3F9A — 192.168.1.23:9000" appears. They tap "Use as send destination", then turn on Send
OSC: iPad B now receives A's scene messages.

**Why this priority**: it is the roadmap row (P3).

**Independent Test**: with a fake browser that reports two services, the list shows both names and addresses;
"Allow" and "Use as send destination" change only the allow list and the send destination.

**Acceptance Scenarios**:

1. **Given** OSC on and "Find nearby devices" on, **When** a browser reports a local service, **Then** its name and address appear.
2. **Given** a found device, **When** the user taps "Allow", **Then** the address is in Approved Devices; **When** they tap "Use as send destination", **Then** Send OSC's destination is that address and port and Send OSC's switch is unchanged.
3. **Given** a found device whose address is not local, **Then** it is not listed.

### User Story 2 - Discovery is off by default (Priority: P3)

**Acceptance Scenarios**:

1. **Given** a fresh install with OSC on, **Then** both switches are off, no browser exists and no service is announced.
2. **Given** both switches off, **When** OSC is turned on and off and the app moves between foreground and background, **Then** no browser is ever created and no service is announced.

### User Story 3 - Discovery stops when it should (Priority: P3)

**Acceptance Scenarios**:

1. **Given** browsing, **When** "Find nearby devices" is turned off, the OSC receiver is turned off, or the app leaves the foreground, **Then** the browser is cancelled and the list is empty.
2. **Given** announcing, **When** "Let nearby devices find this one" is turned off, the OSC receiver is turned off, or the app leaves the foreground, **Then** the announcement is withdrawn.

### User Story 4 - No relay, nothing beyond the local link (Priority: P3)

**Acceptance Scenarios**:

1. **Given** the discovery code, **Then** it names only the `_projectm-osc._udp` type in the `local.` domain, uses no URL loading, no host names and no other endpoints.
2. **Given** the built app, **Then** `NSBonjourServices` lists only `_projectm-osc._udp`, and the network symbol scan accepts browsing and announcing only in the reviewed discovery and receiver code.

### Edge Cases

- A found name with control characters or over 63 characters: cleaned and cut.
- More than 16 devices: the first 16 by name are kept.
- A device that cannot be resolved: listed by name with "Resolving…", without actions.
- The Local Network permission denied: the status line says local network access is off; no retry.
- A device found only at an IPv6 link-local address: listed with "Allow" only ("Use as send destination" disabled).
- The approved list is full (16): "Allow" is disabled.
- Another device announces the same name: both are listed (Bonjour renames one).

## Requirements *(mandatory)*

- **OSC-011-R1**: Discovery MUST use only Bonjour on the local link for the service type `_projectm-osc._udp` in the `local.` domain.
- **OSC-011-R2**: Discovery MUST NOT use any server, relay, cloud service, unicast DNS, hard-coded host, URL loading, Bluetooth or peer-to-peer Wi-Fi.
- **OSC-011-R3**: Settings › OSC MUST offer a Nearby Devices screen with "Find nearby devices", "Let nearby devices find this one", a status line and the found devices.
- **OSC-011-R4**: Both switches MUST be off by default and on a fresh install; with a switch off, its activity (browsing or announcing) MUST NOT exist.
- **OSC-011-R5**: Browsing and announcing MUST run only while their switch is on, the OSC receiver switch (OSC-007) is on and the app is active in the foreground.
- **OSC-011-R6**: When any condition of R5 stops holding, the browser MUST be cancelled (or the announcement withdrawn) at once and the found list cleared.
- **OSC-011-R7**: The announced name MUST be "projectM " plus 4 random hexadecimal digits, chosen per launch and kept in memory only; the announced port MUST be the receiver's port.
- **OSC-011-R8**: Found devices MUST be shown by cleaned name (no control characters, at most 63 characters) and resolved address and port; non-local addresses MUST be dropped; at most 16; this device's own announcement left out.
- **OSC-011-R9**: A found device MUST NOT be added to the allow list or used as send destination except by the user's explicit "Allow" or "Use as send destination" tap.
- **OSC-011-R10**: The two switches MUST be stored on this device only (excluded from backup, removed by the Settings erase and the UI-test reset); found devices and the name MUST stay in memory.
- **OSC-011-R11**: `NSBonjourServices` MUST list exactly `_projectm-osc._udp`; the Local Network usage string, the permission catalog and the privacy policy MUST mention discovery.
- **OSC-011-R12**: The compliance and network-symbol scans MUST accept browsing and announcing only in the reviewed OSC transport code and reject other endpoints in it.

### Key Entities

- **Discovery switches**: Find nearby devices, Let nearby devices find this one (device only).
- **Found device**: cleaned name, optional local address and port; memory only.
- **Announced name**: "projectM XXXX", per launch, memory only.

## Success Criteria *(mandatory)*

- **OSC-011-S1**: On a fresh install, 0 browsers and 0 announcements exist across OSC on/off and foreground/background changes.
- **OSC-011-S2**: Turning discovery off, OSC off or going to the background ends browsing and announcing in 100% of test runs, with the list empty.
- **OSC-011-S3**: 0 found devices reach the allow list or the send destination without the user's tap.
- **OSC-011-S4**: The discovery code and the built app reference only the one local service type and no other network endpoint (scans pass, 0 findings).
- **OSC-011-S5**: A user goes from OSC on to a chosen send destination in at most 3 taps on the Nearby Devices screen.

## Assumptions

- Two real devices on the same Wi-Fi are needed to prove discovery end to end; that is a `{device}` task.
- Discovery does not exchange any data with found devices; OSC-012 (peer cue sync) builds on it later.
