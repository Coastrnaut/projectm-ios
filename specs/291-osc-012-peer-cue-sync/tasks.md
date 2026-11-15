# Tasks: OSC-012 Peer Cue Sync

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/osc-cue-sync.md, quickstart.md
**Tests**: requested by the roadmap acceptance and the brief (pure fixtures with an injected clock, loopback, app, UI).

## Phase 1: Setup

- [X] OSC-012-T01 Write ADR-0102 (new outbound message class `/projectm/cue`, amends ADR-0088 decision 4) in docs/adr/0102-osc-peer-cue-sync.md and list it in docs/adr/README.md — Verified 2026-11-15: docs/adr/0102-osc-peer-cue-sync.md written and indexed; validate_docs OK

## Phase 2: Foundational (pure model, PerformanceControl)

- [X] OSC-012-T02 Implement `OSCCueSyncRole`, `OSCCueSyncMessage` (address `/projectm/cue`, types `s i i i`, "cueID 1…64 UTF-8 bytes", "seq ≥ 1", "offset ≥ 0, clamped to Int32.max", session) with encode and parse in Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCCueSync.swift — Verified 2026-11-15: OSCCueSyncTests testWireBytesAndRoundTrip, testMalformedMessagesAreRefused (swift test, PerformanceControl 350 tests pass)
- [X] OSC-012-T03 Implement `OSCCueSyncLeader` (burst 0/100/300 ms, heartbeat 2 s, overdue slots collapse, newer change cancels older burst) in the same file — Verified 2026-11-15: OSCCueSyncTests testLeaderBurstThenHeartbeat
- [X] OSC-012-T04 Implement `OSCCueSyncFollower` (contract C3) and `OSCCueSyncInbox` (8 entries, one pending hop) in the same file — Verified 2026-11-15: OSCCueSyncTests testFollowerAppliesNewestOnlyAndAligns, testInboxKeepsEightAndAsksForOneHop
- [X] OSC-012-T05 Add `OSCDispatcher.setMessageTap(address:handler:)`, outcome `.tapped`, counter `tapped` in Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDispatcher.swift — Verified 2026-11-15: OSCCueSyncTests testTapReceivesOnlyAllowedMessages; OSCDispatcherTests/OSCReceiverTests unchanged and passing
- [X] OSC-012-T06 Add `OSCSender.postCue(_:)` (no kind filter, 60/s cap) in Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCSender.swift — Verified 2026-11-15: OSCCueSyncTests testPostCueUsesTheDestinationAndTheCapButNotTheKinds

## Phase 3: User Story 1 - A follower stays on the leader's cue (P3)

**Independent test**: leader and follower models through a fake network; real UDP loopback.

- [X] OSC-012-T07 [P] [US1] Unit tests for message round trip, malformed cases and leader schedule in Packages/PerformanceControl/Tests/PerformanceControlTests/OSCCueSyncTests.swift — Verified 2026-11-15: swift test --filter OSCCueSync (host): 7 tests pass
- [X] OSC-012-T08 [P] [US1] Loopback test: OSCSender over NetworkOSCSender to an OSCReceiver (NetworkDatagramTransport, 127.0.0.1 approved, allow list on) whose tap feeds a follower; the follower applies the leader's cue in Packages/PerformanceControl/Tests/PerformanceControlTests/OSCCueSyncLoopbackTests.swift — Verified 2026-11-15: OSCCueSyncLoopbackTests passes on the macOS host over real UDP on 127.0.0.1 (not skipped)
- [X] OSC-012-T09 [US1] App coordinator `OSCCueSyncCoordinator` (role key, leader timer chained onto `show.cueStarted`, follower inbox drain and `stepNow(.go(id))`, status texts) in Apps/projectM-iOS/Coordinators/OSCCueSyncCoordinator.swift — Verified 2026-11-15: OSCCueSyncCoordinatorTests (4) pass on OSC12 iPhone 17 (iOS 27.2)
- [X] OSC-012-T10 [US1] Wire it: `OSCReceiverCoordinator.cueSync` (+ `conditionsChanged` from `apply`), `OSCSendCoordinator.postCue`, creation in AppCoordinator.connectAfterInit, timed-advance hold in AppCoordinator+Show `makeShowAutoAdvance` — Verified 2026-11-15: OSCCueSyncCoordinatorTests, OSCSendCoordinatorTests, OSCReceiverCoordinatorTests pass; build-for-testing with type-check warnings flags shows none in touched files
- [X] OSC-012-T11 [US1] Cue Sync screen and Settings › OSC row in Apps/projectM-iOS/Views/OSCCueSyncView.swift and Apps/projectM-iOS/Views/SettingsView.swift — Verified 2026-11-15: OSCCueSyncUITests passes (20 s)
- [X] OSC-012-T12 [US1] App tests: follower's show steps to the cue; already on it → no re-apply; leader posts `/projectm/cue` through a fake send transport; timed advance held while following; following works while the scene is locked and changes no setting (R11); status texts (R14) in Apps/projectM-iOS/Tests/OSCCueSyncCoordinatorTests.swift — Verified 2026-11-15: OSCCueSyncCoordinatorTests testFollowerShowStepsToTheLeadersCue, testLateJoinerRecoversFromTheNextRepeat

