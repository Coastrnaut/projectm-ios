# Contract: Media relinking (MED-013)

## L1 Registry (LocalPortability `ContentAddressedMediaFolder`)

- `release(ids)`: as FILE-008 M4, and every removed `references` entry is appended to `released`
  (replacing an older entry of the same identifier; at most 256, oldest dropped).
- `intern(_, as: id, _)`: as M1, and `id` is removed from `released`.
- `knownPayloadName(of: id) -> String?`: the `references` entry, else the `released` entry.
- `adoptKnown(_ ids: Set<UUID>) throws -> Set<UUID>`: for each `id` that does not resolve and whose
  known payload file exists: a `references` entry is written (moved out of `released`). Returns the
  adopted identifiers. One atomic registry write.
- `restorePayload(from: URL, wanted: Set<String>) throws -> String?`: hashes the source; when
  `<sha256>.<ext>` is in `wanted` and that payload is absent, copies the source to an incoming name,
  hashes the copy again and renames it to the payload name. Returns the payload name or nil. Never
  writes to the source.
- `forget(_ ids: Set<UUID>) throws`: removes them from `released`.

## L2 Folder scan (`MediaFolderScan.scan(root:wanted:extensions:limits:)`)

Read-only walk under the bounds of data-model.md; returns `matches` (payload name → file),
`visited`, `hashed`, `limitReached`. Hidden files, package contents and symbolic links are skipped.

## L3 Scene references (SceneFormat)

- `SceneDocument.mediaReferences: [SceneMediaReference]`: photo assets, their slideshow `storeIDs`,
  logo assets, video assets (sorted by asset key, role, position).
- `replacingMediaReference(store:from:to:) -> (document, replaced)`: every match in that store's roles
  replaced; every other field and unknown field kept verbatim.

## L4 Show store (ShowStorage)

- `mediaUsage() -> ShowMediaUsage`.
- `rewriteMediaReferences(store:from:to:fault:) throws(ShowMediaRewriteError) -> ShowMediaRewriteReport`:
  steps `stage` (write `.relink-new`), `keepOriginal` (SCN-013 backup), `link` (original →
  `.relink-old`), `commit` (rename new over the scene file), `cleanup`. A failure before cleanup leaves
  every scene file byte for byte as before and no temporary file.

## L5 App service (`MediaRelinkService`)

- `missingItems(cues:) -> [MissingMediaItem]` (sorted: photos then videos, then most scenes first).
- `relinkByChecksum(_ items) -> MediaRelinkReport`.
- `scanFolder(_ url, items) -> MediaRelinkReport` (security scope started and stopped here).
- `replace(_ item, with url) async throws(MediaRelinkError) -> MediaRelinkReport`.

## L6 UI

- Settings → Storage → "Missing Media" (`missingMediaLink`), screen title "Missing Media".
- Rows `missingMedia.<UUID>`: label "Photo" or "Video", value "used by N scenes, M cues[, checksum unknown]";
  button "Relink…" (`missingMediaRelink.<UUID>`) and VoiceOver action "Relink".
- Button "Find Missing Media in Folder…" (`missingMediaFind`); empty state "No missing media."
  (`missingMediaEmpty`); result text (`missingMediaResult`).
- Placeholder tile `missingMediaPlaceholder`: label "Missing media", value "<scene name>: its photo or
  video is no longer stored", button "Relink…" (`missingMediaPlaceholderRelink`).
