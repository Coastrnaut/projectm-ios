# Tasks: MIDI-007 MIDI Scene Selection

**Input**: `specs/147-midi-007-scene-selection/` (spec, plan, research, data-model, contracts, quickstart)

Tests are required by the spec (MIDI-007-S1 to S6). Budgets (owner rule 7): unit tests about 1-2 s (≤ 10 s), package
suite under 1 minute, UI test under 30 s, each xcodebuild run under 10 minutes. `{device}` tasks are the final device
stage and stay open until a person runs them.

## Phase 1: Setup

- [X] MIDI-007-T01 Run `xcodegen generate`, initialize the preset submodules if missing (the `Build` symlink is in place), create the simulator "MIDI7 iPhone 17" (iOS 27.2) and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any run — Verified 2026-11-14: `xcodegen generate`; preset submodules initialized; `Build` symlink present; simulator 7F959C5B "MIDI7 iPhone 17" (iOS 27.2); PosterBoard reports 25 before

## Phase 2: Foundational (blocks every story)

- [X] MIDI-007-T02 [P] `MIDISceneBinding` (lines `pc:<ch 0-15>:<program 0-127>=cue.go:<sceneID>` and `note:<ch>:<note>=cue.go:<sceneID>`, scene ID "1–64 characters of letters, digits, `-`, `_`, `.`", extras kept; `isSceneLine`), `MIDIProgramCueMode` (`pc:<ch|*>:*=cue.position`, off by default) and `MIDISceneBindingList` (≤ 128, no two share a key, no two share a scene ID, unreadable scene lines kept, `bind`/`remove`) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDISceneBinding.swift` (research MIDI-007-D1, D2; contract S1, S2) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE`: 186 tests, 0 failures, 40.9 s; MIDISceneSelectionTests 7/7 (`testSceneLinesRoundTripBesideCCAndNoteTriggerLines`, `testModeLinesAndSceneIDs`, `testBindMovesReplacesAndCapacity`)
- [X] MIDI-007-T03 [P] `MIDINoteBindingList(storageLines:)` skips scene lines in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDINoteBinding.swift`; `MIDILearnEligibility.isSceneEligible` (program change, or note on with velocity > 0) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDILearnSession.swift` (research MIDI-007-D2, D6) — Verified 2026-11-14: same package run; `testSceneLinesRoundTripBesideCCAndNoteTriggerLines` (MIDI-006 list skips scene lines), `testSceneLearnEligibility`; MIDINoteTriggerTests 11/11 (fixture now uses `cue.fire:` as the unknown action)
- [X] MIDI-007-T04 `MIDISceneRouter` and `MIDISceneCommand` (`.scene(id, key)`, `.cue(index, key)`; newest per batch; explicit program mappings before the mode; notes on the down edge only) in `Packages/PerformanceControl/Sources/PerformanceControl/MIDI/MIDISceneRouter.swift` (research MIDI-007-D3; contract S3) — Verified 2026-11-14: same package run; `testRouterFiltersChannelsAndTheNewestWins`, `testPositionModeAndExplicitMappingsWin`, `testParsedProgramChangeRoutes`
- [X] MIDI-007-T05 Coordinator scene state in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator.swift` and `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Scenes.swift`: load and save scene lines after the note lines, a scene learn session (one session at a time), the learning message removed before routing, routing to `performScenes`, input client while scene mappings or the mode exist, Undo over the three lists (contract S4) — Verified 2026-11-14: `xcodebuild test-without-building` on "MIDI7 iPhone 17" (iOS 27.2): MIDISceneSelectionCoordinatorTests 7/7, MIDINoteTriggerCoordinatorTests 7/7, MIDIMappingCoordinatorTests 14/14, ShowCoordinatorTests 5/5, LibraryBackupAppTests 8/8 (41 tests, 0.44 s)

## Phase 3: User Story 1 - A program change recalls a scene (P1) — MVP

**Independent test**: PC 5 / channel 1 mapped to scene X selects X with byte-identical stored mappings.

- [X] MIDI-007-T06 [US1] Package tests `Packages/PerformanceControl/Tests/PerformanceControlTests/MIDISceneSelectionTests.swift`: codec round-trip; mixed `cc:` + `note:` trigger + scene lines (MIDI-003/004/006 lines unchanged); unknown and unreadable scene lines kept; list moves and capacity; router channel filtering, newest wins, explicit before mode; eligibility; host and the Linux shape (`-Xswiftc -DANALYSIS_NO_ACCELERATE`) (S2-S4, R11) — Verified 2026-11-14: `swift test --package-path Packages/PerformanceControl -Xswiftc -DANALYSIS_NO_ACCELERATE` (Linux shape): 186 tests, 0 failures; host filter run 29/29 in 10.2 s
- [X] MIDI-007-T07 [US1] `MIDISceneActionPerformer` in `Apps/projectM-iOS/Coordinators/MIDISceneActionPerformer.swift` (debounce on the active cue's scene or index, "Scene not found." / "Cue n not found." on `.midi`, Go to Cue otherwise) and wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift` (research MIDI-007-D3, D5) — Verified 2026-11-14: same app run; `testAMissingSceneIsAnnouncedAndChangesNothing`, debounce and "Cue n not found." in `testProgramChangeSelectsTheSceneWithoutChangingStoredMappings`
- [X] MIDI-007-T08 [US1] App test `Apps/projectM-iOS/Tests/MIDISceneSelectionCoordinatorTests.swift`: fake MIDI source → real `ShowCoordinator` over a temporary store; PC 5 on channel 1 selects scene X (active cue and applied scene), stored mappings byte-identical (property-list encoding) before and after, with a scene that carries SCN-001 bindings; channel 2 does nothing; a repeat re-applies nothing; a missing scene is announced and changes nothing (S1, S2) — Verified 2026-11-14: same app run; `testProgramChangeSelectsTheSceneWithoutChangingStoredMappings` (active cue and applied scene = X, binary property-list bytes of `settings.midi.mappings` equal before and after, scene X carries an SCN-001 binding and is applied through `AppCoordinator.set`)

