# Data Model: FILE-006 Incremental Backup Manifest

## Folder layout

```text
<picked folder>/projectM Backup/        (or the picked folder itself when it holds backup-manifest.json)
  backup-manifest.json                  written last (atomic)
  projectM Library.pmbackup             FILE-005 archive, unchanged format (atomic)
  media/<sha256>.<ext>                  one copy per content
  media/.partial-<UUID>                 a copy in progress (collected by the next backup)
```

## BackupFolderManifest (`backup-manifest.json`)

| Field | Type | Rule |
|---|---|---|
| format | String | `org.projectmios.backup-folder` |
| formatVersion | Int | 1 (readable: [1]; anything else: unusable) |
| appVersion | String | ≤ 64 bytes |
| createdAt | String | ISO 8601 UTC |
| library | ArchiveRecord? | `{path: "projectM Library.pmbackup", byteCount, sha256}` |
| assets | [AssetEntry] | ≤ 8,192, sorted by kind then name, unique (kind, name) |

## AssetEntry

| Field | Type | Rule |
|---|---|---|
| kind | String | 1-32 chars `[a-z0-9-]`; known: `photo`, `video`, `audio`, `audio-index`; others kept but not restored by this version (SCN-004 may add kinds) |
| name | String | logical name: one safe path component (no `/`, `\`, NUL, not `.`/`..`, no leading `.`), ≤ 255 bytes |
| byteCount | Int64 | ≥ 0 |
| modified | Double? | seconds since 1970 of the source file; only for assets without a content address |
| sha256 | String? | 64 lowercase hex; absent only in older manifests (then not reused) |
| location | String | `media/<sha256>.<ext>`, ext 0-8 chars `[a-z0-9]` (no dot when empty); its stem equals `sha256` |

## BackupAsset (inventory, not stored)

`kind`, `name`, `url` (the stored file), `contentAddress` (the stem of the stored file name when it is
64 lowercase hex), `fileExtension`.

| Kind | Source | Name |
|---|---|---|
| photo | `Photos/` FILE-008 logical files | `<UUID>.png|jpg` |
| video | `Videos/` FILE-008 logical files | `<UUID>.mov` |
| audio | `AudioLibrary/assets/` | `<sha256>[.<ext>]` |
| audio-index | `AudioLibrary/index.json` | `index.json` |

## FolderBackupReport

`copied`, `unchanged`, `removed`, `bytesCopied`, `fullBackup` (no usable previous manifest), `manifest`.

## Media restore (`Application Support/MediaRestore/`)

- `staged/<sha256>.<ext>`: verified copies.
- `request.json`: `{schemaVersion: 1, assets: [AssetEntry]}`, written after every staged copy.
- `last-result.json`: `{schemaVersion: 1, installed, alreadyHere, skipped}`, shown once.

State: none → staged (request present) → installed at launch (request and staging removed, result
written) → result taken (file removed). Cancel removes the folder.
