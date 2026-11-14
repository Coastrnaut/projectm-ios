# Tasks: PRE-003 Preset Tags

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/preset-tags.md](contracts/preset-tags.md), [research.md](research.md)

Tests are requested by the roadmap row (acceptance after relaunch) and the brief. Budgets (owner
rule 7): unit tests about 1-2 s, package suites under 1 minute, UI tests under 30 s.

## Phase 1: Setup

- [X] PRE-003-T01 Create the feature's own simulator "PRE3 iPhone 17" (iOS 27.2), `xcodegen generate`, keep the `Build` link, initialize the preset submodules if missing, and count PosterBoard reports before any run. — Verified 2026-11-14: simulator PRE3 (FB4543E9) created on iOS 27.2, `xcodegen generate`, `Build` link present, preset submodules initialized, PosterBoard reports 25 before.

## Phase 2: Foundational (model, file, store, index; blocks every story)

- [X] PRE-003-T02 Implement `PresetTagMap` and `PresetTagError` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTags.swift`: tag "trimmed, 1-40 characters, one line"; "1-16 tags" per preset; "≤ 256 distinct folded tags"; "≤ 20,000 entries"; fold (case, accents, width, `nil` locale); existing spelling adopted; sorted by (fold, text); `add`, `remove`, `prune`, `repaired` (research PRE-003-D2; contract C1). — Verified 2026-11-14: PresetTagMapTests 6/6 (`swift test --package-path Packages/PresetLibrary --filter PresetTag`).
- [X] PRE-003-T03 Implement `PresetTagsFile` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagsFile.swift`: version 1, bounds "4 MiB, depth 4, strings ≤ 4 KiB, ≤ 20,000 elements per list or object, no duplicate keys", newer version refused, lenient per-entry repair with a drop count, stable encoding (research D4; contract C2). — Verified 2026-11-14: PresetTagStoreTests (round trip byte-exact, damaged entries counted, duplicate keys unreadable, newer format untouched).
- [X] PRE-003-T04 Implement `PresetTagStore` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagStore.swift` (save before show, failed save changes nothing, newer format read-only, unreadable set aside, `repaired(dropped)` notice) (research D1). — Verified 2026-11-14: PresetTagStoreTests 5/5.
- [X] PRE-003-T05 Implement `PresetTagIndex` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagIndex.swift` (listed IDs only, vocabulary, counts, AND `matching(all:)` from the smallest set with `visitedCount`, `presetIDs(tagContaining:)`) and `PresetScope.tagged`, `taggedListing`, `members(…tags:)`, `title`, `search(…tagMatches:)` in `PresetScope.swift` and `PresetLibrary.swift` (research D3, D5; contract C3). — Verified 2026-11-14: PresetTagAcceptanceTests (matching, vocabulary, tagged listing and scope, search tag matches).
- [X] PRE-003-T06 [P] Package tests `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetTagMapTests.swift` and `PresetTagStoreTests.swift`: folding and dedup, adopted spelling, limits 40/16/256/20,000, remove and prune; file round trip and determinism; damaged entries dropped and counted; unreadable file set aside; newer format untouched and refused; failed save changes nothing. — Verified 2026-11-14: PresetTagMapTests 6 + PresetTagStoreTests 5 pass in 0.12 s; PresetLibrary 275 tests (3 skipped) pass in 38.7 s.

## Phase 3: User Story 1 — tag presets and filter, after relaunch (P1, MVP)

**Independent test**: tag presets, filter by tags (expected ID set), recreate the store from disk, filter again: same IDs.

- [X] PRE-003-T07 [US1] Package acceptance test `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetTagAcceptanceTests.swift`: tag several presets of a fixture library, filter by one and two tags (expected IDs), recreate the store and index from disk, same IDs; search matches tags; tagged scope members; hidden orphans; bundled index and pack bytes hashed before and after unchanged; operation count of `matching` bounded by the smallest set on a 12,847-preset synthetic library; bench behind `PRE003_BENCH=1`. — Verified 2026-11-14: PresetTagAcceptanceTests 4 pass (+ bench skipped) in 0.22 s: same ID sets after the store is recreated from disk; bundled index/packs hashes unchanged; `matching` visited ≤ 12 IDs on 13,000 presets. Bench (PRE003_BENCH=1, Debug): index 87 ms with every preset tagged twice, filter 0 ms.
- [X] PRE-003-T08 [US1] App tag state in `Apps/projectM-iOS/Coordinators/PresetCoordinator.swift` and `Apps/projectM-iOS/Coordinators/PresetCoordinator+Tags.swift`: store, cached index, `selectedTags`, `toggleTag`, `clearTags`, `taggedListing`, `addTag`, `removeTag`, `pruneTags`, announcements (library lane edits, search lane chip counts), row label ", tags …", the tagged scope in `members` and `displayCount`; the store's one-time notice (unreadable set aside, entries repaired) shown as `tagsNotice` and the newer-format message (contract C4; spec PRE-003-R6). — Verified 2026-11-14: PresetTagAcceptanceTests (app) 4/4 on PRE3 in 1.6 s: chips AND to the expected IDs, recreated coordinator gives the same IDs, tagged scope line "Tagged: Ambient · 2" and Next, announcements on both lanes, row label ", tags Calm, slow".
- [X] PRE-003-T09 [US1] Views: `Apps/projectM-iOS/Views/PresetTagChips.swift` (chip row with Clear; tagged list with empty text) and `Apps/projectM-iOS/Views/PresetBrowserView.swift` (chips in home, favorites, search; tag-filtered search; row caption line). Register the new views in `scripts/check_status_events.py`. — Verified 2026-11-14: built (type-check budget: PresetRow.body split after measuring 468 ms; no touched function over 300 ms afterwards); exercised by PresetTagsUITests; `check_status_events.py` OK with the two views and PresetCoordinator+Tags registered.
- [X] PRE-003-T10 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (store creation, announcer) and the DEBUG seed `-uitestSeedPresetTags "<tag>:<i>,<j>|…"` in `Apps/projectM-iOS/Debug/UITestPresetTagFixture.swift` (fresh launches only). — Verified 2026-11-14: PresetTagsUITests uses `-uitestSeedPresetTags` (seeded through the real store) and passes.
- [X] PRE-003-T11 [US1] App acceptance tests `Apps/projectM-iOS/Tests/PresetTagAcceptanceTests.swift`: coordinator tags, chips (AND), recreate the coordinator from the same store directory, same IDs; tagged scope walk; announcements; the PresetLibrary and ShowControl folds agree. — Verified 2026-11-14: PresetTagAcceptanceTests 4/4 (incl. bundled PresetIndex.json/PresetPacks.json hashes unchanged, preset and scene folds agree); projectM-iOSTests 699/699 in 36.5 s.
- [X] PRE-003-T12 [US1] UI test `Apps/projectM-iOS/UITests/PresetTagsUITests.swift` (under 30 s): seeded tags, select chip(s), the listed rows equal the expected names; relaunch without reset; same chips give the same rows. — Verified 2026-11-14: testTagFilterGivesTheSameRowsAfterRelaunch passed 3 times on PRE3 (28.2 s, 17.9 s after a 55.6 s cold first run on a freshly booted simulator): same rows for "Calm" and "Calm"+"Slow" after terminate and relaunch.

