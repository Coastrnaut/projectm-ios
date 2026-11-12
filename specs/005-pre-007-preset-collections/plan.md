# Implementation Plan: PRE-007 Preset collections

**Branch**: `feature/pre-007` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-pre-007-preset-collections/spec.md`

## Summary

Users create named collections of presets, order the presets and the collections by hand, and play
a collection as a navigation scope. The model, validation, ordering rules, the versioned file with
its migration path, and scope membership live in the existing `PresetLibrary` package (Foundation
only, tested on the macOS host and on Linux). The app adds a thin layer: `PresetCoordinator` owns a
`PresetCollectionStore`, and three small SwiftUI views extend the preset browser. One JSON file in
Application Support holds everything; every change is written atomically before it is shown.
No new package, dependency, entitlement, permission or networking.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2 / iOS SDK 27.2 (ADR-0002)

**Primary Dependencies**: none new. Foundation (`JSONEncoder`/`JSONDecoder`, `FileManager`,
`Data.write(options: .atomic)`), SwiftUI, Observation.

**Storage**: one file, `<Application Support>/PresetCollections/collections.json`, versioned
(`schemaVersion` 1), Codable, written atomically (research D1-D4). The chosen scope stays in
`settings.presetScope` (UserDefaults) with the new value `collection:<id>`.

**Testing**: XCTest. `PresetLibrary` on the macOS host with `swift test` (also valid on Linux, as
CI runs it) and on the iOS 27.2 simulator; app unit tests and XCUITests in the `projectM-iOS`
scheme on the iOS 27.2 simulator. A worktree has only the 28 Included presets, so tests that need
locked pack presets use the synthetic library fixtures (unit level).

**Target Platform**: iOS and iPadOS 26.0+; the package also builds for macOS 15 and Linux.

**Project Type**: mobile app with SwiftPM packages under `Packages/`

**Performance Goals**: opening the largest collection (1,000 presets) and saving a reorder each
under 0.5 s on the build machine (S9); typical saves are a few kilobytes.

**Constraints**: public Apple APIs only; no networking; no new entitlement or permission; no
purchase code touched; no bundled asset edited; writes are synchronous on the main actor and
bounded by the limits (100 collections × 1,000 presets).

**Scale/Scope**: 3 new source files and 1 changed file pair in `PresetLibrary` (about 450 lines),
1 changed coordinator, 3 new views, 2 changed views, 1 line in `AppCoordinator`, the privacy
policy. `project.yml` and the CI workflow need no change: `PresetLibrary` is already a dependency
and already in every package loop, and the app's sources are picked up by folder.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Note |
|---|---|---|
| I. Public Apple APIs only | Pass | Foundation file APIs and SwiftUI only. `check_compliance.py` runs before each commit. |
| II-V. Capture feasibility, strategy, labeling, claims | Pass | No capture code, label or claim changes. |
| VI. Modular boundaries | Pass | `PresetLibrary` stays Foundation-only (no UIKit, StoreKit, engine). The app layer only forwards. |
| VII. Real-time audio safety | Pass | No audio-path code changes; file writes happen on the main actor from user actions. |
| VIII. Upstream ProjectM fidelity | Pass | `Vendor/` untouched; no preset file is edited. |
| IX. Pinned dependencies and licenses | Pass | No new dependency. Collections hold references (ids) to presets, never preset content, so no redistribution question arises. |
| X. Evidence-based quality | Pass | Deterministic unit tests for all logic; simulator UI tests for the flow; S11 is `{device}` and not claimed. |
| Security | Pass | The saved file is treated as untrusted on read: size cap, shape validation, set aside when unreadable (R15). |
| Privacy | Pass with an amendment | A new kind of on-device data. Spec R17 amends FR-065/FR-123 additively (names, membership, order; no timestamps or history); the privacy policy is updated in the same change. No required-reason API is used (no file timestamps, no disk-space queries), so the privacy manifest is unchanged. |
| Workflow | Pass | specify → clarify → plan → tasks → analyze → implement on `feature/pre-007`; nothing pushed (run rule, ADR-0008). |

Post-design re-check (after Phase 1): unchanged, all pass. No Complexity Tracking entry is needed.

## Project Structure

### Documentation (this feature)

```text
specs/005-pre-007-preset-collections/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/preset-collections.md
├── contracts/preset-collections.schema.json
├── checklists/requirements.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/PresetLibrary/
├── Package.swift                                      # test target: + resources (golden fixtures)
├── Sources/PresetLibrary/
│   ├── PresetCollection.swift                         # NEW: model, name rules, limits, errors, order helpers
│   ├── PresetCollectionsFile.swift                    # NEW: versioned file, decode, migrations
│   ├── PresetCollectionStore.swift                    # NEW: load, transactional mutations, atomic save
│   ├── PresetScope.swift                              # + case collection(String), storage value
│   └── PresetLibrary.swift                            # members/title for a collection scope
└── Tests/PresetLibraryTests/
    ├── PresetCollectionTests.swift                    # NEW: names, limits, order helpers
    ├── PresetCollectionStoreTests.swift               # NEW: CRUD, reorder, persistence, failed write
    ├── PresetCollectionsFileTests.swift               # NEW: golden v1, newer version, unreadable, migration
    ├── PresetCollectionScopeTests.swift               # NEW: membership, lock, missing ids, navigation
    └── Golden/collections-v1.json                     # NEW: immutable fixture

