# Tasks: PRE-010 Preset Quick Audition

**Input**: `specs/168-pre-010-quick-audition/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row's acceptance and the brief (acceptance, Keep, load failure, one
UI test under 30 s).

Format: `- [ ] PRE-010-Tnn [P?] [Story?] Description (file)`.

## Phase 1: Setup

- [X] PRE-010-T01 Create the simulator "PRE10 iPhone 17" (iOS 27.2), count PosterBoard reports, `xcodegen generate` in the worktree. — Verified 2026-11-14: simulator "PRE10 iPhone 17" (iOS 27.2) created, 25 PosterBoard reports before, `xcodegen generate` OK

## Phase 2: Foundational

- [X] PRE-010-T02 `PresetCoordinator`: stored `audition` and generation counter, `onScreen`, `didSelect(_:)` split out of `select` (no behavior change), `select` ends a preview after a successful load and guards the preset actually on screen, `setScope`/`planUpcoming`/session exclusion/loader reachable from the extension, ", previewing" in the row label (`Apps/projectM-iOS/Coordinators/PresetCoordinator.swift`). — Verified 2026-11-14: build-for-testing on PRE10 (no type-check warnings in touched files); PresetTests 19, FlashPolicyTests 18, RecentPresetsAcceptanceTests 7, PresetTagAcceptanceTests 10, PresetCollectionsCoordinatorTests 13, UserPresetsCoordinatorTests 4 still pass

## Phase 3: User Story 1 — peek and go back (P1) MVP

Independent test: select A in "Tagged: Calm", preview B and C, Cancel; A current, scope unchanged, stored values byte-identical, no history entry, no undo step, autosave unchanged.

- [X] PRE-010-T03 [US1] `PresetAudition`, `canPreview`, `preview(_:from:)`, `cancelAudition()`, texts and library-lane announcements (contract A1) in `Apps/projectM-iOS/Coordinators/PresetCoordinator+Audition.swift`. — Verified 2026-11-14: PresetAuditionAcceptanceTests 6/6 on PRE10
- [X] PRE-010-T04 [US1] `PresetAuditionBar` (name, Keep, Cancel with Escape, notice, OK) in `Apps/projectM-iOS/Views/PresetAuditionBar.swift`; the bar as a bottom inset and cancel on close in `Apps/projectM-iOS/Views/PresetBrowserView.swift`. — Verified 2026-11-14: PresetAuditionUITests (bar names each preview, Cancel removes it) on PRE10, 25.1 s
- [X] PRE-010-T05 [US1] Row "Preview" (menu first item, leading swipe, VoiceOver action) through `previewScope` in `Apps/projectM-iOS/Views/PresetBrowserView.swift`; list scopes passed by `PresetFolderView.swift`, `PresetTagChips.swift`, `PresetCollectionView.swift`, `RecentPresetsView.swift`, `UserPresetsView.swift` and the browser's favorites and search lists. — Verified 2026-11-14: PresetAuditionUITests (touch-and-hold Preview); PresetCollectionsUITests 9, PresetTagsUITests 2, RecentPresetsUITests 1 still pass on PRE10
- [X] PRE-010-T06 [US1] Acceptance test (S1) in `Apps/projectM-iOS/Tests/PresetAuditionAcceptanceTests.swift`: fake loader, PRE-006 history on with an injected clock, a `SceneHistoryCoordinator` over the same `AppSettings`, SCN-002 canonical bytes before and after; whole UserDefaults domain byte-identical; the library-lane announcements (R9). — Verified 2026-11-14: PresetAuditionAcceptanceTests testCancelRestoresTheOriginalPresetAndItsTaggedScopeAndStoresNothing

## Phase 4: User Story 2 — keep the one I like (P1)

- [X] PRE-010-T07 [US2] `keepAudition()` (scope, `didSelect`, no second load, announcement) in `PresetCoordinator+Audition.swift`; Keep closes the browser (`PresetAuditionBar.swift`). — Verified 2026-11-14: PresetAuditionAcceptanceTests testKeepCommitsLikeATapWithoutASecondLoad
- [X] PRE-010-T08 [US2] Tests: Keep from a collection equals a tap's stored state with one load; a committed selection during a preview ends it without a restore (`PresetAuditionAcceptanceTests.swift`). — Verified 2026-11-14: PresetAuditionAcceptanceTests testKeepCommitsLikeATapWithoutASecondLoad, testACommittedSelectionDuringAPreviewEndsItWithoutARestore

## Phase 5: User Story 3 — a failed preview changes nothing (P2)

- [X] PRE-010-T09 [US3] Tests: first preview fails (original stays, notice, nothing stored, excluded for the session); a later preview fails (previous preview stays, Cancel returns to the original); Preview not offered for locked, flagged (Reduce flashing on) and on-screen presets (`PresetAuditionAcceptanceTests.swift`). — Verified 2026-11-14: PresetAuditionAcceptanceTests testAFailedFirstPreview…, testAFailedLaterPreview…, testPreviewIsNotOfferedForLockedFlaggedOrOnScreenPresets

## Phase 6: Polish

- [X] PRE-010-T10 UI test under 30 s (S4): seed Calm tags, choose A from the chip list, preview two rows, Cancel, close; `currentPreset` is A and the scope line starts with "Tagged" (`Apps/projectM-iOS/UITests/PresetAuditionUITests.swift`). — Verified 2026-11-14: PresetAuditionUITests testPreviewTwoPresetsThenCancelRestoresTheOriginal passed on PRE10 (26.5 s, then 25.1 s)
- [X] PRE-010-T11 [P] `scripts/check_status_events.py` covers the new files; repo checks, type-check budget, privacy manifest and network symbol checks on the Debug app. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 159 OK; check_privacy_manifest and check_network_symbols OK on the Debug app
- [X] PRE-010-T12 Spec status, delete the simulator and derived data, PosterBoard count. — Verified 2026-11-14: spec status updated; simulator and derived data deleted; PosterBoard reports 25 before and after

## Dependencies

T01 → T02 → T03 → (T04, T05, T06) → T07 → T08 → T09 → T10 → T11 → T12. T11's script edit can run in parallel.
