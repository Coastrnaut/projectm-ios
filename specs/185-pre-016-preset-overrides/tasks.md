# Tasks: PRE-016 Preset parameter overrides

**Input**: `specs/185-pre-016-preset-overrides/` (spec, plan, research, data-model, contracts, quickstart)
**Tests**: requested by the roadmap brief (acceptance, allow-list, clamping, backup round trip, UI test).
Budgets (owner rule 7): unit ≤ 10 s, package suite < 1 min, UI test < 30 s.

## Phase 1: Setup

- [X] PRE-016-T01 Create simulator "PRE16 iPhone 17" (iOS 27.2), `xcodegen generate`, count PosterBoard reports (baseline) — Verified 2026-11-14: `xcrun simctl create` gave 9E4D0EB4-B279-49DB-9A0D-A55F72F14167; PosterBoard baseline 25

## Phase 2: Foundational (PresetLibrary package)

- [X] PRE-016-T02 [P] `PresetOverrideParameter` allow-list (keys, labels, ranges "zoom 0.8-1.2, rot -0.2-0.2, warp 0-2, fDecay 0.9-1.0, wave_r/g/b 0-1, fGammaAdj 1-3", steps, engine defaults), case-insensitive lookup, `clamped` (clamp then round to 4 decimals; non-finite → nil) in `Packages/PresetLibrary/Sources/PresetLibrary/Overrides/PresetOverrideParameter.swift` — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter 'PresetOverride|PresetTextOverlay'`, 14 tests pass in 0.02 s
- [X] PRE-016-T03 [P] `PresetOverrideMap` + `PresetOverrideError` (unknown parameter, invalid value, invalid preset ID, too many presets 20,000, newer format, save failed) in `Packages/PresetLibrary/Sources/PresetLibrary/Overrides/PresetOverrideMap.swift` — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter 'PresetOverride|PresetTextOverlay'`, 14 tests pass in 0.02 s
- [X] PRE-016-T04 `PresetTextOverlay` (`originalValues`, `apply`, `valueText`; research D2-D3) in `Packages/PresetLibrary/Sources/PresetLibrary/Overrides/PresetTextOverlay.swift` — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter 'PresetOverride|PresetTextOverlay'`, 14 tests pass in 0.02 s
- [X] PRE-016-T05 `PresetOverridesFile` (version 1, FILE-007 schema, 1 MiB, lenient) and `PresetOverrideStore` (transactions, newer/unreadable) in `Packages/PresetLibrary/Sources/PresetLibrary/Overrides/` — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter 'PresetOverride|PresetTextOverlay'`, 14 tests pass in 0.02 s
- [X] PRE-016-T06 Unit tests: allow-list rejection, clamping, rounding, overlay (rewrite first occurrence, case, insert after header, CRLF, Latin-1 bytes kept, no overrides → identical; R17: `PresetFlashRisk.rules` of a flagged fixture unchanged by an overlay), original values, document round trip / newer / unreadable / repaired, store relaunch in `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetOverride*Tests.swift` — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary --filter 'PresetOverride|PresetTextOverlay'`, 14 tests pass in 0.02 s

## Phase 3: User Story 1 — Adjust a preset's look (P1) 🎯 MVP

**Independent test**: overrides for 2-3 parameters of a fixture preset → loaded data carries them, source byte-identical, survives a new store.

- [X] PRE-016-T07 [US1] Loader hook: `RendererPresetLoader.overrides` and overlay of the original bytes in `load`; `originalData(for:)` in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` — Verified 2026-11-14: `PresetOverridesAcceptanceTests` (2 tests, 0.2 s) pass on simulator PRE16 iPhone 17 (iOS 27.2): loaded data carries 3 overrides, Included file byte-identical, relaunch applies them, Reset loads the original file (no data) and reads the original values
- [X] PRE-016-T08 [US1] `PresetOverridesCoordinator` (store, originals, set on drag end, reload on screen, library-lane announcements) in `Apps/projectM-iOS/Coordinators/PresetOverridesCoordinator.swift`; `overrides` property on `PresetCoordinator`; construction in `AppCoordinator` (R11: the store lives in `PresetCollections/`, which `-uitestResetNotice` already removes; verified by the UI test starting with Original values) — Verified 2026-11-14: `PresetOverridesAcceptanceTests` (2 tests, 0.2 s) pass on simulator PRE16 iPhone 17 (iOS 27.2): loaded data carries 3 overrides, Included file byte-identical, relaunch applies them, Reset loads the original file (no data) and reads the original values
- [X] PRE-016-T09 [US1] `PresetOverridesView` sheet (sliders with `.accessibleParameter`, value + original labels, per-row reset, Reset to Original, note) in `Apps/projectM-iOS/Views/PresetOverridesView.swift`; menu item "Adjust Parameters…" + sheet in `Apps/projectM-iOS/Views/PresetBrowserView.swift` — Verified 2026-11-14: `PresetOverridesUITests.testAdjustZoomThenResetReturnsTheOriginalValue` passes in 22.5 s (simulator, not device evidence)
- [X] PRE-016-T10 [US1] Acceptance test (overlay applied on load, Included file byte-identical, relaunch) in `Apps/projectM-iOS/Tests/PresetOverridesAcceptanceTests.swift` — Verified 2026-11-14: `PresetOverridesAcceptanceTests` (2 tests, 0.2 s) pass on simulator PRE16 iPhone 17 (iOS 27.2): loaded data carries 3 overrides, Included file byte-identical, relaunch applies them, Reset loads the original file (no data) and reads the original values