## Phase 4: User Story 2 - A pad recalls a scene (P1)

- [X] MIDI-007-T09 [US2] App test in `MIDISceneSelectionCoordinatorTests.swift`: note 60 / channel 1 mapped to scene Y selects Y on note on, nothing on note off, mappings byte-identical; a MIDI-006 trigger on another note still steps (S1) — Verified 2026-11-14: same app run; `testNoteSelectsTheSceneWithoutChangingStoredMappings`

## Phase 5: User Story 3 - Program number selects cue position (P2)

- [X] MIDI-007-T10 [US3] Coordinator `setProgramCueMode(_:)` (saved at once, no Undo entry) and app test in `MIDISceneSelectionCoordinatorTests.swift`: mode on channel 1 → PC 2 selects cue 3, channel 2 nothing, PC 9 announces "Cue 10 not found.", an explicit mapping wins (S3) — Verified 2026-11-14: same app run; `testProgramNumberSelectsCuePositionOnTheChosenChannel`

## Phase 6: User Story 4 - Assign MIDI to a scene (P2)

- [X] MIDI-007-T11 [US4] Learn in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Scenes.swift` (result texts, moves from scenes and MIDI-006 triggers) and the MIDI-006 side in `Apps/projectM-iOS/Coordinators/MIDIMappingCoordinator+Notes.swift` (a note learn frees a scene key); app tests: learning message selects nothing, moved note, Undo restores all lists, timeout, scene rows ("Program 5 · Ch 1", "Scene not found" for a scene no cue shows), announcements on the `.midi` lane only (research MIDI-007-D6; R8-R10) — Verified 2026-11-14: same app run; `testAssignAProgramTheLearningMessageSelectsNothingThenItTriggers`, `testAssignANoteMovesItFromATriggerAndUndoRestoresEveryList`, `testSceneLearnTimesOutAndDeleteUsesUndo`
- [X] MIDI-007-T12 [US4] Views: "Scene triggers" section and picker in `Apps/projectM-iOS/Views/MIDIMappingsView.swift`; `Apps/projectM-iOS/Views/MIDISceneAssignView.swift`; "Assign MIDI…" in `Apps/projectM-iOS/Views/ShowEditorView.swift`; one argument in `Apps/projectM-iOS/Views/SettingsView.swift`; DEBUG "Send Program" in `Apps/projectM-iOS/Debug/UITestFakeMIDI.swift` — Verified 2026-11-14: build-for-testing with the type-check flags (no warning in touched code; the one warning, SettingsView.swift:245 at 159 ms, is existing code under 200 ms); exercised by MIDISceneSelectionUITests
- [X] MIDI-007-T13 [US4] UI test `Apps/projectM-iOS/UITests/MIDISceneSelectionUITests.swift` (under 30 s): seeded show, plug Fake Keys, Settings → Show → cue 3 "Assign MIDI…", send program 5, read the result, send it again, cue 3 is active and its scene applied (S5) — Verified 2026-11-14: `xcodebuild test-without-building -only-testing:projectM-iOSUITests/MIDISceneSelectionUITests` on "MIDI7 iPhone 17": passed in 25.3 s (MIDINoteTriggersUITests and ShowCueUITests 2/2 also pass)

## Phase 7: Polish

- [X] MIDI-007-T14 Update the MIDI-006 fixture that used `cue.go:` as an unknown action in `Apps/projectM-iOS/Tests/MIDINoteTriggerCoordinatorTests.swift`; type-check budget on touched files; repository checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest, network symbols); PosterBoard count; delete the simulator and derived data (S6) — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 tests OK; check_privacy_manifest OK and check_network_symbols OK on the Debug app; PosterBoard 25 before and after; simulator and derived data deleted
- [ ] MIDI-007-T15 {device} With a physical controller on D1, assign a program to a scene; the patch change selects it and a repeat does nothing

## Dependencies

T01 → T02, T03 (parallel) → T04 → T05 → US1 (T06-T08) → US2 (T09) and US3 (T10) → US4 (T11-T13) → T14 → T15.

## Parallel examples

- T02 and T03 touch different files.
- T06 (package tests) can be written while T07 is built.

## Implementation strategy

MVP is US1 (the row's acceptance). US2-US4 extend the same code paths; the UI test closes US4.
