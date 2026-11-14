# Research: FILE-003 Import Dry Run

## FILE-003-D1: Where the dry run starts for presets

- **Decision**: Extend "Import Preset…": a picked `.zip` opens the preview; `.milk` keeps PRE-012.
- **Rationale**: The archive format exists (PRE-014) and its reader is tested, but the app had no archive import; one entry point keeps the screen simple and makes the row reachable.
- **Alternatives**: A separate "Import Archive…" button (another toolbar item at accessibility sizes, rejected); waiting for PRE-013 (leaves the row unreachable).

## FILE-003-D2: What counts as the library, and how equality is proven

- **Decision**: `LibraryTreeSnapshot` records every file's relative path and SHA-256 and every directory under the owned roots (`UserPresets`, `PresetCollections`; for scenes `Photos`, `Videos`), plus the owned UserDefaults values. Two snapshots are compared with `==`.
- **Rationale**: Exactly the acceptance wording ("byte-for-byte"), including empty folders created and left behind.
- **Alternatives**: Comparing modification dates (not byte-level), comparing only the index (misses stray files).

## FILE-003-D3: Deterministic identifiers for Keep both

- **Decision**: A renamed copy's identifier is `user/` + the first 32 hex digits of SHA-256(`"FILE-003|" + incoming id + "|" + text sha256 + "|" + n`), with the smallest n ≥ 1 not used by the library or earlier planned entries.
- **Rationale**: Planning twice with the same inputs gives equal plans, so Install's re-validation is a plain `==`, and fixture plans are exact. Identifiers stay within `[a-z0-9-]`, 32 characters (PRE-014 accepts 1-75).
- **Alternatives**: Random UUIDs at plan time (re-plan never equal); random at install (plan would not state the identifiers the install uses).

## FILE-003-D4: Atomic install

- **Decision**: Stage every text in `UserPresets/Staging/` (inside the store, so PRE-015-R19's path guard still covers every operation), re-read each staged file and check its SHA-256, rename each into `Files/` (same volume, atomic), then write the index once with an atomic write. On failure: remove every moved file, remove folders this install created if empty, remove `Staging/`. A leftover `Staging/` from a crash is removed by `load()` (the index never named those files).
- **Rationale**: The index is the single commit point: before it is written no preset is listed; the rollback removes the only other traces.
- **Alternatives**: Staging under `tmp/` (the store's path guard refuses paths outside its folder; cross-volume risk); one `add` per preset (a failure midway would leave a partial install).

## FILE-003-D5: Metadata from the archive is not trusted

- **Decision**: Each text is validated again with `MilkdropPresetValidator` against the app's textures; its warnings and licence lines replace the archive's. The archive's name is cleaned like an imported name. Presets enter `pending`.
- **Rationale**: Same safety as a picked file (PRE-012-R20); the archive could be hand-edited.

## FILE-003-D6: Scene archive dry run

- **Decision**: `planImport(at:)` copies the picked file into a temporary staging folder (removed on return), reads it with `SceneArchiveReader`, and builds the plan; the media are not staged into stores. SCN-012 entries are computed on the document with each asset key's store ID replaced by a placeholder that the availability reports present (what the install produces). `importArchive(at:plan:)` re-reads, compares the archive SHA-256 and the current photo and video IDs with the plan's, then runs the existing import.
- **Rationale**: The stores and their keys are not touched by the dry run; the commit path stays the tested FILE-001 path.

## FILE-003-D7: Replace

- **Decision**: Not in this row (FILE-004). Recorded in the spec's Clarifications.