## Phase 4: User Story 2 — tag a preset from its row (P1)

- [X] PRE-003-T13 [US2] `Apps/projectM-iOS/Views/PresetTagsView.swift` (Tags sheet: tags with Remove button and VoiceOver action, field with Add and Return, suggestions narrowed by the field, refusal message) and the "Tags…" context menu item and VoiceOver action "Tags" on `PresetRow`. — Verified 2026-11-14: exercised by testTaggingThroughTheSheetAddsAChip (context menu Tags…, field + Return, Done).
- [X] PRE-003-T14 [US2] UI test in `PresetTagsUITests`: add "Calm" through the row's Tags… sheet, the chip appears, selecting it lists only that preset (under 30 s). — Verified 2026-11-14: testTaggingThroughTheSheetAddsAChip passed (16.7 s, 27.0 s): the row label ends ", tags Calm, Slow" and the Slow chip lists only that preset.
- [X] PRE-003-T15 [US2] Prune on user preset removal in `Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift`, covered by a unit test in `PresetTagAcceptanceTests`. — Verified 2026-11-14: UserPresetsCoordinatorTests.testRemovingAPresetKeepsWhatIsPlaying now asserts the removed preset's tags are pruned (19/19 pass).

## Phase 5: User Story 3 — backup, restore, erase (P2)

- [X] PRE-003-T16 [US3] LibraryBackup: `LibraryFolders.tagsFile`, `LibraryContents.presetTags`, reader, writer and backup reader (`collections/tags.json`), `LibraryRecords` key `preset-tags`, restore section `tags` with per-preset merge and copy-ID remap, installer write, preview line "Tags", erase category title "Collections, tags and favorites" (`Packages/LibraryBackup/Sources/LibraryBackup/*.swift`, `Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift`) (research D6). — Verified 2026-11-14: `swift test --package-path Packages/LibraryBackup` 72/72 in 8.9 s (existing erase acceptance updated to map `preset-tags` to the collections category); the app's restore preview gains a "Preset tags" line (built with the app).
- [X] PRE-003-T17 [P] [US3] Tests `Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetTagTests.swift`: backup round trip onto an empty library; merge by choice (union capped at 16, replace, skip); erase of the collections category leaves no tags file. — Verified 2026-11-14: LibraryBackupPresetTagTests 4/4: round trip (same map and record digest), merge by choice (Keep both union, Replace, Skip), union capped at 16 with fellBack, erase removes tags.json and the inventory counts tagged presets.

## Phase 6: Polish

- [X] PRE-003-T18 Repo checks (compliance, docs, motion, permissions, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, no new UserDefaults keys, Linux-shaped build of PresetLibrary (no Apple-only API), PosterBoard count after; update spec status; delete the simulator and derived data. — Verified 2026-11-14: check_compliance, validate_docs, check_motion_policy, check_permission_catalog, check_status_events OK; test_scripts 153 OK (1 skipped); check_privacy_manifest and check_network_symbols OK on the Debug simulator app; no new UserDefaults keys (diff grep); PresetLibraryUITests 5/5 still pass; PosterBoard reports 25 before and 25 after; PRE3 simulator and derived data deleted. Linux: PresetLibrary and LibraryBackup use Foundation only (no Apple-only API added) but were not built on Linux here; CI's Linux job builds and tests both.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → (T09, T10) → T11 → T12 → T13 → T14 → T15; T16 after T03 (parallel with T08-T15) → T17 → T18.

## Parallel opportunities

T06 and T07 (different test files); T16-T17 (LibraryBackup) alongside the app tasks T08-T15.

## Implementation strategy

MVP = Phases 1-3 (tag, filter, persist across relaunch). US2 adds the editing sheet; US3 the backup
integration.

## Analysis (speckit-analyze, 2026-11-14)

No CRITICAL or HIGH findings; 15/15 requirements and 5/5 success criteria map to tasks. Applied: the
store's one-time notice (PRE-003-R6) was not surfaced by any app task (added to PRE-003-T08); the
edge-case messages "Your tags could not be saved." and the newer-format text were not in the contract
(added to C1).
