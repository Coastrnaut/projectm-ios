# Tasks: SHOW-004 Cue Transition Override

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/show-cue-transition-override.md](contracts/show-cue-transition-override.md), [quickstart.md](quickstart.md)

**Tests**: requested by the roadmap acceptance and the brief (round trip, lenient read, acceptance, one short UI test).
Budgets (owner rule 7): unit tests ~1-2 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] SHOW-004-T01 Create simulator "SHOW4 iPhone 17" (iOS 27.2), run `xcodegen generate` in the worktree, and count `~/Library/Logs/DiagnosticReports/PosterBoard-*.ips` before any simulator run — Verified 2026-11-14: simulator created, `xcodegen generate`, PosterBoard reports 26 before

## Phase 2: Foundational (model and file; blocks every story)

- [X] SHOW-004-T02 Add `transitionOverride: ShowCueTransition?` ("nil = use the scene default"), `effectiveTransition` (`transitionOverride ?? transition`), `setTransitionOverride(_:to:)` (never changes position, order or `transition`) and an `insert(…, transitionOverride:)` parameter in `Packages/ShowControl/Sources/ShowControl/ShowCueList.swift` — Verified 2026-11-14: ShowTransitionOverrideTests (4 tests) in `swift test --package-path Packages/ShowControl`, 114 tests, 0 failures
- [X] SHOW-004-T03 Store the optional per-cue `transitionOverride` object in `Packages/ShowControl/Sources/ShowControl/ShowDocument.swift` (written only when set; same fields as SCN-007 `transition`; lenient read via `StoredTransition`; warnings `droppedTransitionOverrides(Int)` and `unknownTransitionOverrideType(cue:type:)`; no version bump) per contract O1-O3 — Verified 2026-11-14: ShowTransitionOverrideTests round-trip, bytes and lenient-read tests

## Phase 3: User Story 1 — one cue enters differently (P1, MVP)

**Independent test**: two cues of one scene, 2 s crossfade default, Cut override on the first; a spy sees cut then crossfade; scene file and defaults unchanged.

- [X] SHOW-004-T04 [US1] Pass `cue.effectiveTransition` (direct apply and the SCN-012 repaired-open closure) and add `setTransitionOverride` (refused while locked via `refusedByLock`, saves, applies nothing) plus the Duplicate Scene carry-over in `Apps/projectM-iOS/Coordinators/ShowCoordinator.swift` — Verified 2026-11-14: CueTransitionOverrideAcceptanceTests (2 tests, 0.03 s) on "SHOW4 iPhone 17"; CueTransitionAcceptanceTests 3 and ShowAutoAdvanceCoordinatorTests 5 still pass
- [X] SHOW-004-T05 [US1] Acceptance test `Apps/projectM-iOS/Tests/CueTransitionOverrideAcceptanceTests.swift`: cut into A, 2 s crossfade into B, scene file bytes and both cues' `transition` equal before/after, "Use Scene Default" restores the crossfade, Reduce Motion still resolves the override to a cut and Reduce flashing turns a Cut override into the 0.5 s crossfade, lock refuses the edit, Duplicate copies the override (contract O4-O6) — Verified 2026-11-14: CueTransitionOverrideAcceptanceTests testTheCueOverrideWinsWithoutAlteringTheSceneDefault and testSafetyLockAndDuplicateApplyToTheOverride pass

## Phase 4: User Story 2 — the override survives the file (P1)

- [X] SHOW-004-T06 [P] [US2] Package tests `Packages/ShowControl/Tests/ShowControlTests/ShowTransitionOverrideTests.swift`: round trip byte-identical with bit-identical durations; a show without overrides has no `transitionOverride` key and the same bytes as before; lenient read of each invalid case (wrong JSON type, bad duration, bad easing, empty type) and an unknown type; edit rules (position, order, `transition` untouched) — Verified 2026-11-14: `swift test --package-path Packages/ShowControl` (114 tests, 1.2 s)

## Phase 5: User Story 3 — edit it in the show editor (P1)

- [X] SHOW-004-T07 [US3] Add a `target` (`.sceneDefault` / `.override`) to `Apps/projectM-iOS/Views/CueTransitionView.swift`: with `.override` the first type choice is "Use Scene Default", the title "Transition Into This Cue", the footer names the scene default, edits call `setTransitionOverride` — Verified 2026-11-14: CueTransitionOverrideUITests (26.9 s); CueTransitionUITests testACueTransitionPersistsAcrossARelaunch still passes
- [X] SHOW-004-T08 [US3] In `Apps/projectM-iOS/Views/ShowEditorView.swift`: context menu "Transition Into This Cue…", leading swipe "Into" (identifier `showCueTransitionOverride`), VoiceOver action "Transition Into This Cue", row line "Into this cue: <summary>" and VoiceOver ", into this cue <summary>"; hidden while locked (SCN-015-R6) — Verified 2026-11-14: CueTransitionOverrideUITests reads ", into this cue Cut" from the row value via the "Into" swipe action
- [X] SHOW-004-T09 [US3] UI test `Apps/projectM-iOS/UITests/CueTransitionOverrideUITests.swift` (< 30 s): set Cut on cue 2, the row value reads "into this cue Cut"; "Use Scene Default" removes it — Verified 2026-11-14: CueTransitionOverrideUITests testSettingAndClearingACueOverride passed (26.9 s)

## Phase 6: Polish

- [X] SHOW-004-T10 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`) shows no new warnings in touched files — Verified 2026-11-14: build-for-testing with -warn-long-function-bodies=300 / -warn-long-expression-type-checking=150: no warnings in touched files
- [X] SHOW-004-T11 Repo checks (compliance, docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the Debug app; spec status; PosterBoard count after; delete the simulator and derived data — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 174 OK; check_privacy_manifest and check_network_symbols OK on the Debug app; PosterBoard 26 before and after

## Dependencies

T01 → T02 → T03 → (T04 → T05), T06 [P after T03], (T07 → T08 → T09) after T04 → T10 → T11.
