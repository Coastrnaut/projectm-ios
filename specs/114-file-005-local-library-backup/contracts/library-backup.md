# Contract: FILE-005 Local Library Backup

## C1 Backup writer

`LibraryBackupWriter.write(_ contents: LibraryContents, appVersion: String, createdAt: Date) throws -> Data`
writes the archive of data-model.md: entries in a fixed order (show, scenes by ID, current, preset
index, texts by hash, collections, settings, photos by name), manifest last. Equal contents and
metadata give equal bytes.

## C2 Backup reader

`LibraryBackupReader.read(_ data: Data) throws(LibraryBackupError) -> LibraryBackupContents` refuses,
before interpreting any record: more than 512 MiB, a ZIP/manifest/checksum failure (FILE-002 errors),
a foreign format, a newer version (`newerVersion`, "update the app"), an unsafe or unexpected path,
more than 64 photos. Then each record is decoded by its own reader (scene decode with SCN-013
migration, `ShowCueList.decode`, `UserPresetsFile.decode`, `PresetCollectionsFile.decode`, settings
schema) and cross-checked (scene file name = document ID; preset text SHA-256 = record; no
excluded record). Any failure refuses the whole backup with the record named.

## C3 Logical records

`LibraryRecords(_ contents: LibraryContents)` and `LibraryRecords.read(folders:settings:)`;
`==`, `differences(from:) -> [String]`. Keys and encodings: research FILE-005-D2.

## C4 Planner

`LibraryRestorePlanner.plan(backup: LibraryContents, library: LibraryContents, choice:, overrides:) ->
LibraryRestorePlan` is pure; rules in spec Clarifications (FILE-005-R10). The show is planned by
FILE-004's `ShowSceneImportPlanner` when the library's show is not empty.

## C5 Installer

`LibraryRestoreInstaller(folders:).install(backup:plan:applySettings:) -> LibraryRestoreOutcome`
(`.restored(summary)`, `.changed(newPlan)`, `.refused(message)`); `recover(applySettings:) -> Bool`.
Steps and guarantees: research FILE-005-D4. `applySettings` receives values to set and keys to remove,
only after the commit point.

## C6 Request and launch runner

`LibraryRestoreRequestStore(folders:)`: `save(backup: Data, choice:)`, `pending`, `cancel()`,
`takeResult()`. `LibraryRestoreLaunch.run(folders:settings:applySettings:)`: recover an interrupted
restore, then install a pending request (plan again with its choice) and record the result; the
request is removed in every case.

## C7 App

- Settings › Storage › Backup: "Back Up Library…" (summary, then the system exporter;
  the temporary file is deleted when it closes) and "Restore from Backup…" (system picker with
  `.pmbackup` and ZIP types; preview with counts and the "Apply to all" choice; "Restore at Next
  Launch"; "Cancel Restore" while pending; the result once).
- Announcements: the shared announcer's `library` lane.
- DEBUG: `-uitestBackupTo <host path>` copies the written backup there; `-uitestRestoreFrom <host
  path>` previews that file as if picked.