Apps/projectM-iOS/
├── Coordinators/PresetCoordinator.swift               # collections API, scope title, fallback
├── Coordinators/AppCoordinator.swift                  # creates the store (one statement + UI-test reset)
├── Views/PresetBrowserView.swift                      # home row, routes, "Add to Collection" on PresetRow
├── Views/PresetFolderView.swift                       # unchanged API; rows gain the add action through PresetRow
├── Views/PresetCollectionsView.swift                  # NEW: list of collections (create, rename, delete, reorder)
├── Views/PresetCollectionView.swift                   # NEW: one collection (play, reorder, remove)
├── Views/CollectionSheets.swift                       # NEW: name sheet, add-to-collection sheet
├── Tests/PresetCollectionsCoordinatorTests.swift      # NEW
└── UITests/PresetCollectionsUITests.swift             # NEW

docs/privacy-policy.md                                 # "What is stored on your device" + coverage row
```

**Structure Decision**: Extend `PresetLibrary` and the existing coordinator; no new package. The
roadmap's proposed `LocalPortability`/`SceneDocuments` packages do not exist yet, and a collection
is library metadata, so it belongs next to the index and scopes it refers to. The file format is
its own type (`PresetCollectionsFile`), so FILE-005 (backup) and PRE-014 (export) can read the
logical records without the store.

## Design

### Model and rules (`PresetCollection.swift`)

- `PresetCollection`: `id` (opaque string, a UUID when created by the app), `name`, `presetIDs`
  (ordered, unique). `Codable`, `Sendable`, `Hashable`, `Identifiable`. The JSON key for
  `presetIDs` is `presets`.
- `PresetCollectionLimits`: `maxNameLength` 60, `maxCollections` 100, `maxPresetsPerCollection`
  1,000, `maxFileBytes` 16 MB.
- `PresetCollectionName.normalized(_:)`: line breaks → spaces, trim white space, count
  `Character`s; throws `emptyName` or `nameTooLong`. `PresetCollectionName.key(_:)`: the
  comparison key (case- and diacritic-folded), the same folding search uses.
- `PresetCollectionError` (Equatable): `emptyName`, `nameTooLong(limit:)`, `duplicateName`,
  `unknownCollection`, `tooManyCollections(limit:)`, `collectionFull(limit:)`, `invalidOrder`,
  `newerFormat(version:)`, `saveFailed`. Each has a user-facing sentence (`message`).
- `PresetCollectionOrder` (pure functions):
  - `moved(_:fromOffsets:toOffset:)`: the list-move rule of the standard list control, without
    importing a UI framework.
  - `applying(visibleOrder:to:)`: R14's rule. The stored list keeps hidden ids in their slots; the
    slots of the visible ids are refilled in the new visible order. Throws `invalidOrder` unless
    `visibleOrder` is a permutation of a subset of the stored ids.

### File and migration (`PresetCollectionsFile.swift`)

- `PresetCollectionsFile`: `schemaVersion` (Int), `collections` ([PresetCollection]).
  `currentVersion = 1`.
- `decode(_ data:, migrations:)` reads the version from a header-only decode first:
  - version == current → decode, validate (non-empty unique collection ids), remove duplicate
    preset ids keeping the first;
  - version > current → throws `.newerVersion(v)`, nothing else is read;
  - version < current → applies `migrations[v]` (pure `Data → Data`, one step per version) until
    the current version, then decodes; a missing step → `.unreadable`;
  - anything else (not JSON, wrong shape, invalid ids, size over the cap) → `.unreadable`.
- `encode()` uses sorted keys, so output is stable.
- The production migration table is empty (version 1 is the first). The path is tested with an
  injected step from a synthetic version 0 (a bare array of collections), so the first real
  migration only adds a table entry and a golden fixture.

### Store (`PresetCollectionStore.swift`)

- `init(directory:, makeID:, write:, migrations:)`. `makeID` defaults to a UUID string; `write`
  defaults to `Data.write(to:options: .atomic)`; both are injected in tests.
- Load (in `init`, never throws):
  - no file → empty, available;
  - current version → loaded;
  - older version → migrated in memory; the original is copied to
    `collections.v<old>.backup.json`; the migrated file is written; only after that write
    succeeded is the backup removed. If the write fails the original file is still in place and
    the store runs on the migrated in-memory state, retrying on the next change;
  - newer version → `availability = .newerFormat(version)`, file untouched, list empty, every
    mutation throws `newerFormat`;
  - unreadable → the file is renamed to `collections.unreadable.json` (replacing an earlier one),
    `loadNotice = .unreadableSetAside`, store empty and available.
- Mutations are transactions: copy the list, apply the change, encode, write, and only then
  replace the in-memory list. A failed write throws `saveFailed` and leaves memory and disk as
  they were (R8, S5).
- API: `collections`, `collection(id:)`, `create(name:)`, `rename(_:to:)`, `delete(_:)`,
  `add(_:to:)` (returns whether it was added), `remove(_:from:)`, `reorderPresets(in:visibleOrder:)`,
  `reorderCollections(_:)`, `presetIDsByCollection` (the dictionary scope membership takes).
- Not `Sendable`; owned and used by the main-actor `PresetCoordinator`, like `FavoritesStore`.

### Scope (`PresetScope.swift`, `PresetLibrary.swift`)

- `PresetScope.collection(String)`; storage value `collection:<id>`.
- `members(of:unlocked:favorites:excluded:collections:)` gains `collections: [String: [String]]`
  with an empty default, so existing callers compile unchanged. For `.collection(id)` the
  candidates are the collection's ids resolved through the index in stored order (missing ids
  skipped, R14); the common filter then removes locked and excluded presets (R13, FR-118).
- `collectionListing(_:)` returns the existing presets of an id list in stored order, locked ones
  included (what the collection screen shows; the counterpart of `favoritesListing`).
- `title(of:collectionNames:)` returns the collection's name; `resolves` stays true for a
  collection (the library cannot know; the coordinator checks the store).

### App layer

- `PresetCoordinator` takes the store in its initializer. It exposes `collections`,
  `collectionsAvailability`, `collectionsUnavailableText`, `collectionsNotice` (the set-aside
  sentence, dismissible), `collectionListing(_:)`, and one method per user action; each catches
  `PresetCollectionError`, sets `collectionsMessage` (shown as an alert) and bumps
  `collectionsVersion` so views refresh. `members`, `scopeLine` and the scope announcement pass the
  store's dictionary and names. `resolveScope()` also falls back when a collection scope names a
  collection that does not exist or the store is unavailable; it runs after `attach` and after a
  delete (R12). Purchase fields are not touched.
- `AppCoordinator` creates the store at
  `Application Support/PresetCollections` and passes it in. Under `-uitestResetNotice` (existing
  UI-test reset) that folder is removed first.
- Views:
  - Home: one row "Collections" with the count, after the library rows.
  - `PresetCollectionsView`: rows (name, count), `+` to create, Edit mode with move and delete,
    swipe actions and a context menu (Rename, Move Up, Move Down, Delete), delete confirmation,
    empty state, the unavailable sentence.
  - `PresetCollectionView`: `PresetRow`s in the user's order (lock, current mark, star as
    elsewhere), Edit mode with move and remove, context menu (Move Up, Move Down, Remove from
    Collection, Add to Collection), Rename in the toolbar menu. Choosing a preset calls the
    existing `onChoose(preset, .collection(id))`.
  - `PresetRow` (every list): context menu and swipe action "Add to Collection…" opening
    `AddToCollectionSheet` (existing collections with a checkmark when the preset is already
    there, and "New Collection…").
  - `CollectionNameSheet`: text field, live validation message, Save disabled until valid.
  - Drag handles exist only in Edit mode (research D7); the row menu and the VoiceOver actions
    work in both modes.
- Accessibility (R18): rows use `"<name>, <n> presets"`; move up/down are also VoiceOver custom
  actions (`accessibilityAction(named:)`) on both lists; all text uses system styles and wraps.

### Rollback

Reverting the commits removes the feature. A `collections.json` left on a device is ignored by an
older build (nothing reads it), and a stored `collection:<id>` scope does not parse there, so the
older build falls back to its default scope. No bundled or settings data is migrated, so there is
nothing to undo.

## Complexity Tracking

No constitution deviation; nothing to justify.
