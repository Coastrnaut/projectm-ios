# Implementation Plan: PRE-003 Preset Tags

**Branch**: `feature/pre-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/149-pre-003-preset-tags/spec.md`

## Summary

Tags follow PRE-007's storage pattern (one versioned file in `Application Support/PresetCollections/`)
and SCN-005's rules. Bundled assets are never written.

Pure model (`Packages/PresetLibrary/Sources/PresetLibrary/`, Foundation only, Linux-tested):

- `PresetTags.swift` (new): `PresetTagMap` (preset ID → sorted tags) with `normalizedTag`, `fold`
  (case, accents, width; `nil` locale, as SCN-004/005), `add`, `remove`, `prune`, `repaired`, and
  `PresetTagError` with messages. Limits 40 characters, 16 per preset, 256 distinct, 20,000 tagged
  presets (research PRE-003-D2).
- `PresetTagIndex.swift` (new): the inverted index (folded tag → set of preset IDs) over the presets
  the library lists, its display spellings and vocabulary, `matching(all:)` (AND by intersecting from
  the smallest set; counts the IDs it visits) and `presetIDs(tagContaining:)` for search
  (research PRE-003-D3).
- `PresetTagsFile.swift` (new): the document (`schemaVersion` 1, `tags` object), FILE-007 bounded
  schema check, newer version refused, lenient per-entry repair with a drop count (research D4).
- `PresetTagStore.swift` (new): loads and saves `tags.json` atomically like `PresetCollectionStore`
  (save before show, newer format read-only, unreadable file set aside) (research D1).
- `PresetScope.tagged([String])` (stored as `all`), `PresetLibrary.taggedListing`, `members(of:…,
  tags:)`, `title`, and `search(_:limit:tagMatches:)` (research D5).

Backup and erase (`Packages/LibraryBackup`): `LibraryFolders.tagsFile`; `LibraryContents.presetTags`;
the reader, the backup writer and reader (`collections/tags.json`), `LibraryRecords` (`preset-tags`),
the restore planner (section `tags`, per-preset merge by choice, copy-ID remap) and installer (writes
the staged collections folder); FILE-011 category title "Collections, tags and favorites"; erase
already removes the whole folder (research D6).

App:

- `PresetCoordinator` (+ `PresetCoordinator+Tags.swift`, new): the tag store, the cached index
  (rebuilt when tags or the library change), `selectedTags` (in memory), `toggleTag`, `clearTags`,
  `taggedListing`, `addTag`, `removeTag`, `pruneTags`, announcements (library lane for edits, search
  lane for chip counts), row label ", tags …", `searchResults(_:)` combining tags and chips.
- `UserPresetsCoordinator.remove`: prunes the removed preset's tags.
- Views: `PresetTagsView.swift` (new Tags sheet), `PresetTagChips.swift` (new chip row and the tagged
  list), `PresetBrowserView` (chips in home, favorites and search; tag results), `PresetRow` ("Tags…"
  context menu, VoiceOver action "Tags", caption line).
- `AppCoordinator`: one line creating the store; wiring of the announcer; DEBUG seed
  `-uitestSeedPresetTags` (new `Debug/UITestPresetTagFixture.swift`).
- `scripts/check_status_events.py`: register the two new views.
- No new UserDefaults keys, no networking.

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/preset-tags.md](contracts/preset-tags.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26)

**Primary Dependencies**: PresetLibrary, LocalPortability (schema check), LibraryBackup. None new.

**Storage**: `Application Support/PresetCollections/tags.json` (version 1, ≤ 4 MiB).

**Testing**: XCTest. PresetLibrary package tests on host and Linux (rules, index, file, store,
acceptance with recreate-from-disk, bundled-file hash, operation-count performance); LibraryBackup
(round trip, restore merge, erase); app unit tests (`PresetTagAcceptanceTests`); one UI test with a
relaunch (`PresetTagsUITests`, under 30 s) on the feature's own simulator "PRE3".

**Target Platform**: iOS 26+ (app), macOS 15 and Linux (packages).

**Performance Goals**: a chip change costs O(size of the smallest selected tag's set × number of
selected tags) plus sorting the result; the index build is O(tagged entries). Measured by counts; no
wall-clock assertions. A DEBUG-free bench behind `PRE003_BENCH=1` prints timings on demand.

**Constraints**: Linux build of PresetLibrary and LibraryBackup; type-check budget; short tests.

**Scale/Scope**: 12,847 bundled presets plus up to 1,000 user presets; ≤ 20,000 tagged entries.

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI and Foundation only; no networking. |
| VI. Modular boundaries | Pass: model, file format and index in PresetLibrary (Linux-tested); backup in LibraryBackup; the app wires and draws. |
| IX. Pinned dependencies | Pass: none added. |
| X. Evidence-based quality | Pass: automated tests; simulator results are not device evidence; no device claim. |
| Privacy constraints | Pass: local Application Support only; no UserDefaults keys; tags are user content, never logged. |

Post-design re-check: unchanged.

## Project Structure

```text
specs/149-pre-003-preset-tags/  spec, plan, research, data-model, contracts/preset-tags.md, quickstart, tasks
Packages/PresetLibrary/Sources/PresetLibrary/PresetTags.swift          (new)
Packages/PresetLibrary/Sources/PresetLibrary/PresetTagIndex.swift      (new)
Packages/PresetLibrary/Sources/PresetLibrary/PresetTagsFile.swift      (new)
Packages/PresetLibrary/Sources/PresetLibrary/PresetTagStore.swift      (new)
Packages/PresetLibrary/Sources/PresetLibrary/PresetScope.swift         (tagged scope)
Packages/PresetLibrary/Sources/PresetLibrary/PresetLibrary.swift       (members, title, search)
Packages/PresetLibrary/Tests/PresetLibraryTests/PresetTag*Tests.swift  (new)
Packages/LibraryBackup/Sources/LibraryBackup/*.swift                   (tags record, plan, install, erase title)
Packages/LibraryBackup/Tests/LibraryBackupTests/LibraryBackupPresetTagTests.swift (new)
Apps/projectM-iOS/Coordinators/PresetCoordinator.swift (+Tags.swift new)
Apps/projectM-iOS/Coordinators/UserPresetsCoordinator.swift            (prune on remove)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                    (store, wiring, seed)
Apps/projectM-iOS/Views/PresetTagsView.swift, PresetTagChips.swift     (new)
Apps/projectM-iOS/Views/PresetBrowserView.swift                        (chips, row action)
Apps/projectM-iOS/Debug/UITestPresetTagFixture.swift                   (new)
Apps/projectM-iOS/Tests/PresetTagAcceptanceTests.swift                 (new)
Apps/projectM-iOS/UITests/PresetTagsUITests.swift                      (new)
scripts/check_status_events.py                                         (register views)
```

## Complexity Tracking

None.
