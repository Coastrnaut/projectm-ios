# Data Model: PRE-001 Visual Thumbnail Cache

## PresetThumbnailSpec (value)

| Field | Value |
|---|---|
| width × height | 128 × 72 pixels |
| frames | 45 |
| sampleRate | 44,100 Hz |
| samplesPerFrame | 735 (stereo, interleaved) |
| seed | `0x5052_4531` |
| rendererVersion | 1 (bumped when any field or the drawing changes) |

## PresetThumbnailKey (value)

- `presetID` (String), `contentHash` (String, `IndexedPreset.hash`), `rendererVersion` (Int).
- `stableID`: first 32 hex digits of SHA-256 of `presetID + "\n" + contentHash + "\n" + rendererVersion`.
- `fileName`: `stableID + ".png"`.
- Rule: equal inputs → equal `stableID` (S6); any input differs → different `stableID`.

## PresetThumbnailIndex (file `index.json`)

| Field | Type | Rule |
|---|---|---|
| schemaVersion | Int | 1; above 1 → discarded |
| rendererVersion | Int | the version that wrote it (informational) |
| entries | {stableID: Entry} | |

Entry: `presetID`, `contentHash`, `rendererVersion`, `file`, `width`, `height`. An entry is valid only
when its `rendererVersion` is the current one and `file` exists in the folder.

### Open-time repair (states)

```text
missing ─────────────► empty
unreadable / newer ──► empty, all PNGs removed
older entries ───────► entries dropped, their files removed
missing file ────────► entry dropped
orphan PNG ──────────► file removed
(repaired) ──────────► saved
```

## Pending request (in memory)

`key`, `contents` loader, waiters (token → continuation). At most 32; newest served first.

## Session failures (in memory)

Set of stable IDs that failed with a non-`unavailable` error; never persisted.
