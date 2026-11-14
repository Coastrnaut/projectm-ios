# Tasks: MIDI-008 MIDI Transport Mapping

**Input**: `specs/157-midi-008-transport/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-008-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-008-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI8 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; `Build` symlink present; simulator BDA43CC3 "MIDI8 iPhone 17" (iOS 27.2); PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-008-T02 [P] `MIDIPressFilter` (`rawEdge`, `accept`, `beginBatch`, `registerPress`; 30 ms window on message timestamps; momentary real-time) and `MIDIEvent.triggerKey` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDIPressFilter.swift` (research MIDI-008-D2, D3; contract T1) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 196 tests, 0 failures, 23.7 s; MIDITransportTests `testFilterRulesAndHysteresis`
- [X] MIDI-008-T03 [P] Transport actions and trigger keys in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift`: `transport.toggle|play|pause`, `ccbtn:` and `rt:start|stop` lines (real-time with hold unreadable, kept), `isTriggerLine`, list reads all three tags; `MIDILearnEligibility.isTriggerEligible` in `MIDILearnSession.swift` (research MIDI-008-D1, D4; contract T3) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 196 tests, 0 failures, 23.7 s; `testTriggerLinesRoundTripBesideEveryOtherLine`, `testBindRejectsRealTimeOnTheHoldRowAndTitles`, `testTriggerLearnEligibility`
- [X] MIDI-008-T04 `MIDINoteRouter` over `MIDIPressFilter` in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteRouter.swift` (unbound keys skipped first; panic unchanged; `registerPress` for learn) (contract T2) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 196 tests, 0 failures, 23.7 s; MIDINoteTriggerTests 11/11 (fixture batches now 100 ms apart), `testUnboundCCNeverReachesTheFilterAndHoldWorksWithACCButton`, `testRegisteredLearningPressSilencesItsCopies`

## Phase 3: User Story 1 - One press, one action (P1) — MVP

**Independent test**: each source kind and repeat pattern fires once per press; a deliberate second press fires again.

- [X] MIDI-008-T05 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDITransportTests.swift`: filter rules; CC hysteresis; acceptance for note, CC button and real-time × (doubled in one packet list, doubled across two batches 5 ms apart, CC 127 repeated with no 0) through `MIDIByteStreamParser`; deliberate second press; codec round-trip; mixed MIDI-003/004/006/007 lines unchanged; host and the Linux shape (S1, S3, S4, R8) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 196 tests, 0 failures, 23.7 s; MIDITransportTests 10/10 (`testDoubledInOnePacketListFiresOnce`, `testDoubledAcrossTwoBatchesFiveMillisecondsApartFiresOnce`, `testCC127RepeatedWithoutAZeroFiresOnce`, `testADeliberateSecondPressFiresAgain`)
- [X] MIDI-008-T06 [US1] App test `Apps/projectM-iOS/Tests/MIDITransportCoordinatorTests.swift`: fake MIDI source → `MIDIMappingCoordinator` → `MIDINoteActionPerformer` with logged actions; the three patterns for each source kind fire Next cue once per press (S1) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI8 iPhone 17" (iOS 27.2): MIDITransportCoordinatorTests 5/5, MIDINoteTriggerCoordinatorTests 7/7, MIDIMappingCoordinatorTests 14/14, MIDISceneSelectionCoordinatorTests 7/7, LibraryBackupAppTests 5/5, ThresholdTriggerAppTests 2/2 (40 tests, 0.39 s); `testEverySourceKindFiresOncePerPressDespiteRepeatedPackets`

## Phase 4: User Story 2 - Play and pause (P1)

- [X] MIDI-008-T07 [US2] Performer transport actions in `Apps/projectM-iOS/Coordinators/MIDINoteActionPerformer.swift`; `setPausedQuietly(_:)` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift`; wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift`; app tests: toggle twice pauses then resumes, Play and Pause idempotent, Start → Play / Stop → Pause (research MIDI-008-D5; S2) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI8 iPhone 17" (iOS 27.2): MIDITransportCoordinatorTests 5/5, MIDINoteTriggerCoordinatorTests 7/7, MIDIMappingCoordinatorTests 14/14, MIDISceneSelectionCoordinatorTests 7/7, LibraryBackupAppTests 5/5, ThresholdTriggerAppTests 2/2 (40 tests, 0.39 s); `testPlayPauseTogglesAndPlayAndPauseAreIdempotent` (the app's `setPausedQuietly` is exercised by the wiring build only; its visual effect is not asserted on the simulator)

## Phase 5: User Story 3 - Learn a transport source (P2)

- [X] MIDI-008-T08 [US3] Trigger learn in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift` (note, CC button, real-time; not real-time on the hold row; learned press registered; texts "CC 20 · Ch 1", "MIDI Start"; CC button ↔ parameter exclusivity) and the MIDI-003 side in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift`; app tests: learn a CC button (learning press fires nothing, duplicate copy fires nothing, two later presses fire twice), learn MIDI Start, moved from a glow parameter and back, Undo, a CC button held on Black out while held is released when the input stops (research MIDI-008-D6, D7; R6, R7) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI8 iPhone 17" (iOS 27.2): MIDITransportCoordinatorTests 5/5, MIDINoteTriggerCoordinatorTests 7/7, MIDIMappingCoordinatorTests 14/14, MIDISceneSelectionCoordinatorTests 7/7, LibraryBackupAppTests 5/5, ThresholdTriggerAppTests 2/2 (40 tests, 0.39 s); `testLearnACCButtonItsCopiesFireNothingThenItTriggers`, `testLearnMIDIStartAndBackToAParameter`, `testAHeldCCButtonIsReleasedWhenTheInputStops`
- [X] MIDI-008-T09 [US3] View: "Transport" section header and footer in `Apps/projectM-iOS/Views/MIDIMappingsView.swift`; DEBUG "Send CC Button" in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift` — Verified 2026-11-14: build-for-testing with the type-check flags: no warning in touched files (the warnings listed are existing code under 200 ms); exercised by MIDITransportUITests
- [X] MIDI-008-T10 [US3] UI test `Apps/projectM-iOS/UITests/MIDITransportUITests.swift` (under 30 s): seeded show, plug Fake Keys, MIDI Mappings → Learn on Next cue, Send CC Button, read the result, press twice, cue 3 is applied (S5) — Verified 2026-11-14: `xcodebuild test-without-building -only-testing:projectM-iOSUITests/MIDITransportUITests` on "MIDI8 iPhone 17": passed in 23.1 s (MIDINoteTriggersUITests 21.1 s and MIDISceneSelectionUITests 17.3 s also pass)

## Phase 6: Polish

- [X] MIDI-008-T11 Update the MIDI-006 assertions on the row list and the CC-in-note-learn fixture; type-check budget on touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols); PosterBoard count; delete the simulator and derived data (S6) — Verified 2026-11-14: MIDI-006 assertions updated (row list, CC fixture below 64, batch spacing, UI test opens Settings at MIDI and no longer scrolls back to the row: 42.7 s → 21.1 s); check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 tests OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app; PosterBoard 25 before and after; simulator and derived data deleted
- [ ] MIDI-008-T12 {device} With a physical controller on D1, map a CC button and a pad to Next cue and Play/Pause; each press acts once

## Dependencies

T01 → T02, T03 (parallel) → T04 → US1 (T05, T06) → US2 (T07) → US3 (T08-T10) → T11 → T12.

## Parallel examples

- T02 and T03 touch different files.
- T05 (package tests) can be written while T07 is built.

## Implementation strategy

MVP is US1 (the row's acceptance). US2 adds the play/pause actions; US3 adds learn and the UI test.
