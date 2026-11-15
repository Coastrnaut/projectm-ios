# Tasks: OSC-005 OSC Send

**Input**: `specs/277-osc-005-osc-send/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (loopback fixture, disable stops traffic) and the brief. No wall-clock
assertions except the short "nothing arrives" window of real UDP; unit tests about 1-2 s, package suite < 1 min,
UI test < 30 s (owner rule 7). Tasks are ticked only when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] OSC-005-T01 Audit OSC-001/002/003/004/007/008/009, the loopback tests, SHOW-001 scene application, SHOW-011 TempoSnapshot and MIDI-010; record the baseline table in `specs/277-osc-005-osc-send/spec.md`.

## Phase 2: Foundational (package)

- [ ] OSC-005-T02 `OSCSendDestination` ("literal, local, not link-local IPv6/unspecified/multicast; port 1024-65535"), `OSCSendDestinationError`, `OSCSendKind`, `OSCSendEvent`, `OSCSendStatus`, `OSCSendMessages` (names ≤ 64 UTF-8 bytes), `OSCSendRateCap` (60 per 1 s), `OSCBeatGate` (once per beat, ≥ 250 ms apart) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSend.swift` (R3, R6-R9, R13).
- [ ] OSC-005-T03 `OSCSendTransport`, `OSCSendTransportEvent`, `OSCSender` (configure, options, post, counters, state) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSender.swift` (R4, R5, R9).
- [ ] OSC-005-T04 `NetworkOSCSender` (UDP `NWConnection` to a literal local host, no cellular, generation-dropped queued sends, ≤ 16 in flight, cancel on close) in `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkOSCSender.swift` (R3, R5); ADR-0088 and the `NetworkOSCSender` marker rule in `scripts/check_network_symbols.py` with tests in `scripts/test_scripts.py`.

## Phase 3: User Story 1 - Tell a lighting desk about scene changes and beats (P2)

**Independent test**: a real UDP listener on 127.0.0.1 receives exactly the expected bytes for a scene change and a beat.

- [ ] OSC-005-T05 [US1] Pure tests in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSendTests.swift`: message bytes for each kind match contract S1; encoder round trip through `OSCDecoder` for the three kinds plus a seeded pseudo-random property test (strings with multibyte text, ints, floats); name truncation at a character boundary; beat gate once per beat and ≥ 250 ms apart; rate cap 60 per window; sender with a fake transport (kind off, inactive, counters) (R6-R9, R13; S4).
- [ ] OSC-005-T06 [US1] Loopback acceptance in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCSendLoopbackTests.swift` (macOS host): `NetworkDatagramTransport` on port 0 receives byte-exact `/projectm/scene ,s "Intro"` and `/projectm/beat ,i 1` from `OSCSender` + `NetworkOSCSender` (S1).
- [ ] OSC-005-T07 [US1] `OSCSendCoordinator` in `Apps/projectM-iOS/Coordinators/OSCSendCoordinator.swift` (five keys, conditions, beat poll, status text, counts) and the hooks: `OSCReceiverCoordinator.apply()` → `sender?.conditionsChanged()`, `AppCoordinator.connectAfterInit` wiring, `start(_:)`/`stop()` status events, `applyShowScene` scene event (R4, R6, R10).
- [ ] OSC-005-T08 [US1] `Apps/projectM-iOS/Views/OSCSendView.swift` and the "Send OSC" row in `Apps/projectM-iOS/Views/SettingsView.swift` `oscSection` (R1, R10).
- [ ] OSC-005-T09 [US1] App test `Apps/projectM-iOS/Tests/OSCSendCoordinatorTests.swift`: with a loopback `NetworkDatagramTransport` listener, a scene and a beat (fake grid and clock) arrive byte-exact; defaults off (R2).

## Phase 4: User Story 2 - Disable stops traffic (P2)

- [ ] OSC-005-T10 [US2] Package loopback test: after `configure(destination: nil)` posts produce nothing at the listener over a 300 ms window; queued sends are dropped (S2). App test: Send OSC off, receiver switch off, background each stop traffic at the loopback listener (R5).

## Phase 5: User Story 3 - Only the local network (P2)

- [ ] OSC-005-T11 [US3] Tests in `OSCSendTests.swift`: 8.8.8.8, 100.64.0.1, 224.0.0.1, 255.255.255.255, 0.0.0.0, 2001:db8::1, fe80::1, `mixer.local`, port 80 and 70000 refused; 127.0.0.1, 10.0.0.2, 172.16.0.1, 192.168.1.40, 169.254.1.1, ::1, fd00::1 accepted (S3). App test: allow list on without the destination → nothing sent, status says so.
- [ ] OSC-005-T12 [US3] UI test `Apps/projectM-iOS/UITests/OSCSendUITests.swift` (< 30 s): open Send OSC, a public address shows the error, a LAN address is accepted, toggles exist; no network needed (S5).

## Phase 6: Polish

- [ ] OSC-005-T13 Keys in `scripts/run_device_tests.py` `ALLOWED_KEYS`, `LibrarySettingsPolicy.excludedKeys`, `LibraryErasePolicy` (Settings erase), `-uitestResetNotice`, `LibraryBackupAppTests` app keys and excluded set (R12); LibraryBackup package tests, `LibraryBackupAppTests`, `SettingsTests` pass.
- [ ] OSC-005-T14 Local Network usage string in `project.yml` and `PermissionCatalog.swift`, privacy policy section (R11); `check_permission_catalog.py`.
- [ ] OSC-005-T15 Repo checks, `check_network_symbols` and `check_privacy_manifest.py` on the Debug app, type-check budget build, PosterBoard counts.
- [ ] OSC-005-T16 {device} LAN receiver on D1 (quickstart step 4).

## Dependencies

T01 → T02 → T03 → T04 → T05, T06, T10, T11; T07 after T03; T08 after T07; T09 after T04 and T07; T12 after T08; T13-T15 last.

## Parallel examples

T05 with T07 (different files); T13 with T14.

## Implementation strategy

Package first (pure, Linux-safe), then the transport and loopback proof (MVP: US1 package acceptance), then the app coordinator, screen and tests.
