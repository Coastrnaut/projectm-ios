# Contract: REC-002 batch export

## B1 — Naming (`SnapshotBatchNaming`)

- `safeName("Dawn/Dusk") == "Dawn-Dusk"`, `safeName("🌅🌅") == "Snapshot"`, `safeName("Sunset 🌅") == "Sunset"`, `safeName("...") == "Snapshot"`, `safeName("Été  (live)") == "Été (live)"`.
- `fileNames(["A", "a"])` → `["01-A.png", "02-a.png"]`; at most 48 characters of name.

## B2 — Job capture

- Values = live values overlaid with the snapshot plan's writes; unusable snapshots are not selectable; unknown parameters skipped.
- Refused: no selection, a non-native visual (`unsupportedMessage`), Compare active ("Finish Compare first."), a batch rendering.

## B3 — Rendering

- `SnapshotStillRenderer.render(job:item:) -> Data` (PNG of exactly the job's size, opaque); same inputs → same bytes.

## B4 — Coordinator

- `start(selection:size:)`, `cancel()`, `done()`; `phase`, `progressText` ("Rendering 2 of 5"), `files`.
- Cancel or failure: the batch folder does not exist afterwards; `files` empty.
- Never calls the snapshot coordinator's `write`, `store`, the autosave or the history.
- Announces "Exported N images" / "Export cancelled" / "Export failed" on the library lane.

## B5 — UI identifiers

`snapshotBatchOpen` (row), `snapshotBatchSheet`, `snapshotBatchToggle.<index>`, `snapshotBatchSize`,
`snapshotBatchExport`, `snapshotBatchCancel`, `snapshotBatchStatus`, `snapshotBatchSave`, `snapshotBatchShare`,
`snapshotBatchPhotos`, `snapshotBatchDone`; DEBUG `snapshotBatchProbe` (file names and PNG sizes, "|"-separated).
