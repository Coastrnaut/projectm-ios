# Tasks: FILE-004 Import Conflict Resolver

**Input**: Design documents from `specs/111-file-004-import-conflict-resolver/`

**Tests**: Requested by the roadmap row (schema and fixture tests plus the simulator). Budgets
(owner rule 7): unit tests about 1-2 s (at most 10 s), package suite under 1 minute, UI test under
30 s.

## Phase 1: Setup

- [X] FILE-004-T01 Add `LocalPortability` to the `ShowStorage` target in Packages/ShowControl/Package.swift (SHA-256 for derived IDs and the library digest); `swift build` on the host — Verified 2026-11-14: `swift build` and `swift test --package-path Packages/ShowControl` (42 tests) on the host; the app build resolves it

## Phase 2: Foundational (presets)

- [X] FILE-004-T02 Choice model and Replace planning in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/PresetArchiveImportPlan.swift: `.replace`, `overrides`, entry `choice`/`replaces`/`fellBack`, `PresetArchiveAction.replacesID`, `replaceCount`, `PresetArchiveText.installed(_:replaced:)` (contract C1, research D1, D6) — Verified 2026-11-14: PresetArchiveConflictTests (10) and the FILE-003 plan tests pass, `swift test --package-path Packages/PresetLibrary` (240, 2 skipped)
- [X] FILE-004-T03 `UserPresetStore.commitImport(adding:replacing:)` with `staging/replaced.json`, deletion of old texts after the index write, and the load-time cleanup in `removeLeftoverStaging()`; `addAll` delegates (research D3) in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetStore.swift — Verified 2026-11-14: PresetArchiveConflictTests fault loop and interrupted-replace test; FILE-003's PresetArchiveInstallTests unchanged and passing
- [X] FILE-004-T04 `UserPresetLibrary.planArchiveImport(_:policy:overrides:)`, `installArchive` with Replace and the held-target refusal, `runTrial` text guard (research D6, D7) in Packages/PresetLibrary/Sources/PresetLibrary/UserPresets/UserPresetLibrary.swift — Verified 2026-11-14: testAHeldReplaceTargetRefusesTheInstallWithNothingWritten, testMixedChoicesInstallExactlyThePlan (the trial guard D7 is code-reviewed only: no test drives a trial concurrently with an install)

## Phase 3: User Story 1 - Per-conflict choices for presets (P1)

**Independent Test**: mixed choices install exactly the plan.

- [X] FILE-004-T05 [US1] Package tests in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveConflictTests.swift: mixed choices in one archive (Replace by ID, Replace by name, Keep both, Skip, new) install exactly the plan; Replace keeps the identifier and a collection listing it still resolves; Skip leaves the existing record and text byte-identical; fallbacks (two incoming with one name; ID match plus name taken by another preset); replacing a quarantined preset; held target refused — Verified 2026-11-14: PresetArchiveConflictTests: mixed choices, Replace by name, fallbacks, quarantined target, held target (all pass, 0.67 s for the suite)
- [X] FILE-004-T06 [US1] Coordinator: `setArchiveChoice(_:for:)`, `setArchivePolicy` clears overrides, words for Replace/fallback/Skip outcome, install announcement with the replaced count on the `library` lane, DEBUG conflict fixture, in Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift and one line in Apps/projectM-iOS/Coordinators/AppCoordinator.swift — Verified 2026-11-14: PresetArchiveConflictAppTests 4/4 on the FILE4 iOS 27.2 simulator (library-lane announcement asserted)
- [X] FILE-004-T07 [US1] Preview UI: Apps/projectM-iOS/Views/PresetArchiveChoiceRow.swift (new) and Apps/projectM-iOS/Views/PresetArchiveImportView.swift (conflict rows use it; three-option "Apply to all"); small bodies, accessibility sizes, no animation — Verified 2026-11-14: PresetArchiveConflictUITests at accessibility XXXL (row choices reachable and selected, screenshot attached); check_motion_policy OK; no compiler warnings in touched files
- [X] FILE-004-T08 [US1] App tests in Apps/projectM-iOS/Tests/PresetArchiveConflictAppTests.swift: a per-row choice re-plans, "Apply to all" clears overrides, install with Replace announces on the `library` lane, words — Verified 2026-11-14: PresetArchiveConflictAppTests 4/4 on the FILE4 iOS 27.2 simulator
- [X] FILE-004-T09 [US1] UI test Apps/projectM-iOS/UITests/PresetArchiveConflictUITests.swift at the largest accessibility size: conflict row Keep both → Skip → Replace, install count and outcome follow, Cancel, same digest; under 30 s — Verified 2026-11-14: PresetArchiveConflictUITests.testARowChoiceChangesThePlanAndCancelChangesNothing passes in 20.2 s (Install 2 → 1 → 2, row says “Replaces …”, same digest after Cancel)

