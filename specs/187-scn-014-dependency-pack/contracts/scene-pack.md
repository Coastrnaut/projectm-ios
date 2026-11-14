# Contract: Scene Pack (SCN-014)

## P1 Writer (SceneArchive)

`SceneArchiveWriter.write(document:media:slides:registry:modified:limits:sink:)` (and `data(...)`), `slides` default `[]`.
Refuses before any byte is written: FILE-001's refusals; a slide whose key is not the photo asset with a
slideshow, an index outside 1…N, a missing or repeated index (`slideMismatch(key)`); a slide failing the photo
content check; a manifest or scene string flagged by the path audit (`absolutePath(String)`). Writes
`scene.json`, the assets in key order, then the slides in index order, then `manifest.json` (`slides` only
when non-empty).

## P2 Reader (SceneArchive)

`SceneArchiveReader.read` returns `SceneArchiveContents.slides` in index order. Refuses: a `slides` record
with an invalid key, a key that is not the scene's photo asset, an index outside 1…20, a repeated index, a
path other than the exact one, a count different from the slideshow's identifier count; a listed slide file
missing (`missingAssetFile`); content not PNG/JPEG. All of PortableArchive's entry-name rules (absolute,
`..`, backslash, colon) and FILE-002 checksums apply first.

## P3 Path audit (SceneArchive)

`SceneArchivePathAudit.findings(inJSON: Data) -> [String]` lists every string (key or value) that is an
absolute location (research D2). Pure; Linux-compatible.

## P4 Library import (app)

- `ScenePackImporter.preview(at: URL) async -> ScenePackPreview` reads, verifies, derives identifiers,
  plans against the show; writes nothing outside its staging folder (removed).
- `ScenePackImporter.importPack(at: URL, preview:) async -> ScenePackImportOutcome`: refuses when the
  pack's SHA-256 differs from the preview's or the show changed (`changed`); stages, adopts (no current
  change), installs with Keep both, releases only new identifiers on failure.

## P5 UI (app)

- Scene Folders scene row: context menu "Export Scene…", leading swipe "Export", VoiceOver action
  "Export Scene" → share sheet with one `.pmscene` file; the file is removed when the sheet closes.
- Scene Folders actions: "Import Scene…" → file picker (`org.projectmios.scene-archive`) → preview sheet
  (`scenePackPreview`) with Import (`scenePackImport`) and Cancel; Import is disabled when refused or
  identical.
- Announcements (library lane): "Exported <name>.", "Imported <name> as cue <n>.", "<name> is already in the
  show.", or the refusal.
