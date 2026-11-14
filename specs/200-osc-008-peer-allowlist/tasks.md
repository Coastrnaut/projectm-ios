# Tasks: OSC-008 OSC Peer Allowlist

**Input**: `specs/200-osc-008-peer-allowlist/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (unit fuzz + local network integration; device LAN last). No
wall-clock assertions; unit tests about 1-2 s, package suite < 1 min, UI test < 30 s (owner rule 7). Tasks are
ticked only when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [ ] OSC-008-T01 Audit OSC-001 transport/receiver, OSC-003 routes and the OSC settings section; record the baseline table in `specs/200-osc-008-peer-allowlist/spec.md`.

## Phase 2: Foundational (package)

- [ ] OSC-008-T02 `OSCPeerAddress.normalized`, display `text`, `storageText` and `init?(text:)` (IPv4 dotted; IPv6 8 lowercase hex groups, `::` accepted) plus `OSCPeerAllowlist` ("≤ 16" approved, "≤ 4" recently blocked, off by default, non-local refused) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCPeerAllowlist.swift`.
- [ ] OSC-008-T03 `OSCTransportEvent.datagram` gains `peer: OSCPeerAddress? = nil` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDatagramTransport.swift`; `OSCReceiver` owns `peerAllowlist` and drops unapproved datagrams before `OSCDispatcher.handle` in `OSC/OSCReceiver.swift`; `droppedUnapproved` counter and `noteDroppedUnapproved()` in `OSC/OSCDispatcher.swift`.
- [ ] OSC-008-T04 `NetworkDatagramTransport` passes the address it already computed for the local check with each datagram (no new API) in `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkDatagramTransport.swift`.

## Phase 3: User Story 1 - Only my controller can change the show (P1)

**Independent test**: fake transport, allowlist on; unapproved routed message changes nothing, approved applies.

- [ ] OSC-008-T05 [P] [US1] Rule and text tests (normalization, mapped IPv4, round trip, rejects, bounds) in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCPeerAllowlistTests.swift`.
- [ ] OSC-008-T06 [US1] Acceptance test (S1): unapproved host's glow route and test-value messages leave store values and live values unchanged and add to `droppedUnapproved` only; approved host (any port, mapped form) applies; allowlist off applies from anyone; unknown host dropped while on — in `OSCPeerAllowlistTests.swift`.
- [ ] OSC-008-T07 [US1] Seeded fuzz (S1): 500 datagrams, seeded generator, random malformed/valid bytes from random local, foreign and unknown hosts; only approved valid messages may change the store; unapproved ones never reach the decoder (`rejected` unchanged) — in `OSCPeerAllowlistTests.swift`.
- [ ] OSC-008-T08 [US1] Loopback integration: real UDP to 127.0.0.1 with the allowlist on and nothing approved changes nothing and lists 127.0.0.1 as blocked; after approval it applies — in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift`.
- [ ] OSC-008-T09 [US1] `OSCPeersCoordinator` (load/validate/store `settings.osc.peerAllowlist.enabled` and `settings.osc.approvedPeers`, push to the receiver, refresh from counters, clear blocked on OSC off) in `Apps/projectM-iOS/Coordinators/OSCPeersCoordinator.swift`; wiring in `OSCReceiverCoordinator.swift` and `AppCoordinator.swift`.

## Phase 4: User Story 2 - Approve the device that just tried (P2)

- [ ] OSC-008-T10 [US2] App unit tests: allow from recently blocked, full list refused, remove, invalid stored entries dropped, keys persisted, blocked cleared when OSC is off — `Apps/projectM-iOS/Tests/OSCPeersCoordinatorTests.swift`.
- [ ] OSC-008-T11 [US2] `OSCPeersView` and the "Approved Devices" row in `oscSection` (`Apps/projectM-iOS/Views/OSCPeersView.swift`, `Views/SettingsView.swift`).
- [ ] OSC-008-T12 [US2] UI test `Apps/projectM-iOS/UITests/OSCPeersUITests.swift` (< 30 s): open Approved Devices, switch on, empty-list note shown, row value updates.
- [ ] OSC-008-T13 {device} LAN check on D1 with a second device on Wi-Fi (quickstart step 5).

## Phase 5: Polish

- [ ] OSC-008-T14 [P] Keys: `ALLOWED_KEYS` in `scripts/run_device_tests.py`, `LibrarySettingsPolicy.excludedKeys` in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`, the `-uitestResetNotice` reset in `AppCoordinator.swift`.
- [ ] OSC-008-T15 [P] Privacy policy section and ADR-0058 (`docs/privacy-policy.md`, `docs/adr/0058-osc-peer-allowlist.md`).
- [ ] OSC-008-T16 Repo checks, `check_network_symbols` and `check_privacy_manifest.py` on the Debug app, type-check budget build.

## Dependencies

T01 → T02 → T03 → T04; T05-T08 after T03/T04; T09 after T03; T10-T12 after T09; T14-T16 last. US2 depends on US1's coordinator.

## Parallel examples

T05 with T14 and T15 (different files).

## Implementation strategy

MVP is US1 (package filter + acceptance); US2 adds the Settings screen.
