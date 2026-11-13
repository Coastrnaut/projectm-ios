# Feature Specification: FILE-012 No-Telemetry Verification

**Feature Branch**: `feature/file-012` (spec directory `076-file-012-no-telemetry-verification`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement FILE-012 (No-telemetry verification) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Test that normal app use makes no
application-initiated network requests." Acceptance, verbatim: "Local proxy test sees no connections
except explicit StoreKit or user-enabled LAN." P0, effort M, depends on SCN-001."

Identifiers in this feature carry the roadmap ID: requirements `FILE-012-R1…`, success criteria
`FILE-012-S1…`, tasks `FILE-012-T01…`. Other features are cited by their own IDs: FR-068 (feature
001: no networking APIs; amended 2026-11-12 for OSC, ADR-0008), feature 002 FR-122 (StoreKit purchase
traffic), OSC-001 (UDP receiver, off by default), OSC-007 (listener badge and Stop), FR-066 (privacy
manifest scan, `check_privacy_manifest.py`).

## Baseline: the app's network surface (audit of 2026-11-13, commit `607c2c2`)

| Surface | Where | Status |
|---|---|---|
| URL loading, sockets, WebKit, CFNetwork | anywhere | Forbidden in source by `check_compliance.py` (FR-068) |
| Network framework | `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/` only | OSC UDP listener, off by default (OSC-001, ADR-0008) |
| Outbound Network connection | `OSCLoopbackSender` | DEBUG only, loopback host only, for a package test (OSC-001-R19) |
| StoreKit 2 | `LibraryStore` (feature 002) | Purchase and restore; the requests are made by iOS (StoreKit daemon), not by the app's process |
| ANGLE (`libEGL`, `libGLESv2`), projectM (`projectM-4`) | embedded frameworks | Vendored C/C++; no networking code expected, never checked before this feature |
| Third-party SDKs, analytics, crash reporters | — | None |

Until now the only evidence was the source rule. Nothing checked the built binaries (which also carry
vendored C/C++ that the source rule does not scan) or observed the running app.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The shipped binaries cannot make network requests on their own (Priority: P1)

The owner (and a reviewer reading the privacy answers) wants proof that the built app, including every
embedded framework, contains no code that can open a network connection except the two allowed
surfaces: StoreKit (requests are made by iOS) and the OSC listener the user turns on.

**Why this priority**: Static proof covers every code path, including rarely used ones that no UI
session reaches.

**Independent Test**: Run the binary scan on a Debug simulator build, a Release simulator build and a
Release device build; inject a fixture binary that calls a socket function and confirm the scan fails.

**Acceptance Scenarios**:

1. **Given** a built app, **When** the scan runs, **Then** it inspects the executable, the Debug
   dylib (when present) and every embedded framework, and reports each image's network-capable
   imports and linked frameworks.
2. **Given** an image that links a forbidden framework or imports a socket, resolver, URL-loading,
   web-view or browser symbol, **When** the scan runs, **Then** it fails and names the image and symbol.
3. **Given** Network framework imports, **When** the scan runs, **Then** they pass only in the image
   that holds the OSC transport, and in a Release build only listener-side APIs pass (no API that
   opens an outbound connection or sends).
4. **Given** StoreKit linkage, **When** the scan runs, **Then** it is reported as allowed.

### User Story 2 - Normal use opens no network connection (Priority: P1)

During a scripted session of normal use with OSC off and the store stubbed, an observer on the Mac
sees no network socket and no network-connection activity in the app's process.

**Why this priority**: The roadmap's acceptance is about observed traffic; the binary scan cannot see
what system frameworks do on the app's behalf at run time.

**Independent Test**: Run the session's UI tests under the observer; the observer's report shows zero
sockets and zero connection events, and the same observer, in the OSC run, does see the listener and a
probe peer (so a zero is not blindness).

**Acceptance Scenarios**:

1. **Given** OSC off and the store stubbed, **When** the session launches the app, passes the notice
   and the chooser, starts In-App Playback, switches visuals (projectM, spectra, Photo, Video, Text
   with seeded content), opens Settings and Storage, saves a frame, records a short video, steps show
   cues and clears caches, **Then** the observer reports no internet or local-network socket and no
   connection, listener or resolver activity in the app's process.
2. **Given** the observer is running, **When** the app is relaunched between tests, **Then** each new
   app process is observed too.

### User Story 3 - User-enabled OSC opens only its local listener (Priority: P1)

When the user turns the OSC receiver on in Settings, the only network endpoint in the app's process is
the UDP listener on the chosen port; the app opens no outbound connection.

**Independent Test**: Under the observer, a UI test enables OSC in Settings, uses the app, and turns it
off; the observer sends one probe datagram from the Mac's loopback address and reports the listener,
the probe's peer, and nothing else.

**Acceptance Scenarios**:

1. **Given** OSC turned on by the user, **When** the session runs, **Then** the observer sees a UDP
   listener bound to the chosen port and no other socket except the peer of its own probe.
2. **Given** OSC turned off again, **When** the session continues, **Then** the listener is gone.

### User Story 4 - An honest record of what is and is not proven (Priority: P2)

The owner can read one report that says what each layer proves, what it cannot prove (system
frameworks contacting Apple, the device's own network stack), and what is left for a device run.

**Acceptance Scenarios**:

1. **Given** the report, **When** the owner reads it, **Then** each claim cites a command, its result
   and its date, and simulator results are never presented as device evidence.

### Edge Cases

- A socket opened and closed between two observer samples: the unified-log layer still records the
  connection's creation; raw BSD sockets that bypass the Network framework and are shorter than one
  sample interval are a documented blind spot of the socket layer (the binary scan covers them).
- System daemons acting for the app (StoreKit, crash reporting, push, App Store) run in other
  processes; they are outside "application-initiated" and outside the observer's process filter.
- The XCTest runner process has its own sockets for test control; it is not the app and is excluded.
- An observer that cannot run (no `lsof`, no simulator log access) fails the run rather than passing.
- Fat (multi-architecture) frameworks: every architecture is scanned.
- No Debug dylib (Release): skipped without error.

## Requirements *(mandatory)*

### Functional Requirements

- **FILE-012-R1**: A binary scan MUST inspect every Mach-O image in a built app (executable, Debug
  dylib, embedded frameworks and any app extensions), all architectures, and report linked frameworks
  and network-capable imported symbols per image.
- **FILE-012-R2**: The scan MUST fail on: linking CFNetwork, WebKit, JavaScriptCore, SafariServices,
  AuthenticationServices, MultipeerConnectivity, NetworkExtension or SystemConfiguration; importing BSD
  socket or resolver functions; URL-loading, socket-stream, reachability, Bonjour or web-view classes
  and functions; or any symbol from the Network framework outside the allowed image.
- **FILE-012-R3**: The scan MUST allow exactly: StoreKit linkage (purchase traffic is made by iOS);
  Network framework imports in the image that defines the OSC transport (`NetworkDatagramTransport`);
  and, only in Debug builds, the outbound loopback-sender APIs in that same image. In Release builds an
  outbound Network API (connection to a host, send, browser, connection group, path monitor) MUST fail.
- **FILE-012-R4**: The scan's rules MUST be tested on any OS from recorded tool output, and on macOS
  against real binaries built for the test (a positive control that calls a socket function), with a
  clear skip elsewhere.
- **FILE-012-R5**: CI MUST run the scan on the app it already builds when that costs seconds.
- **FILE-012-R6**: A runtime observer MUST wrap a test command, find every app process launched in a
  given simulator, sample its internet sockets, and record the simulator's network and URL-loading log
  events for that process, then classify them against an expectation (`none`, or the OSC listener on a
  port) and exit non-zero on anything unexpected or when it could not observe.
- **FILE-012-R7**: The observer MUST prove it can see the app's sockets: in the OSC run it sends one
  probe datagram from the Mac's loopback address to the listener and requires seeing the resulting peer
  socket and connection events; the report records this.
- **FILE-012-R8**: UI tests MUST script normal use (US2 scenario 1) with OSC off and the store stubbed,
  and the OSC session (US3) with OSC turned on in Settings, without changing other tests, each test
  under 30 s.
- **FILE-012-R9**: A report `docs/test-reports/no-telemetry.md` MUST state what each layer proves and
  does not prove, with commands, results and dates; `docs/release/app-privacy.md` MUST cite it.
- **FILE-012-R10**: A `{device}` task MUST describe the D1 check (App Privacy Report or a Mac proxy
  set up by the owner) and stay open until run.
- **FILE-012-R11**: No app behaviour changes: this feature adds tests, scripts and documents only.

### Key Entities

- **Scan finding**: image, architecture, kind (framework or symbol), name, rule, verdict.
- **Observation sample**: time, process ID, socket lines; **log event**: time, process ID, category,
  message.
- **Observation report**: processes seen, sockets, events, probe result, verdict.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FILE-012-S1**: The scan reports zero violations on a Debug simulator build, a Release simulator
  build and a Release device build of `projectM-iOS`, and lists the allowed StoreKit and Network
  findings.
- **FILE-012-S2**: The scan fails on a fixture binary that calls `socket`/`connect` and on recorded
  output that imports each forbidden class; tests run on any OS.
- **FILE-012-S3**: With OSC off, the observed session (every app process launched during it) shows
  0 internet sockets and 0 connection, listener or resolver events.
- **FILE-012-S4**: With OSC on, the observer sees exactly one listener on the chosen port plus its own
  probe's peer, and 0 outbound connections.
- **FILE-012-S5**: Each new UI test runs in under 30 s; script tests in under 10 s each.

## Assumptions

- On the iOS Simulator the app runs as a Mac process sharing the Mac's network stack, so `lsof` on the
  Mac sees its sockets (verified 2026-11-13: an OSC listener appeared as `UDP *:47129`, and a datagram
  from the Mac produced a connected peer socket), and `simctl spawn log stream` delivers its
  Network-framework log events.
- The device's network stack differs (and system daemons run there too); simulator results are not
  device evidence, so the device check is a separate `{device}` task.
- A local proxy (the roadmap's wording) only sees HTTP(S) that honours proxy settings; socket and log
  observation of the process is stricter on the simulator, so it stands in for the proxy here, and the
  proxy or App Privacy Report run is the device task.

## Scope

In scope: binary scan script and tests, CI step, runtime observer script and tests, UI session tests,
report, privacy document update. Out of scope: a Network Extension or packet capture (needs
entitlements or root), blocking traffic at run time, changing app behaviour.
