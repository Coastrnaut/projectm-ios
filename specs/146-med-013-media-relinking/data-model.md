# Data Model: MED-013 Media Asset Relinking

## Registry file (`references.json`, FILE-008, format `org.projectmios.media-references` version 1)

```json
{"format": "org.projectmios.media-references", "version": 1,
 "references": [{"id": "<UUID>", "payload": "<sha256>.<ext>"}],
 "released": [{"id": "<UUID>", "payload": "<sha256>.<ext>"}]}
```

- `released` (new, optional, omitted when empty): identifiers released from `references`, oldest first,
  at most 256 (oldest dropped), no identifier also in `references`. Names only: it never keeps a
  payload. Invalid entries are dropped when read.

## SceneMediaReference (SceneFormat)

| Field | Meaning |
|---|---|
| `store` | `photos` (photo, slide, logo) or `videos` (video) |
| `role` | `photo`, `slide`, `logo`, `video` |
| `assetKey` | the scene asset key |
| `storeID` | canonical UUID text |

## ShowMediaUsage (ShowStorage)

- `scenes[MediaKey] → Set<sceneID>` for every readable stored scene; `unreadableScenes` count.
- `MediaKey = (store, storeID)`.

## ShowMediaRewriteReport (ShowStorage)

`scenes` (IDs rewritten), `references` (count replaced), `unreadable` (scenes skipped).

## MissingMediaItem (app)

`store`, `id` (UUID), `sceneIDs`, `cueCount`, `checksumKnown`, `title` ("Photo 1A2B3C4D"), VoiceOver value.

## MediaRelinkReport (app)

`relinked` (identifiers resolved again), `scenes`, `cues`, `references`, `unreadableScenes`,
`contentDiffers`, `scan` (visited, hashed, limitReached) — rendered as one sentence.

## Folder scan limits

| Limit | Value |
|---|---|
| Entries visited | 5,000 |
| Depth | 4 |
| Files hashed | 1,000 |
| Bytes hashed in total | 4 GiB |
| Per file | the store's import limit: photos 40 MiB, videos 500 MiB |
