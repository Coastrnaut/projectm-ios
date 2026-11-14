# ADR-0041: The Local Library Backup Format, Its Exclusions and a Restore at Next Launch

- **Status**: Accepted 2026-11-14 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: FILE-005 (`specs/114-file-005-local-library-backup`)
- **Constitution**: I (public APIs), VI (modular boundaries), X (evidence-based quality); Security
  (imported files are untrusted) and Privacy
- **Builds on**: ADR-0008 (full-library copies stay on the device), ADR-0029 (archive checksums give
  integrity, not authenticity), FILE-001/002/007 (portable archive, checksummed manifest, bounded
  JSON), FILE-003 (dry run, tree snapshot), FILE-004 (Skip / Keep both / Replace, derived IDs, scene
  installer), SCN-013 (scene migration), PRE-012 (preset checks)

## Context

FILE-005 saves the user's library in one file they choose and restores it, with the acceptance
"Restore on fresh sandbox recreates exact local logical records". Three questions need a durable
answer: what the file holds (and must never hold), what "exact" means, and how a restore that spans
several stores stays all or nothing while the running app holds those stores in memory.

## Decision

1. **Format**: a FILE-002 portable archive (`.pmbackup`), format `org.projectmios.library-backup`,
   version 1: `show/show.json`, `show/scenes/<ID>.scene.json`, `current/current.scene`,
   `presets/index.json` + `presets/texts/<sha256>.milk`, `collections/collections.json`,
   `settings.json` (typed values), `photos/<UUID>.png|jpg`, and `manifest.json` last (format, version,
   app version, created at, record counts, exclusion counts, every entry's size and SHA-256). Limits:
   512 MiB file, 4,096 entries, 64 MiB per entry, 1 MiB manifest, 64 photos. A newer version is refused
   ("update the app"); records inside are migrated by their own readers.
2. **Included**: the show and its scenes (with their MOD-002 bindings), the current scene, My Presets
   (imported presets and copies of Included presets, with their texts), collections, favorites, the
   last preset, the settings in `LibrarySettingsPolicy.includedKeys`, and the stored photos.
3. **Never included**: copies of full-library presets (ADR-0008: a backup must not move paid content to
   another account), quarantined presets, the StoreKit entitlement (the App Store restores purchases),
   videos and imported audio (hundreds of megabytes, originals stay with the user; FILE-006's place),
   OSC on / MIDI on (device switches that need a permission on the device), notices, permission
   explanations, session recovery and guide state. The reader refuses a backup that holds a
   full-library copy, a quarantined record or an unknown setting.
4. **A file never vouches for a text**: restored presets come back waiting for their check (PRE-012),
   and the reader runs the static preset check on every text.
5. **Exact logical records** are defined by `LibraryRecords`: per record key the SHA-256 of a canonical
   encoding (canonical scene and show bytes, preset logical fields + text, collections file bytes in
   order, typed setting values, photo bytes). The check state, file dates and store-chosen names are
   not records.
6. **Restore at next launch**: the request (a copy of the backup and the "Apply to all" choice) is
   stored; `AppCoordinator.init` runs it before any store reads the library. The library is planned
   again with the same choice, every changed folder is built in a staging area, swapped in under a
   journal (prepared → committed), and settings are applied after the commit; an interrupted restore
   is rolled back or forward at the next launch.
7. **Clashes** follow FILE-004 (Keep both default): keyed records get derived identifiers
   (`FILE-005|<kind>|<id>|<content sha256>|<n>`; scenes through FILE-004's installer); single values
   cannot be kept twice, so Keep both keeps the device's value; favorites are combined.

## Consequences

- Restoring into a fresh library recreates every included record exactly (package acceptance test;
  simulator UI test across three launches).
- A scene that used a video shows the existing "no longer stored" notice after a restore on another
  device; the summary says videos were kept on the device.
- The user must close and reopen the app to finish a restore; the Backup section says so and the
  request can be cancelled.
- Checksums detect damage, not deliberate edits (ADR-0029); every record is still decoded and checked
  by its own reader, and nothing in a backup is executed.

## Alternatives rejected

- Restoring in place while the app runs: every coordinator would need a reload path, and autosave
  would write the old state back over the restore.
- Including videos and imported audio: backups of hundreds of megabytes read into memory; left to
  FILE-006's incremental media manifest.
- Trusting a preset's "checked" state from the file: a crafted backup could mark any text playable.
