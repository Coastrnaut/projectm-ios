# Tasks: OSC-004 OSC Learn

**Input**: `specs/274-osc-004-osc-learn/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row (unit tests with an injected clock and fake transport, a loopback
integration test, device LAN last). No wall-clock assertions; unit tests about 1-2 s, package suite < 1 min,
UI test < 30 s (owner rule 7). Tasks are ticked only when verified, with " — Verified 2026-11-14: <how>".

## Phase 1: Setup

- [X] OSC-004-T01 Audit OSC-001/002/003/007/008/009 and MIDI-003/005 learn; record the baseline table in `specs/274-osc-004-osc-learn/spec.md`. — Verified 2026-11-14: spec.md "Baseline" table (no OSC capture existed; MIDILearnSession is the pattern).

## Phase 2: Foundational (package)

- [X] OSC-004-T02 `OSCLearnEligibility`, `OSCLearnSession`, `OSCLearnOutcome`, `OSCLearnResolution`, `OSCLearnBinding` in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCLearn.swift` (R3, R5, R7, R8). — Verified 2026-11-14: OSCLearnTests (4) pass; `swift test --package-path Packages/PerformanceControl` 291 tests, 0 failures, 12.9 s.
- [X] OSC-004-T03 Learn capture in `Packages/PerformanceControl/Sources/PerformanceControl/OSC/OSCDispatcher.swift`: `armLearn`, `disarmLearn`, `isLearnArmed`; capture after rate admission and decode, disarm under the lock, handler called after the lock (R4, R5, R6, R12). — Verified 2026-11-14: OSCLearnTests acceptance and rate-limit tests pass; every existing OSC dispatcher, flood, routes and allowlist test still passes (291 total).

## Phase 3: User Story 1 - Bind my controller's fader by moving it (P2)

**Independent test**: dispatcher with a fake clock; a burst binds exactly the first address; a later message drives the parameter.

- [X] OSC-004-T04 [US1] Acceptance tests in `Packages/PerformanceControl/Tests/PerformanceControlTests/OSCLearnTests.swift`: burst of eligible messages (and a bundle) records exactly one address; the captured message itself applies no value to the parameter (R6) and the bound alias routes the next message to it; session times out at 10 s on the clock with no binding; cancel; binding resolutions (added, replaced, already, full) (S1, S3). — Verified 2026-11-14: OSCLearnTests.testLearnRecordsOneAllowedAddressFromABurstAndExitsAfterTimeoutOtherwise (burst + bundle record only `/1/fader3`, no value applied, next message drives the parameter, 10 s timeout on the fake clock), testCancelAndRestartAndDisarm, testBindingResolutions pass.
- [X] OSC-004-T05 [US1] Loopback integration: real UDP to 127.0.0.1 with learn armed captures one address (`OSCLoopbackIntegrationTests.swift`, macOS host only, as the existing loopback tests). — Verified 2026-11-14: OSCLoopbackIntegrationTests.testLearnCapturesOneAddressFromARealLoopbackBurst passes on the macOS host (not skipped, 0.002 s).
- [X] OSC-004-T06 [US1] `OSCRoutesCoordinator.bindLearned` in `Apps/projectM-iOS/Coordinators/OSCRoutesCoordinator.swift`; `OSCLearnCoordinator` (start, capture, timeout via injected clock and scheduler, cancel, leave, receiver stopped, `.osc` announcements) in `Apps/projectM-iOS/Coordinators/OSCLearnCoordinator.swift`; wiring in `OSCReceiverCoordinator.swift` and `AppCoordinator.swift` (R1, R2, R8, R9, R10). — Verified 2026-11-14: OSCLearnCoordinatorTests (2) pass on "OSC4 iPhone 17" (iOS 27.2); wired in `AppCoordinator.connectAfterInit`.
- [X] OSC-004-T07 [US1] DEBUG fake OSC source `Apps/projectM-iOS/Debug/UITestFakeOSC.swift` (`-uitestFakeOSC`: a transport that reports ready and injects datagrams from 192.168.1.20; no Network framework). — Verified 2026-11-14: used by OSCLearnCoordinatorTests and OSCLearnUITests; `check_network_symbols` OK on the Debug app.
- [X] OSC-004-T08 [US1] App tests `Apps/projectM-iOS/Tests/OSCLearnCoordinatorTests.swift` with the fake source: arm, burst, bound alias persisted in `settings.osc.aliases` and driving the live value; timeout and cancel; receiver off ends learn; Learn disabled while off. — Verified 2026-11-14: OSCLearnCoordinatorTests.testArmInjectBurstBindsOneAliasThatPersistsAndDrivesTheGlow and testTimeoutCancelReplaceAndReceiverOff pass (0.11 s).
- [X] OSC-004-T09 [US1] Learn section in OSC Routes (`Apps/projectM-iOS/Views/OSCLearnSection.swift`, `Views/OSCRoutesView.swift`, `Views/SettingsView.swift`). — Verified 2026-11-14: OSCLearnUITests passes; OSCRoutesUITests still passes.
- [X] OSC-004-T10 [US1] UI test `Apps/projectM-iOS/UITests/OSCLearnUITests.swift` (< 30 s): arm, inject, bound row shown (S4: two taps from OSC Routes). — Verified 2026-11-14: OSCLearnUITests.testArmInjectBound passes in 20.0 s alone (36.1 s in the first batch run, which included the simulator's first boot).

## Phase 4: User Story 2 - Nothing else gets bound (P2)

- [X] OSC-004-T11 [US2] Tests in `OSCLearnTests.swift`: a disallowed peer (receiver with the allow list on and a fake transport) is ignored and not approved; malformed datagrams, invalid or `/projectm/` addresses and non-numeric or multi-argument messages are ignored; a rate-limited datagram is not learned (S2). — Verified 2026-11-14: OSCLearnTests.testMalformedInvalidReservedNonNumericAndRateLimitedMessagesAreNotLearned and the disallowed-peer step of the acceptance test pass.

## Phase 5: Polish

- [X] OSC-004-T12 [P] `scripts/check_status_events.py` lists the new coordinator and section; R11: keys unchanged (no new UserDefaults key, no peer address stored: LibraryBackupAppTests and SettingsTests still pass). — Verified 2026-11-14: check_status_events OK; LibraryBackupAppTests (5) and SettingsTests (9) pass; no key added.
- [X] OSC-004-T13 Repo checks, `check_network_symbols` and `check_privacy_manifest.py` on the Debug app, type-check budget build, PosterBoard counts. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts OK; check_network_symbols OK and check_privacy_manifest OK on the Debug simulator app; type-check build with the 300/150 ms flags shows no warning in changed files; PosterBoard reports 31 before and after.
- [ ] OSC-004-T14 {device} LAN controller on D1 (quickstart step 4).

## Dependencies

T01 → T02 → T03 → T04, T05, T11; T06 after T03; T07 → T08; T09 after T06; T10 after T07 and T09; T12, T13 last.

## Parallel examples

T04 with T07 (different files); T12 with T09.

## Implementation strategy

Package first (pure, Linux-safe tests), then the app coordinator with the fake source, then the screen and the UI test.

## Analysis (speckit-analyze, 2026-11-14)

Coverage: R1 T09-T10; R2 T06, T08; R3 T02, T11; R4 T11; R5 T03-T04; R6 T04; R7 T04, T06; R8 T04, T08; R9 T08; R10 T06, T12; R11 T12; R12 T11; S1 T04; S2 T11; S3 T04; S4 T10. Fixes applied: R6 got an explicit assertion in T04, R11 a check in T12, S4 in T10. No constitution conflict; no ambiguity left.
