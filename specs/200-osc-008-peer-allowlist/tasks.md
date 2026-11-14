# Tasks: OSC-008 OSC Peer Allowlist

**Input**: `specs/200-osc-008-peer-allowlist/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (unit fuzz + local network integration; device LAN last). No
wall-clock assertions; unit tests about 1-2 s, package suite < 1 min, UI test < 30 s (owner rule 7). Tasks are
ticked only when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [X] OSC-008-T01 Audit OSC-001 transport/receiver, OSC-003 routes and the OSC settings section; record the baseline table in `specs/200-osc-008-peer-allowlist/spec.md`. — Verified 2026-11-14: spec.md "Baseline" (transport discarded the host after the local check; `.datagram` carried only `OSCSourceID`).

## Phase 2: Foundational (package)

- [X] OSC-008-T02 `OSCPeerAddress.normalized`, display `text`, `storageText` and `init?(text:)` (IPv4 dotted; IPv6 8 lowercase hex groups, `::` accepted) plus `OSCPeerAllowlist` ("≤ 16" approved, "≤ 4" recently blocked, off by default, non-local refused) in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCPeerAllowlist.swift`. — Verified 2026-11-14: OSCPeerAllowlistTests (3 rule/text tests) pass (`swift test --package-path Packages/PerformanceControl`, 238 tests, 0 failures).
- [X] OSC-008-T03 `OSCTransportEvent.datagram` gains `peer: OSCPeerAddress? = nil` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDatagramTransport.swift`; `OSCReceiver` owns `peerAllowlist` and drops unapproved datagrams before `OSCDispatcher.handle` in `OSC/OSCReceiver.swift`; `droppedUnapproved` counter and `noteDroppedUnapproved()` in `OSC/OSCDispatcher.swift`. — Verified 2026-11-14: OSCPeerAllowlistTests acceptance passes (`received` stays 0 for unapproved datagrams); all OSC-001/002/003/009 receiver, dispatcher and flood tests unchanged and passing.
- [X] OSC-008-T04 `NetworkDatagramTransport` passes the address it already computed for the local check with each datagram (no new API) in `Packages/PerformanceControl/Sources/PerformanceControl/OSCTransport/NetworkDatagramTransport.swift`. — Verified 2026-11-14: OSCLoopbackIntegrationTests.testAllowlistBlocksAnUnapprovedLoopbackSenderUntilItIsApproved passes on the macOS host (real NWListener hands on 127.0.0.1); `check_network_symbols` OK.

## Phase 3: User Story 1 - Only my controller can change the show (P1)

**Independent test**: fake transport, allowlist on; unapproved routed message changes nothing, approved applies.

- [X] OSC-008-T05 [P] [US1] Rule and text tests (normalization, mapped IPv4, round trip, rejects, bounds) in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCPeerAllowlistTests.swift`. — Verified 2026-11-14: testMappedIPv4IsTheSameHostAndTextRoundTrips, testApproveRefusesNonLocalDuplicatesAndAFullList, testRecentlyBlockedKeepsFourDistinctHostsMostRecentFirst pass.
- [X] OSC-008-T06 [US1] Acceptance test (S1): unapproved host's glow route and test-value messages leave store values and live values unchanged and add to `droppedUnapproved` only; approved host (any port, mapped form) applies; allowlist off applies from anyone; unknown host dropped while on — in `OSCPeerAllowlistTests.swift`. — Verified 2026-11-14: testUnapprovedSourceAddressCannotChangeTheSceneAndAnApprovedOneCan and testWithTheAllowlistOffEveryLocalHostAppliesAsBefore pass.
- [X] OSC-008-T07 [US1] Seeded fuzz (S1): 500 datagrams, seeded generator, random malformed/valid bytes from random local, foreign and unknown hosts; only approved valid messages may change the store; unapproved ones never reach the decoder (`rejected` unchanged) — in `OSCPeerAllowlistTests.swift`. — Verified 2026-11-14: testSeededFuzzOfMalformedAndForeignSourcePacketsNeverChangesTheScene passes (500 datagrams, seed 0x05C8_0008).
- [X] OSC-008-T08 [US1] Loopback integration: real UDP to 127.0.0.1 with the allowlist on and nothing approved changes nothing and lists 127.0.0.1 as blocked; after approval it applies — in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLoopbackIntegrationTests.swift`. — Verified 2026-11-14: passes in 0.5 s for the three loopback tests (not skipped).
- [X] OSC-008-T09 [US1] `OSCPeersCoordinator` (load/validate/store `settings.osc.peerAllowlist.enabled` and `settings.osc.approvedPeers`, push to the receiver, refresh from counters on OSC-009's gated refresh only (S4: no main-thread work per datagram), clear blocked on OSC off) in `Apps/projectM-iOS/Coordinators/OSCPeersCoordinator.swift`; wiring in `OSCReceiverCoordinator.swift` and `AppCoordinator.swift`. — Verified 2026-11-14: OSCPeersCoordinatorTests pass on "OSC8 iPhone 17" (iOS 27.2); wired in `AppCoordinator.connectAfterInit`.

## Phase 4: User Story 2 - Approve the device that just tried (P2)

- [X] OSC-008-T10 [US2] App unit tests: allow from recently blocked, full list refused, remove, invalid stored entries dropped, keys persisted, blocked cleared when OSC is off — `Apps/projectM-iOS/Tests/OSCPeersCoordinatorTests.swift`. — Verified 2026-11-14: OSCPeersCoordinatorTests (3) pass on iOS 27.2; OSCReceiverCoordinatorTests (7), OSCRoutesCoordinatorTests (5), LibraryBackupAppTests (5) pass.
- [X] OSC-008-T11 [US2] `OSCPeersView` and the "Approved Devices" row in `oscSection` (`Apps/projectM-iOS/Views/OSCPeersView.swift`, `Views/SettingsView.swift`). — Verified 2026-11-14: OSCPeersUITests passes; OSCRoutesUITests and OSCNetworkAccessUITests still pass; OSCReceiverUITests passes (26.8 s) on a rerun alone (first batch run failed before Settings opened, at the controls' Settings button).
- [X] OSC-008-T12 [US2] UI test `Apps/projectM-iOS/UITests/OSCPeersUITests.swift` (< 30 s): open Approved Devices, switch on, empty-list note shown, row value updates. — Verified 2026-11-14: OSCPeersUITests.testApprovedDevicesTurnsOnAndExplainsAnEmptyList passes in 17.4 s.
- [ ] OSC-008-T13 {device} LAN check on D1 with a second device on Wi-Fi (quickstart step 5).

## Phase 5: Polish

- [X] OSC-008-T14 [P] Keys: `ALLOWED_KEYS` in `scripts/run_device_tests.py`, `LibrarySettingsPolicy.excludedKeys` in `Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`, `LibraryErasePolicy.settingsCategoryKeys` (FILE-011 erase does not derive excluded keys; R10) in `Packages/LibraryBackup/Sources/LibraryBackup/LibraryErasePolicy.swift`, the `-uitestResetNotice` reset in `AppCoordinator.swift`. — Verified 2026-11-14: LibraryBackup 77 tests pass; LibraryBackupAppTests passes; `test_scripts.py` 159 OK.
- [X] OSC-008-T15 [P] Privacy policy section and ADR-0058 (`docs/privacy-policy.md`, `docs/adr/0058-osc-peer-allowlist.md`). — Verified 2026-11-14: `validate_docs` OK; docs/adr/0058-osc-peer-allowlist.md indexed in docs/adr/README.md.
- [X] OSC-008-T16 Repo checks, `check_network_symbols` and `check_privacy_manifest.py` on the Debug app, type-check budget build. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; check_network_symbols OK and check_privacy_manifest OK on the Debug simulator app; type-check build shows no warning in changed files (the AppCoordinator init warning at line 361, 335 ms, remains after moving OSC-008's line out of it, so it predates this feature).

## Dependencies

T01 → T02 → T03 → T04; T05-T08 after T03/T04; T09 after T03; T10-T12 after T09; T14-T16 last. US2 depends on US1's coordinator.

## Parallel examples

T05 with T14 and T15 (different files).

## Implementation strategy

MVP is US1 (package filter + acceptance); US2 adds the Settings screen.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1-R13 and S1-S4 each map to at least one task (R1-R3 T02, T09; R4-R5 T02, T10; R6-R7 T03, T06, T07;
R8 T06, T08; R9 T11, T12; R10 T14; R11 T09, T10; R12 T15; R13 T04, T16; S3 T12). No constitution conflict; the
privacy narrowing is recorded in ADR-0058. Fixes applied: (1) MEDIUM — FILE-011's Settings erase lists excluded
keys by hand, so T14 now names `LibraryErasePolicy`; (2) LOW — S4 made explicit in T09.
