# Research: FILE-005 Local Library Backup

## FILE-005-D1: Archive format

- **Decision**: FILE-002's `PortableArchive` (stored ZIP, `manifest.json` last with every entry's path,
  SHA-256 and size), format `org.projectmios.library-backup`, `formatVersion` 1, extension
  `.pmbackup` (exported as `public.zip-archive`-conforming data so Files can hold it).
- **Rationale**: The reader already enforces entry counts, sizes, safe paths, CRC-32, checksums, a
  bounded manifest (FILE-007) and "newer version → update the app"; ImportFuzz covers it.
- **Alternatives**: A single JSON document (base64 photos, no per-entry checksums); a property list
  (no shape checks before decoding).

## FILE-005-D2: What is a logical record and how to compare

- **Decision**: `LibraryRecords` maps record keys to the SHA-256 of a canonical encoding: `show` →
  re-encoded `ShowCueList`; `scene/<ID>` and `current-scene` → SCN-001 canonical bytes after decode
  (and SCN-013 migration); `preset/<id>` → sorted-key JSON of the logical fields (no `state`,
  `provenOnScreen`, `quarantine`) plus the text's SHA-256; `collections` → `PresetCollectionsFile`
  canonical bytes; `setting/<key>` → the typed value's canonical JSON; `favorites` → sorted list;
  `photo/<name>` → bytes. Equality of two libraries = equality of the maps; `differences` lists keys.
- **Rationale**: File dates and store-chosen names (content-addressed text names, backup copies) are
  not records; canonical encodings already exist for every format.

## FILE-005-D3: When the restore is applied

- **Decision**: At the next launch, in `AppCoordinator.init` before `AppSettings` and every store are
  created. Restore stores `LibraryRestore/pending/backup.pmbackup` and `request.json` (choice, backup
  SHA-256); the launch runner re-reads, plans again with the same choice and installs.
- **Rationale**: Coordinators hold presets, collections, favorites, the show, the current scene and
  settings in memory and write them back (autosave every change); a restore made under them would be
  overwritten or half-seen.
- **Alternatives**: Reloading coordinators in place (large, racy); recreating `AppCoordinator`
  (teardown of audio and renderer is not designed for it).

## FILE-005-D4: All-or-nothing install across folders

- **Decision**: For each folder the plan changes, copy the live folder to
  `LibraryRestore/staging/<name>` and apply the plan there (presets, collections, current scene and
  photos by direct writes; show merge through `ShowStore.installImportedScenes` on the staged copy).
  Then write `restore.journal.json` (phase `prepared`, the folders), move each live folder to
  `LibraryRestore/previous/<name>` and the staged one into place, rewrite the journal as `committed`
  with the settings to apply (the commit point), hand the settings to the app, and remove the work
  folders. Any failure before the commit moves everything back. At launch `recover()` rolls a
  `prepared` journal back and a `committed` one forward. Every file operation goes through one
  function with a fault hook.
- **Rationale**: Renames within one volume are atomic; the folders all live under Application Support.

## FILE-005-D5: Derived identifiers

- **Decision**: Presets: `user/` + 32 hex of SHA-256("FILE-005|preset|<id>|<text sha256>|<n>");
  collections: an uppercase UUID (version nibble 8) from SHA-256("FILE-005|collection|<id>|<content
  sha256>|<n>"); scenes and cues: FILE-004's rules (its installer runs). Smallest n ≥ 1 not taken.
  Copy names: FILE-004/PRE-015's `UserPresetName.copyName`, PRE-007's case-insensitive name key for
  collections ("<name> copy", "<name> copy 2").

## FILE-005-D6: Settings bridge

- **Decision**: The package declares the included keys (`LibrarySettingsPolicy.includedKeys`); the app
  reads each key with `UserDefaults.object(forKey:)` and classifies Bool (CFBoolean), Int, Double,
  String, [String] and Data; it writes values back with the matching setter. An app test checks the
  key list against the stores' own key constants.

## FILE-005-D7: Exclusions

- **Decision**: As the spec Baseline. Presets: `UserPresetExportPlan.exclusion` == `.fullLibraryCopy`
  (ADR-0008) and quarantined records are left out; the rest are written with their text and come back
  `pending`. Videos, imported audio and the device keys are never read. The manifest carries the
  counts of what was left out.