## Phase 4: User Story 2 - No partial overwrite (P1)

- [X] FILE-004-T10 [US2] Fault loop: a mixed install (Replace, Keep both, new, Skip) failing at every store file operation; before the commit the snapshot equals the one before; after the commit the outcome is installed and a reload gives the clean-success snapshot; crash simulation (staging left with `replaced.json` before and after the index write) recovered at load, in Packages/PresetLibrary/Tests/PresetLibraryTests/PresetArchiveConflictTests.swift — Verified 2026-11-14: testAMixedInstallFailingAtEveryFileOperationIsAllOrNothing (every pre-commit fault: snapshot identical and memory unchanged; post-commit faults: reload gives the clean snapshot) and testAnInterruptedReplaceIsSettledByTheIndexAtLoad

## Phase 5: User Story 3 - Deterministic IDs (P1)

- [X] FILE-004-T11 [US3] ID table: equal inputs give equal plans in two runs; fixed expected derived IDs (literal hex, so a second process gives the same); different content gives different IDs, for presets in PresetArchiveConflictTests.swift and for scenes and cues in ShowSceneImportTests.swift — Verified 2026-11-14: testDerivedIdentifiersAreFixedValues (presets) and testDerivedIDsAreFixedValues (scenes: literal UUID 440A1BDB-628F-807C-A1B0-1875044D5EEB)

## Phase 6: User Story 4 - Scene conflicts (P2, no screen)

- [X] FILE-004-T12 [US4] Packages/ShowControl/Sources/ShowStorage/ShowSceneImport.swift: types, pure planner, `planSceneImport`, journalled `installImportedScenes`, `recoverInterruptedSceneImport` (contract C3, research D4) — Verified 2026-11-14: ShowSceneImportTests 11/11 on the host (0.54 s)
- [X] FILE-004-T13 [US4] Packages/ShowControl/Tests/ShowControlTests/ShowSceneImportTests.swift: plan kinds (new, identical, conflict with cue count); Rename rewrites the scene id and adds a cue with the derived ID; Replace keeps cues; Skip byte-identical; mixed choices; fault at every file operation leaves the show folder snapshot identical; simulated crash at every operation recovered to before (pre-commit) or to the success state (post-commit); unreadable show refused — Verified 2026-11-14: ShowSceneImportTests: kinds, Keep both rewrite plus derived cue, Replace keeps cues, Skip byte-identical, mixed, fallback, fault at every operation, simulated crash at every operation recovered, unreadable show

## Phase 7: User Story 5 - Re-validation (P2)

- [X] FILE-004-T14 [US5] Presets: a replace target removed between plan and install gives `.changed` with nothing written; scenes: a stored scene changed meanwhile gives `.changed` with nothing written (in the two test files above) — Verified 2026-11-14: testARemovedReplaceTargetIsDetectedWithNothingWritten and testAChangedStoredSceneIsDetectedWithNothingWritten

## Phase 8: Polish

- [X] FILE-004-T15 Run the checks (compliance, docs, motion policy, permission catalog, status events, script tests, privacy manifest on the Debug app), PresetLibrary and ShowControl on the host, the app tests and UI tests in quickstart.md on the own simulator (PosterBoard count before and after); record results in spec.md's status — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK (1 skipped); check_privacy_manifest OK on the Debug app; PresetLibrary 240 and ShowControl 42 tests on the macOS host; projectM-iOSTests 502 plus PresetArchiveImportUITests and PresetArchiveConflictUITests on the FILE4 iOS 27.2 simulator (deleted afterwards); PosterBoard reports 25 before and after. Linux container not available on this Mac (CI's Linux job covers both packages)

## Dependencies

T01 → T12-T13. T02 → T03 → T04 → T05, T10, T11, T14 → T06 → T07 → T08, T09. T15 last.

## Parallel examples

- T12/T13 (ShowControl) alongside T02-T05 (PresetLibrary): different packages.

## Implementation strategy

MVP: T02-T05 and T10 (preset choices with the atomic Replace). Then scenes (T01, T12, T13), the ID
table and re-validation, the app and UI, the checks.