## Phase 4: User Story 2 - Packet loss recovers without infinite retransmission (P3)

- [X] OSC-012-T13 [US2] Packet-loss fixture: seeded 50% loss, first-3 burst loss, 5 s outage; convergence by burst or next heartbeat; ≤ 3 sends per cue change; ≤ 31 sends in 60 s without changes in Packages/PerformanceControl/Tests/PerformanceControlTests/OSCCueSyncLossTests.swift — Verified 2026-11-15: OSCCueSyncLossTests (4) pass: 50% seeded, first-3 burst, 5 s outage, 60 s bound (33 sends: 3 burst + 30 heartbeats)

## Phase 5: User Story 3 - Only approved, newest, known cues (P3)

- [X] OSC-012-T14 [P] [US3] Follower tests: duplicates, reordering, new session, unknown cue reported once, unapproved ignored, malformed ignored; inbox keeps at most 8 and asks for one hop until taken (R13) in OSCCueSyncTests.swift — Verified 2026-11-15: OSCCueSyncTests testFollowerAppliesNewestOnlyAndAligns, testUnknownUnapprovedAndMalformedNeverApply, testInboxKeepsEightAndAsksForOneHop
- [X] OSC-012-T15 [P] [US3] Receiver tap test with a fake transport: unapproved host dropped before the tap; approved host tapped; no tap → unknown address in OSCCueSyncTests.swift — Verified 2026-11-15: OSCCueSyncTests testTapReceivesOnlyAllowedMessages
- [X] OSC-012-T16 [US3] App test: unknown cue reported and not applied; allow list off → nothing applied, in OSCCueSyncCoordinatorTests.swift — Verified 2026-11-15: OSCCueSyncCoordinatorTests testUnknownCueIsReportedAndAllowListOffAppliesNothing

## Phase 6: User Story 4 - Off by default (P3)

- [X] OSC-012-T17 [US4] Register `settings.osc.cueSync.role` in scripts/run_device_tests.py ALLOWED_KEYS, LibrarySettingsPolicy.excludedKeys (Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift), the `-uitestResetNotice` reset in AppCoordinator and Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift — Verified 2026-11-15: LibraryBackupAppTests and SettingsTests pass on the simulator; LibraryBackup package 88 tests pass (erase policy oscCueSyncKeys); test_scripts 186 OK
- [X] OSC-012-T18 [US4] UI test: Cue sync Off by default, Lead and Follow selectable with a status line, under 30 s, in Apps/projectM-iOS/UITests/OSCCueSyncUITests.swift — Verified 2026-11-15: OSCCueSyncUITests testRoleIsOffByDefaultAndLeadAndFollowAreSelectable (20.0 s)
- [X] OSC-012-T19 [US4] App test: fresh defaults → role Off, nothing posted on a cue step, no tap installed, in OSCCueSyncCoordinatorTests.swift — Verified 2026-11-15: OSCCueSyncCoordinatorTests testOffByDefaultSendsAndAppliesNothing

## Phase 7: Polish

- [X] OSC-012-T20 Privacy policy and permission texts mention cue sync (docs/privacy-policy or equivalent, `PermissionCatalog` only if its text lists message kinds) — Verified 2026-11-15: docs/privacy-policy.md Cue Sync paragraph; the Local Network usage string already covers sending to the one local device; check_permission_catalog OK
- [X] OSC-012-T21 Repo checks: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts, check_privacy_manifest, check_network_symbols; type-check budget; PosterBoard counts — Verified 2026-11-15: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events, test_scripts, check_privacy_manifest and check_network_symbols on the Debug app all OK
- [ ] OSC-012-T22 {device} Two devices on one Wi-Fi follow quickstart "Two devices": B follows A's cues and recovers after a 10 s Wi-Fi outage within about 2 s

## Dependencies

T01 → T02 → T03, T04 → T05, T06 → US1 (T07-T12) → US2 (T13), US3 (T14-T16), US4 (T17-T19) → T20-T21. T22 after all.
Parallel: T07/T08 (different files), T14/T15.

## Strategy

The model first (T02-T06) with its tests (T07, T13, T14, T15), then the app glue (T09-T12, T16-T19).
