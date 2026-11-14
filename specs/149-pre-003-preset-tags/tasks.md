# Tasks: PRE-003 Preset Tags

**Input**: [plan.md](plan.md), [spec.md](spec.md), [data-model.md](data-model.md),
[contracts/preset-tags.md](contracts/preset-tags.md), [research.md](research.md)

Tests are requested by the roadmap row (acceptance after relaunch) and the brief. Budgets (owner
rule 7): unit tests about 1-2 s, package suites under 1 minute, UI tests under 30 s.

## Phase 1: Setup

- [ ] PRE-003-T01 Create the feature's own simulator "PRE3 iPhone 17" (iOS 27.2), `xcodegen generate`, keep the `Build` link, initialize the preset submodules if missing, and count PosterBoard reports before any run.

## Phase 2: Foundational (model, file, store, index; blocks every story)

- [ ] PRE-003-T02 Implement `PresetTagMap` and `PresetTagError` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTags.swift`: tag "trimmed, 1-40 characters, one line"; "1-16 tags" per preset; "≤ 256 distinct folded tags"; "≤ 20,000 entries"; fold (case, accents, width, `nil` locale); existing spelling adopted; sorted by (fold, text); `add`, `remove`, `prune`, `repaired` (research PRE-003-D2; contract C1).
- [ ] PRE-003-T03 Implement `PresetTagsFile` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagsFile.swift`: version 1, bounds "4 MiB, depth 4, strings ≤ 4 KiB, ≤ 20,000 elements per list or object, no duplicate keys", newer version refused, lenient per-entry repair with a drop count, stable encoding (research D4; contract C2).
- [ ] PRE-003-T04 Implement `PresetTagStore` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagStore.swift` (save before show, failed save changes nothing, newer format read-only, unreadable set aside, `repaired(dropped)` notice) (research D1).
- [ ] PRE-003-T05 Implement `PresetTagIndex` in `Packages/PresetLibrary/Sources/PresetLibrary/PresetTagIndex.swift` (listed IDs only, vocabulary, counts, AND `matching(all:)` from the smallest set with `visitedCount`, `presetIDs(tagContaining:)`) and `PresetScope.tagged`, `taggedListing`, `members(…tags:)`, `title`, `search(…tagMatches:)` in `PresetScope.swift` and `PresetLibrary.swift` (research D3, D5; contract C3).
- [ ] PRE-003-T06 [P] Package tests `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetTagMapTests.swift` and `PresetTagStoreTests.swift`: folding and dedup, adopted spelling, limits 40/16/256/20,000, remove and prune; file round trip and determinism; damaged entries dropped and counted; unreadable file set aside; newer format untouched and refused; failed save changes nothing.

## Phase 3: User Story 1 — tag presets and filter, after relaunch (P1, MVP)

**Independent test**: tag presets, filter by tags (expected ID set), recreate the store from disk, filter again: same IDs.

- [ ] PRE-003-T07 [US1] Package acceptance test `Packages/PresetLibrary/Tests/PresetLibraryTests/PresetTagAcceptanceTests.swift`: tag several presets of a fixture library, filter by one and two tags (expected IDs), recreate the store and index from disk, same IDs; search matches tags; tagged scope members; hidden orphans; bundled index and pack bytes hashed before and after unchanged; operation count of `matching` bounded by the smallest set on a 12,847-preset synthetic library; bench behind `PRE003_BENCH=1`.
- [ ] PRE-003-T08 [US1] App tag state in `Apps/projectM-iOS/Coordinators/PresetCoordinator.swift` and `Apps/projectM-iOS/Coordinators/PresetCoordinator+Tags.swift`: store, cached index, `selectedTags`, `toggleTag`, `clearTags`, `taggedListing`, `addTag`, `removeTag`, `pruneTags`, announcements (library lane edits, search lane chip counts), row label ", tags …", the tagged scope in `members` and `displayCount` (contract C4).
- [ ] PRE-003-T09 [US1] Views: `Apps/projectM-iOS/Views/PresetTagChips.swift` (chip row with Clear; tagged list with empty text) and `Apps/projectM-iOS/Views/PresetBrowserView.swift` (chips in home, favorites, search; tag-filtered search; row caption line). Register the new views in `scripts/check_status_events.py`.
- [ ] PRE-003-T10 [US1] Wiring in `Apps/projectM-iOS/Coordinators/AppCoordinator.swift` (store creation, announcer) and the DEBUG seed `-uitestSeedPresetTags "<tag>:<i>,<j>|…"` in `Apps/projectM-iOS/Debug/UITestPresetTagFixture.swift` (fresh launches only).
- [ ] PRE-003-T11 [US1] App acceptance tests `Apps/projectM-iOS/Tests/PresetTagAcceptanceTests.swift`: coordinator tags, chips (AND), recreate the coordinator from the same store directory, same IDs; tagged scope walk; announcements; the PresetLibrary and ShowControl folds agree.
- [ ] PRE-003-T12 [US1] UI test `Apps/projectM-iOS/UITests/PresetTagsUITests.swift` (under 30 s): seeded tags, select chip(s), the listed rows equal the expected names; relaunch without reset; same chips give the same rows.

## Phase 4: User Story 2 — tag a preset from its row (P1)

- [ ] PRE-003-T13 [US2] `Apps/projectM-iOS/Views/PresetTagsView.swift` (Tags sheet: tags with Remove button and VoiceOver action, field with Add and Return, suggestions narrowed by the field, refusal message) and the "Tags…" context menu item and VoiceOver action "Tags" on `PresetRow`.
- [ ] PRE-003-T14 [US2] UI test in `PresetTagsUITests`: add "Calm" through the row's Tags… sheet, the chip appears, selecting it lists only that preset (under 30 s).
- [ ] PRE-003-T15 [US2] Prune on user preset removal in `Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift`, covered by a unit test in `PresetTagAcceptanceTests`.

## Phase 5: User Story 3 — backup, restore, erase (P2)

- [ ] PRE-003-T16 [US3] LibraryBackup: `LibraryFolders.tagsFile`, `LibraryContents.presetTags`, reader, writer and backup reader (`collections/tags.json`), `LibraryRecords` key `preset-tags`, restore section `tags` with per-preset merge and copy-ID remap, installer write, preview line "Tags", erase category title "Collections, tags and favorites" (`Packages/LibraryBackup/Sources/LibraryBackup/*.swift`, `Apps/projectM-iOS/Coordinators/LibraryBackupCoordinator.swift`) (research D6).
- [ ] PRE-003-T17 [P] [US3] Tests `Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetTagTests.swift`: backup round trip onto an empty library; merge by choice (union capped at 16, replace, skip); erase of the collections category leaves no tags file.

## Phase 6: Polish

- [ ] PRE-003-T18 Repo checks (compliance, docs, motion, permissions, status events, script tests), privacy manifest and network symbol checks on the Debug app, type-check budget, no new UserDefaults keys, Linux-shaped build of PresetLibrary (no Apple-only API), PosterBoard count after; update spec status; delete the simulator and derived data.

## Dependencies

T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → (T09, T10) → T11 → T12 → T13 → T14 → T15; T16 after T03 (parallel with T08-T15) → T17 → T18.

## Parallel opportunities

T06 and T07 (different test files); T16-T17 (LibraryBackup) alongside the app tasks T08-T15.

## Implementation strategy

MVP = Phases 1-3 (tag, filter, persist across relaunch). US2 adds the editing sheet; US3 the backup
integration.
