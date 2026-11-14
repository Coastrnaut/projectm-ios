# Contract: Folder backup (FILE-006)

## B1 Manifest
`BackupFolderManifest` (Codable), `BackupFolderManifest.read(_ data: Data) -> BackupFolderManifest?`:
nil for anything outside data-model.md's rules (size, bounded JSON, format, version, every entry).
`encoded()` is deterministic (sorted keys, entries sorted).

## B2 File access
`protocol BackupFileAccess: Sendable`:
`status(of:) -> BackupFileStatus?` (byte count; modification date only when asked, container files only),
`copy(from:to:) throws -> MediaContentHash.Digest` (one streaming read, hashing),
`digest(of:) throws -> MediaContentHash.Digest`. `LocalBackupFileAccess` is the real one. Media bytes
are read only through this protocol.

## B3 Inventory
`MediaBackupInventory.assets(root: URL) -> [BackupAsset]`: reads directory listings and the FILE-008
registries only; no media bytes.

## B4 Backup
`FolderBackupWriter(access:fault:).write(archive: Data, assets: [BackupAsset], to folder: URL,
appVersion: String, createdAt: Date) throws(FolderBackupError) -> FolderBackupReport`.
- Unchanged assets (research D2) are not passed to `copy` or `digest`.
- New or changed assets are copied once each; equal contents are copied once.
- No usable manifest: full backup (nothing in the folder is trusted).
- Order: copies, archive, manifest, prune. A thrown fault leaves the previous manifest and every file
  it names unchanged.
`FolderBackupLayout.backupFolder(in picked: URL) -> URL`.

## B5 Restore
`MediaRestoreStager(access:).stage(from folder: URL, root: URL) throws(MediaRestoreError) -> MediaRestoreSummary`:
every entry copied into `MediaRestore/staged/` with its hash checked; any mismatch, missing file or
unusable manifest refuses and removes the staging. `MediaRestoreRequestStore(root:)`: `pending`,
`cancel()`, `takeResult()`. `MediaRestoreLaunch.run(root:) -> MediaRestoreResult?`: installs a pending
request (photos/videos whose identifier does not resolve; audio only without an audio index), removes
the request and staging, records the result. Repeatable after an interruption.

## B6 App
`FolderBackupCoordinator`: `backUp(to:)`, `stageRestore(from:)`, `cancelRestore()`, `refresh()`;
messages announced on the `library` lane. Backup section rows "Back Up to Folder…",
"Restore Media from Folder…", pending text and "Cancel Media Restore". DEBUG: `-uitestBackupFolder <path>`,
`-uitestMediaRestoreFrom <path>`, `-uitestMediaSeed`.
