# Research: PRE-007 Preset collections

Decisions are numbered `PRE-007-D1…`. All were made on 2026-11-12 from the code at `6d669fc`.

## PRE-007-D1: JSON file, not SQLite, not UserDefaults

- **Decision**: one Codable JSON file, `collections.json`.
- **Rationale**: the data is small and bounded (at most 100 × 1,000 short strings), always read
  whole, and changed only by one user action at a time. JSON gives a human-readable, versioned
  format that later export and backup features (PRE-014, FILE-005) can copy as is, and matches the
  roadmap's "versioned, Codable, atomic local writes" policy. The package stays Foundation-only
  and Linux-testable.
- **Alternatives**: SQLite (no need for queries or partial updates; adds a C dependency to a
  Foundation-only package); UserDefaults (favorites use it, but it has no versioning or atomic
  whole-document replacement the app controls, and FR-065's key list is checked by the device
  privacy review); one file per collection (ordering of collections would need a second index
  file and non-atomic multi-file updates).

## PRE-007-D2: Application Support, own folder

- **Decision**: `<Application Support>/PresetCollections/`, created on first save.
- **Rationale**: user data that is not a user-visible document. `Documents` is reserved for the
  automation reports that the device privacy review whitelists (`run_device_tests.py`
  `privacy_problems`), and the app does not expose its Documents folder. Application Support is
  included in device backups, which is right for user-created data. A folder of its own gives the
  backup and set-aside files a home and lets FILE-011 (erase) remove one folder.
- **Alternatives**: Caches (may be purged); Documents (see above).

## PRE-007-D3: Atomic replacement through Foundation

- **Decision**: `Data.write(to:options: .atomic)` (write to a temporary file, then rename), with
  the write function injected so tests can make it fail.
- **Rationale**: the documented way to replace a file so that readers see either the old or the
  new content. A transaction commits to memory only after the write returned.
- **Alternatives**: `FileManager.replaceItemAt` (needs the temporary file handled by hand, same
  result); a write-ahead journal (not needed for a whole-document replace).

## PRE-007-D4: Version field with a step table

- **Decision**: `schemaVersion` integer at the top level; pure `Data → Data` steps keyed by the
  version they read; a header-only decode decides which path applies before the body is touched.
- **Rationale**: the roadmap requires pure, versioned, fixture-tested migrations and a backup kept
  until the atomic replacement succeeded. Reading only the header first means a newer file is
  never partially interpreted. Version 1 is the first, so the production table is empty; the
  machinery is proved with an injected synthetic step and the v1 golden fixture pins today's
  format.
- **Alternatives**: decoding leniently and re-saving (would silently drop fields a newer version
  wrote); refusing to start (collections are not essential to playing).

## PRE-007-D5: Scope membership stays in `PresetLibrary.members`

- **Decision**: add `PresetScope.collection(id)` and pass the collections' id lists into
  `members(of:…)` with a defaulted parameter, exactly as favorites are passed today.
- **Rationale**: one place applies the lock and session-exclusion filters for every scope, so a
  collection cannot bypass them (R13). `ScopeStepper` needs no change: it already walks whatever
  order it is given, which is the manual order here.
- **Alternatives**: a separate membership function in the app (two filters to keep in step);
  making the library own the collections (it is immutable and `Sendable`; collections are mutable
  user state).

## PRE-007-D6: Reordering with hidden entries

- **Decision**: the UI reorders the visible entries; the store maps that onto the stored list by
  refilling the visible entries' slots in the new order and leaving hidden entries in place.
- **Rationale**: satisfies R14 (nothing discarded) and R6 (the shown order is exactly what was
  set) with a pure function that is easy to test exhaustively on small lists.
- **Alternatives**: moving hidden entries to the end (loses their position if the preset returns);
  showing placeholders for missing presets (noise the user cannot act on).

## PRE-007-D7: Reordering controls

- **Decision**: the standard list edit mode (drag handles) plus "Move Up" and "Move Down" in each
  row's context menu and as VoiceOver custom actions.
- **Rationale**: R18 requires reordering without a drag. Custom actions are the documented
  VoiceOver pattern; the context menu covers Switch Control and Voice Control users and people
  who find dragging hard, and gives UI tests a deterministic control.
- **Alternatives**: edit mode only (drag with VoiceOver works but is awkward and is not
  testable in the simulator in a stable way).

- **Found during implementation (2026-11-12)**: with the list's move handler always attached, a
  touch-and-hold on a row starts both the row menu and a pending drag-to-reorder; on the iOS 27.2
  simulator the app then never became idle and the UI test timed out. The move handler is
  therefore attached only while Edit mode is on (each screen owns its edit-mode state and passes it
  to the list and the Edit button). Outside Edit mode, touch and hold opens the menu only.
- **Also found**: closing the name sheet and its parent add sheet in the same step left the
  presentation state inconsistent (the next row menu never opened). The add sheet now closes
  itself only; that takes the name sheet with it.

## PRE-007-D8: Synchronous saves on the main actor

- **Decision**: save synchronously inside the user action.
- **Rationale**: the result (saved or not) must be known before the screen shows the change (R8).
  The worst-case document is about 8 MB; the performance test bounds the largest allowed
  collection (S9). Typical saves are kilobytes.
- **Alternatives**: a background writer (needs a queue, coalescing and a reconciliation path for
  failures; not justified at this size).

## PRE-007-D9: No document picker

- **Decision**: none is added, although the roadmap's shared technical hint for the PRE table
  names `UIDocumentPicker`.
- **Rationale**: nothing in PRE-007's behavior or acceptance involves choosing a file; import and
  export are PRE-012 to PRE-014 and FILE-005.

## PRE-007-D10: Privacy and compliance review

- The collections file holds names the user typed, preset ids and order. No timestamps, counters
  or history (R16). It never leaves the device. The privacy policy's stored-data list gains one
  bullet (R17).
- No required-reason API: the store does not read file timestamps, free space, boot time or the
  keyboard list, and adds no UserDefaults key (the scope key exists).
- `scripts/run_device_tests.py` `privacy_problems` flags unexpected files only under `Documents`
  and `tmp` and audio extensions anywhere; `Library/Application Support/PresetCollections/*.json`
  passes. No script change is needed.
- Licensing: no preset content is copied; collections reference bundled presets by id.

## Cross-feature notes (not implemented here)

- PRE-003 (tags), PRE-006 (recents), PRE-008 (smart collections): separate data with their own
  rules. If they join this file, they do so as new top-level keys in a later `schemaVersion`
  through D4's step table. A smart collection is not a `PresetCollection` (it has rules, not
  entries); `PresetScope` can gain its own case.
- PRE-014 / FILE-005: `PresetCollectionsFile` is the logical record set; ids are stable preset
  ids, no absolute paths.
- The AUD import feature built in parallel touches `project.yml`, the source chooser and
  `AppCoordinator`; this feature changes one statement in `AppCoordinator.init` and nothing in
  `project.yml` or CI.
