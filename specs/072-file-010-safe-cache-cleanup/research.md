# Research: FILE-010 Safe Cache Cleanup

## R1 — What is deletable

- **Decision**: Allowlist by FILE-009 category: Recordings (`tmp/Recordings`), Shares and exports
  (`tmp/Sharing`, `tmp/SceneArchiveExport`, `tmp/PresetExport`), Caches (`Library/Caches`). Everything
  else is kept, including the SHOW-001 `Show` folder (counted under Other app data) and
  `Library/Preferences`.
- **Rationale**: These folders are the ones whose owners already treat their contents as disposable
  (removed at launch or after sharing; the system purges Caches). An allowlist fails safe: a new store
  is kept until someone classifies it.
- **Alternatives**: a denylist of user-data folders (fails open for new stores); clearing all of `tmp`
  (would also hit the scene archive import staging folder while an import runs).

## R2 — Root vetting

- **Decision**: A root is refused when its category is not cleanable, it is a link, it resolves to the
  container or outside it, it equals, contains or lies inside a protected (user-data) root, or it
  duplicates an earlier root. The root folder itself is never removed, only its contents.
- **Rationale**: Defends against a misconfigured location (for example Caches pointed at Application
  Support) and keeps the folder its owner expects to exist.

## R3 — Links

- **Decision**: Children are listed with FILE-009's reader (`isSymbolicLinkKey`, no following). A link
  is planned as a link item (zero bytes) and removed with `FileManager.removeItem(atPath:)`, which
  unlinks a link rather than its target and never traverses links inside a removed folder.
- **Execution re-check**: before each removal the parent folder must still resolve to itself (no folder
  above the item became a link) and lie strictly inside the vetted root; a vanished item is skipped.
- **Alternatives**: `unlink`/`rmdir` per file (C calls, more code, same effect).

## R4 — In-use protection

- **Decision**: The app passes absolute paths in use, gathered on the main actor when Clear Caches is
  tapped and again just before clearing: the recording folders while `VideoRecordingCoordinator.state`
  is not idle, its `offered` and `fileToMove` files, `CaptureShareCoordinator.request.url`, the preset
  export folder while `isExporting` and `exportFile` while its sheet shows. A child that equals an
  in-use path, or lies inside one, is kept; a folder that contains one is entered and its other
  children planned. Paths are compared after the same resolution as the roots.
- **Rationale**: Visible results (an offered recording, a share sheet) must never vanish; per-file
  rules let a leftover beside an offered recording go.
- **Scene archive export**: `SceneArchiveService` is not wired into the app yet (no in-use state); its
  folder is cleared like the others.

## R5 — Sizes and confirmation

- **Decision**: Each item's space used comes from FILE-009's walk rules (regular files, depth 32,
  100,000 entries per item); the confirmation shows the sum formatted like the Storage screen
  (`ByteCountFormatter`, `.file`), with "about" when a limit was reached.

## R6 — Threading

- **Decision**: `StorageUsageModel` runs plan and execute in `Task.detached(priority: .utility)`;
  Refresh and Clear are disabled while clearing; a refresh follows the clear. Leaving the screen does
  not cancel a running clear (it is short and stopping halfway is harmless but confusing).

## R7 — Fixture and acceptance

- **Decision**: The acceptance test builds a temporary container laid out with
  `StorageLocations.make(...)`, writes real user data through the app's own stores (`SceneAutosaveStore`
  twice for main + backup, `ShowStore` for a show with two scene snapshots, files for photo, video,
  presets, collections, audio, preferences), caches in all five folders, a leftover and an offered
  recording, and a link to the photo. After cleanup: byte comparison of every user file, the loaders
  read the scenes, caches are gone, the offered recording and the link target stay.
