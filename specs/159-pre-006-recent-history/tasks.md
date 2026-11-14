# Tasks: PRE-006 Recently Played History

**Input**: `specs/159-pre-006-recent-history/` (spec, plan, research, data-model, contracts, quickstart)

**Tests**: requested by the roadmap row's acceptance and the brief (acceptance, opt-out, dedup and cap,
dwell, relaunch, backup and erase policy, one UI test under 30 s).

Format: `- [ ] PRE-006-Tnn [P?] [Story?] Description (file)`.

## Phase 1: Setup

- [X] PRE-006-T01 Create the simulator "PRE6 iPhone 17" (iOS 27.2), count PosterBoard reports, `xcodegen generate` in the worktree. — Verified 2026-11-14: simulator "PRE6 iPhone 17" (iOS 27.2) created, 25 PosterBoard reports before, `xcodegen generate` OK

## Phase 2: Foundational (pure rules and policy)

- [X] PRE-006-T02 [P] `RecentPresetHistory` (capacity 50, "most recent first; no empty or duplicate IDs; at most 50", `record`, `clear`, lenient `init(storedValue:)`) and `RecentPresetDwell` (threshold 3.0 s, `shown`, `deadline`, `due(at:)`, `cancel`) in `Packages/PresetLibrary/Sources/PresetLibrary/RecentPresetHistory.swift`, with tests (dedup, cap at 51, lenient read, dwell under and at 3 s, replacement, cancel) in `Packages/PresetLibrary/Tests/PresetLibraryTests/RecentPresetHistoryTests.swift`. — Verified 2026-11-14: `swift test --package-path Packages/PresetLibrary` 286 tests (6 new RecentPresetHistoryTests), 0 failures, 30 s
- [X] PRE-006-T03 [P] FILE-005/FILE-011 policy: `LibrarySettingsPolicy.recentPresetsKey` (`recentPresets`, excluded) and `recentPresetsEnabledKey` (`settings.recentPresets.enabled`, included); `LibraryErasePolicy.settingKeys(.collections)` adds the history key; category title "Collections, tags, favorites and history"; `LibraryEraseInventory` counts history entries; tests updated (`Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift`, `LibraryErasePolicy.swift`, `LibraryEraseInventory.swift`, `Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryEraseAcceptanceTests.swift`, `LibraryBackupPresetTagTests.swift`). — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` 73 tests (1 new), 0 failures, 47 s

## Phase 3: User Story 1 — find the presets I just watched (P1) MVP

Independent test: presets shown ≥ 3 s are listed newest first, shorter ones are not, and the list survives a relaunch.

- [X] PRE-006-T04 [US1] `RecentPresetsStore` (UserDefaults keys, absent switch = on, off at launch removes history) in `Apps/projectM-iOS/Coordinators/RecentPresetsStore.swift`. — Verified 2026-11-14: RecentPresetsAcceptanceTests (off switch at launch, relaunch) on PRE6
- [X] PRE-006-T05 [US1] `RecentPresetsCoordinator` (contract C1: injected clock and scheduler, `shown`, `checkDwell`, `setEnabled`, `clear`, `listing(in:)`, library-lane announcements) in `Apps/projectM-iOS/Coordinators/RecentPresetsCoordinator.swift`; `PresetCoordinator.recent` and the one-line hook after a successful load in `Apps/projectM-iOS/Coordinators/PresetCoordinator.swift`. — Verified 2026-11-14: RecentPresetsAcceptanceTests 6/6 on PRE6 (dwell through PresetCoordinator.select, fake clock and scheduler)
- [X] PRE-006-T06 [US1] `AppCoordinator`: create and attach the coordinator, wire the announcer, `-uitestResetNotice` removes both keys (`Apps/projectM-iOS/Coordinators/AppCoordinator.swift`). — Verified 2026-11-14: Debug build on PRE6; RecentPresetsUITests (reset flag, announcer wiring)
- [X] PRE-006-T07 [US1] `RecentPresetsView` (list newest first, standard rows, empty states, `recentList`, `recentEmpty`) in `Apps/projectM-iOS/Views/RecentPresetsView.swift`; home row `node:recent` "Recently Played, N presets" and its route in `Apps/projectM-iOS/Views/PresetBrowserView.swift`. — Verified 2026-11-14: RecentPresetsUITests (node:recent label, rows newest first) on PRE6
- [X] PRE-006-T08 [US1] App tests: dwell through `PresetCoordinator.select` with a fake loader and injected clock (≥ 3 s recorded, < 3 s not, failed load not), dedup through the coordinator, relaunch (new store over the same defaults) in `Apps/projectM-iOS/Tests/RecentPresetsAcceptanceTests.swift`. — Verified 2026-11-14: RecentPresetsAcceptanceTests testOnlyPresetsShownForThreeSecondsAreRecordedNewestFirstAndOnce, testAPresetThatLeftTheLibraryIsNotListed

## Phase 4: User Story 2 — clear without losing favorites (P1)

Independent test: seed favorites, last preset, tags and history; clear; only history changes.

- [X] PRE-006-T09 [US2] Clear History with a destructive confirmation (`recentClear`; the alert button found by its label) in `RecentPresetsView.swift`, and the Settings section `RecentHistorySection` (switch `recentToggle`, Clear History) in `Apps/projectM-iOS/Views/RecentHistorySection.swift`; one property and one line in `SettingsView.tailSections`; pass the coordinator from `VisualizerView`. — Verified 2026-11-14: RecentPresetsUITests (Clear History with confirmation from the list); Settings section built (type-check budget clean for the new files)
- [X] PRE-006-T10 [US2] Acceptance test: seeded `favorites`, `lastPresetID`, a `tags.json` file (real `PresetTagStore`) and history; `clear()`; history empty, the two keys byte-identical (property-list data), the tags file's bytes unchanged, announcement spoken (`RecentPresetsAcceptanceTests.swift`). — Verified 2026-11-14: RecentPresetsAcceptanceTests testClearDeletesHistoryAndDoesNotAlterFavoritesLastPresetOrTags

## Phase 5: User Story 3 — turn history off (P2)

- [X] PRE-006-T11 [US3] Tests: off clears and stops recording (a pending candidate is not recorded later), on starts empty, an off switch at launch removes stored history (`RecentPresetsAcceptanceTests.swift`). — Verified 2026-11-14: RecentPresetsAcceptanceTests testTurningOffClearsAndStopsRecordingAndOnStartsEmpty, testAnOffSwitchFoundAtLaunchRemovesStoredHistory; opt-in default (integrator decision): testByDefaultHistoryIsOffAndNothingIsRecorded, rerun 7/7

## Phase 6: Polish and cross-cutting

- [X] PRE-006-T12 App key lists: `LibraryBackupAppTests` and `LibraryEraseAppTests` app-key sets include both keys; a test that the history is never in a backup's settings and is erased with the collections category (`Apps/projectM-iOS/Tests/`). — Verified 2026-11-14: LibraryBackupAppTests, LibraryEraseAppTests (erase message with the new title), RecentPresetsAcceptanceTests testTheKeysAgreeWithTheBackupAndErasePolicy
- [X] PRE-006-T13 [P] `ALLOWED_KEYS` gains both keys (`scripts/run_device_tests.py`); `check_status_events.py` registers the new files. — Verified 2026-11-14: `python3 scripts/test_scripts.py` 153 OK (stored-keys scan), `check_status_events.py` OK
- [X] PRE-006-T14 [P] ADR (next free number) amending FR-065/FR-123; privacy policy "What is stored on your device" and the FR-063 coverage row (`docs/adr/`, `docs/privacy-policy.md`). — Verified 2026-11-14: `validate_docs.py` OK; ADR-0055, privacy policy section and FR-063 row
- [X] PRE-006-T15 UI test: two presets shown 3 s each appear in Recently Played; star one; Clear; Recent empty; Favorites lists the starred preset; under 30 s (`Apps/projectM-iOS/UITests/RecentPresetsUITests.swift`). — Verified 2026-11-14: RecentPresetsUITests 1/1 on PRE6, 24.3 s (27.2 s on the first run); rerun with the opt-in switch on through launch arguments: 21.4 s
- [X] PRE-006-T16 Verification: package tests (PresetLibrary, LibraryBackup), app unit tests touched, the UI test, type-check budget, repo checks, privacy manifest and network symbols on the Debug app; spec status; delete derived data and the simulator; PosterBoard counts. — Verified 2026-11-14: package suites, 47 app unit tests, RecentPresetsUITests + PresetLibraryUITests (6/6), repo checks, check_privacy_manifest and check_network_symbols OK on the Debug app

## Dependencies

T01 → T02, T03 (parallel) → T04 → T05 → T06, T07 → T08; T09–T11 after T05; T12 after T03, T04; T15 after
T06, T07, T09; T16 last.

## Implementation strategy

MVP = Phase 3 (recording and the list). Then Clear (US2, the roadmap acceptance), opt-out (US3), polish.