## Phase 4: User Story 2 — Reset to original (P1)

- [X] PRE-016-T11 [US2] Reset in coordinator and store; acceptance: after reset the loaded bytes equal the original exactly, in `Apps/projectM-iOS/Tests/PresetOverridesAcceptanceTests.swift` — Verified 2026-11-14: `PresetOverridesAcceptanceTests` (2 tests, 0.2 s) pass on simulator PRE16 iPhone 17 (iOS 27.2): loaded data carries 3 overrides, Included file byte-identical, relaunch applies them, Reset loads the original file (no data) and reads the original values
- [X] PRE-016-T12 [US2] Prune overrides when a user preset is removed in `Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift` — Verified 2026-11-14: build plus `UserPresetsCoordinatorTests` (27) pass; prune path covered by `testRefusalsAndRowResetsChangeOnlyWhatTheySay`
- [X] PRE-016-T13 [US2] UI test < 30 s: adjust Zoom, reset, label returns to the original, in `Apps/projectM-iOS/UITests/PresetOverridesUITests.swift` — Verified 2026-11-14: `PresetOverridesUITests.testAdjustZoomThenResetReturnsTheOriginalValue` passes in 22.5 s (simulator, not device evidence)

## Phase 5: User Story 3 — Overrides travel with the library (P2)

- [X] PRE-016-T14 [US3] FILE-005: folders, format path, contents read, archive write/read, records, restore plan (section `overrides`), installer staging in `Packages/LibraryBackup/Sources/LibraryBackup/` — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup`, 77 tests pass (3 new) in 13.6 s
- [X] PRE-016-T15 [US3] FILE-011: Collections inventory counts presets with overrides in `Packages/LibraryBackup/Sources/LibraryBackup/LibraryEraseInventory.swift`; restore section label in `Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift` — Verified 2026-11-14: `LibraryBackupPresetOverrideTests.testEraseOfCollectionsRemovesOverrides`; app builds with the section label; LibraryBackupAppTests/LibraryEraseAppTests pass
- [X] PRE-016-T16 [US3] Tests: backup round trip, restore choices, erase count in `Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetOverrideTests.swift` — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup`, 77 tests pass (3 new) in 13.6 s

## Phase 6: Polish

- [X] PRE-016-T17 Type-check budget build (`-warn-long-function-bodies=300 -warn-long-expression-type-checking=150`), no new warnings — Verified 2026-11-14: build-for-testing with -warn-long-function-bodies=300 -warn-long-expression-type-checking=150 shows no warning in any touched file
- [X] PRE-016-T18 Repo checks (compliance, validate_docs, motion policy, permission catalog, status events, script tests), privacy manifest and network symbols on the built Debug app — Verified 2026-11-14: compliance, validate_docs, motion policy, permission catalog, status events OK; test_scripts 159 OK; check_privacy_manifest OK; check_network_symbols OK (19 images)
- [ ] PRE-016-T19 Delete simulator and derived data, PosterBoard count after

## Dependencies

T02-T05 → T06; T04-T05 → T07-T10 → T11-T13; T05 → T14-T16 (parallel with US1/US2). T17-T19 last.

## Parallel examples

T02 and T03 (different files); T14-T16 alongside T07-T09 (different packages).

## Implementation strategy

MVP = Phases 2-3 (overlay + store + loader hook + sheet). Then reset and UI test, then backup.
