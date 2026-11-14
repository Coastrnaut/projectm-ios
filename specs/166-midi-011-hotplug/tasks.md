# Tasks: MIDI-011 MIDI Hot-Plug Recovery

**Input**: `specs/166-midi-011-hotplug/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-011-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-011-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI11 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; `Build` symlink present; simulator 740444B9 "MIDI11 iPhone 17" (iOS 27.2); PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-011-T02 `MIDISourceSystem`, `MIDISourceSnapshot`, `MIDISubscriptionRegistry` ("An entry exists iff exactly one connection to that handle is live"; `lost` ⊆ `disconnected`), `MIDIReconcileResult` and `MIDISourceSubscriptions` (coalesced `setupChanged`, `sourceRemoved(handle:)`, `update(wanted:)`, `close()`, counters) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDISourceSubscriptions.swift` (research MIDI-011-D1-D4; contract H1-H3) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 207 tests, 0 failures, 34.8 s; MIDIHotplugTests 11/11 (`testRegistryReportsLostSubsetOfDisconnected`, `testABurstCostsOneReconcile`)
- [X] MIDI-011-T03 [P] `ScriptedMIDISourceSystem` (new handle per plug, per-handle connection counts, removal/setup notifications, bursts, `send(_:from:timestamp:)` once per live connection) and `ScriptedMIDISourceInputProvider` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/ScriptedMIDISourceSystem.swift` (D6) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 207 tests, 0 failures, 34.8 s; MIDIHotplugTests 11/11 (`testTheFixtureMakesDuplicatesVisible`)
- [X] MIDI-011-T04 `MIDIInputProvider.sourceLossCount` (default 0) and `MIDIInputService.sourceLossCount` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIInputService.swift` (D5; contract H4) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 207 tests, 0 failures, 34.8 s; MIDIHotplugTests 11/11 (`sourceLossCount` asserted in the acceptance test)

## Phase 3: User Story 1 - Unplug and replug keeps one listener (P1) — MVP

**Independent test**: the A/B fixture keeps exactly one live connection per present endpoint at every step.

- [X] MIDI-011-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDIHotplugTests.swift`: the A/B acceptance fixture (connect both, remove A, re-add A with a new handle and same unique number, repeated setup notifications, remove/re-add B twice incl. inside one burst; at every step one connection per present endpoint, zero for absent, one delivery per message from A, loss reported for removed endpoints); unique-number collision fallback; a burst → one reconcile; same-handle replug via removal mark; failed connect retried next reconcile; offline counts as lost, unwanted does not; close; 20 cycles without growth; host and the Linux shape (`-DANALYSIS_NO_ACCELERATE`, no Apple-only API in the tested files) (S1-S4, R8) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 207 tests, 0 failures, 34.8 s; MIDIHotplugTests 11/11 (`testDisconnectAndReconnectFixtureYieldsOneLiveListenerPerEndpoint` and the rest; Linux shape: no Apple-only API in the tested sources, CI runs Linux)
- [X] MIDI-011-T06 [US1] `CoreMIDIInputProvider` over `MIDISourceSubscriptions`: notify block on the input client (removed source → `sourceRemoved`; added/removed/setup/property changed → `setupChanged`), `CoreMIDISourceSystem` (enumeration as before, `MIDIPortConnectSource`/`MIDIPortDisconnectSource`), receive block unchanged, in `Packages/PerformanceControl/Sources/PerformanceControl/MIDISystem/CoreMIDIInputProvider.swift` (D3, D4) — Verified 2026-11-14: build-for-testing of the app for the iOS 27.2 simulator and `swift build` on the macOS host compile it with no warnings; the existing CoreMIDI receive-block test (`MIDIInputServiceTests`) passes in the 207-test package run. The notify path's behavior with real hardware is T12 {device}

## Phase 4: User Story 2 - A mapped control survives a reconnect (P1)

- [X] MIDI-011-T07 [US2] Loss → release: `MIDIInputCoordinator.drain()` runs state observers when `sourceLossCount` changed (before the batch) in `Apps/projectM-iOS/Coordinators/MIDIInputCoordinator.swift`; `releaseNotesIfInputChanged()` releases on a changed loss count in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift` with `lastLossCount` in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift` (R5) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI11 iPhone 17" (iOS 27.2): MIDIHotplugCoordinatorTests 4/4, MIDIDiscoveryCoordinatorTests 9/9, MIDIMappingCoordinatorTests 14/14, MIDINoteTriggerCoordinatorTests 8/8, MIDITransportCoordinatorTests 5/5, MIDISceneSelectionCoordinatorTests 7/7, MIDIMonitorCoordinatorTests 7/7 (54 tests, 3.6 s); `testAQuickReplugRepairsTheListenerAndReleasesAHeldKey`
- [X] MIDI-011-T08 [US2] DEBUG fake over the source system: `UITestFakeMIDI` input = `ScriptedMIDISourceInputProvider`, Plug/Unplug update both fakes, sends come from Fake Keys, in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift` (R9) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI11 iPhone 17": MIDIDiscoveryUITests (38.4 s), MIDIMonitorUITests (34.9 s), MIDILearnUITests (15.5 s) pass on the new fake (the first two are existing tests over the 30 s UI budget, including the run's cold launch; not changed here)
- [X] MIDI-011-T09 [US2] App tests `Apps/projectM-iOS/Tests/MIDIHotplugCoordinatorTests.swift`: a CC 7 mapping changes its parameter once per message after unplug/replug (one event drained, no double trigger); a held note trigger is released on a quick replug that leaves discovery's list unchanged (S5) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI11 iPhone 17" (iOS 27.2): MIDIHotplugCoordinatorTests 4/4, MIDIDiscoveryCoordinatorTests 9/9, MIDIMappingCoordinatorTests 14/14, MIDINoteTriggerCoordinatorTests 8/8, MIDITransportCoordinatorTests 5/5, MIDISceneSelectionCoordinatorTests 7/7, MIDIMonitorCoordinatorTests 7/7 (54 tests, 3.6 s); `testAMappedCCAndNoteWorkOnceAfterAReconnect`, `testAQuickReplugRepairsTheListenerAndReleasesAHeldKey`

