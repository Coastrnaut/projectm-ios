# Data Model: REC-010 Recording library

- **RecordingLibraryFile** (scan result): `url`, `name` (file name), `bytes: Int64` (file size), `date: Date` (modification date). Identity: `name` (unique in the folder). Order: `date` descending, then `name` descending.
- **RecordingFacts** (header read): `durationSeconds`, `width`, `height`, `framesPerSecond`, `codec` (four-character code, e.g. "hvc1", "avc1"). Absent → the file is Incomplete.
- **RecordingLibraryItem** (row): file + `state`: `.loading`, `.ready(RecordingFacts)`, `.incomplete`. Actions: ready → Play, Share, Rename, Delete; incomplete or loading → Delete.
- **Thumbnail cache entry**: key `<name>.<bytes>`; memory dictionary and `Caches/RecordingThumbnails/<key>.jpg`. Removed on delete and rename of its file.
- **Delete confirmation**: the item awaiting confirmation (`pendingDelete`); Cancel clears it, Delete removes file, row, cache entry.
- **Totals**: `count`, `totalBytes` = sum of listed file sizes; FILE-009 "Saved recordings" measures the same folder.

State transitions: offered (tmp) → Keep → saved (library) → Delete → gone; saved → Rename → saved (new name, new cache key).