## Phase 5: User Story 3 - Reconnect announcement (P2)

- [X] MIDI-011-T10 [US3] `MIDIDiscoveryCoordinator`: IDs seen since start (cleared on stop), `announcement(for:seen:)` with "MIDI device reconnected: <device>" / "<n> MIDI devices reconnected" in `Apps/projectM-iOS/Coordinators/MIDIDiscoveryCoordinator.swift`; app test in `Apps/projectM-iOS/Tests/MIDIHotplugCoordinatorTests.swift` (disconnected then reconnected; a new device still "connected"; after stop/start "connected") (R6, D7) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI11 iPhone 17" (iOS 27.2): MIDIHotplugCoordinatorTests 4/4, MIDIDiscoveryCoordinatorTests 9/9, MIDIMappingCoordinatorTests 14/14, MIDINoteTriggerCoordinatorTests 8/8, MIDITransportCoordinatorTests 5/5, MIDISceneSelectionCoordinatorTests 7/7, MIDIMonitorCoordinatorTests 7/7 (54 tests, 3.6 s); `testAReturningDeviceIsAnnouncedReconnected`, `testAnnouncementTextsForSeveralDevices`

## Phase 6: Polish

- [X] MIDI-011-T11 Re-run the MIDI package suites and the existing MIDI app tests and `MIDIDiscoveryUITests`/`MIDIMonitorUITests` on the new fake; type-check budget on touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols); PosterBoard count; delete the simulator and derived data (S6) — Verified 2026-11-14: package 207/207 (34.8 s); app MIDI tests 54/54; UI tests 3/3; build-for-testing with the type-check flags: no warning in touched files; check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 tests OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app; PosterBoard 25 before and after; simulator and derived data deleted
- [ ] MIDI-011-T12 {device} On D1 with a USB controller mapped to a glow parameter and a pad to Next cue, unplug and replug (also quickly); each movement and press acts once afterwards and the reconnect is announced

## Dependencies

T01 → T02 → T03, T04 (parallel) → US1 (T05, T06) → US2 (T07-T09) → US3 (T10) → T11 → T12.

## Parallel examples

- T03 and T04 touch different files.
- T06 (CoreMIDI) can be written while T05's tests run.

## Implementation strategy

MVP is US1 (the row's acceptance, proven in the package). US2 carries it into the app's mappings; US3 adds the
spoken reconnect.
