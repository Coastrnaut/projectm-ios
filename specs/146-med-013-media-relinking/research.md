# Research: MED-013 Media Asset Relinking

Decisions taken by Claude under owner rules 4 and 9 (conservative, local-first), 2026-11-14.

## MED-013-D1: What content addressing already gives

- **Decision**: Use FILE-008's registry as the checksum index. An identifier whose registry entry still
  names `<sha256>.<ext>` resolves again as soon as that payload exists; `intern` recreates it when the
  same bytes are imported again. No new lookup is needed for that case.
- **Gap found**: `release` deletes the entry, so the hash of an identifier that a new current photo,
  Remove or a scenes-only erase released is lost; scenes that name it cannot be matched by checksum.
- **Decision**: `references.json` gains an optional key `released` (ordered `{id, payload}` list, at most
  256, oldest dropped, same format version 1). `release` appends the entries it removes; `intern` and
  adoption drop an identifier from it; `forget` removes identifiers (FILE-011). Older readers ignore the
  key (Codable ignores unknown keys) and drop it on their next write, which only loses relink hints.
- **Rejected**: a separate `checksums.json` (every test and backup that lists the folder would see a
  new file); hashes as identifiers (ADR-0043 rejected it); keeping released payloads alive (changes
  ADR-0043's space rules).

## MED-013-D2: When a checksum match is applied

- **Decision**: `adoptKnown(ids)` re-registers each missing identifier whose known payload exists. The
  app calls it with the missing identifiers after every photo and video import (the stores' change
  callbacks) and when the Missing Media screen opens or refreshes. Only identifiers that saved scenes
  name are adopted, so unrelated released references are not resurrected.

## MED-013-D3: Folder scan

- **Decision**: `MediaFolderScan` (LocalPortability, Foundation only) walks a picked folder with
  `FileManager.enumerator` (skip hidden files and package contents; symbolic links are not followed),
  bounded: 5,000 entries visited, depth 4, 1,000 files hashed, per-file size limit (the store's import
  limit: 40 MiB photos, 500 MiB videos), 4 GiB hashed in total; stops when every wanted hash was found.
  Only files with a store's extensions (`png`, `jpg`, `jpeg`, `mov`) are hashed. A match is copied into
  the store with `restorePayload`, which hashes the copy again before renaming it into place.
- **Rejected**: matching by file name (a name is no proof of content); sanitizing every candidate before
  hashing (expensive, and a sanitized original only equals the stored copy when the sanitizer is
  deterministic, which a normal re-import covers anyway).

## MED-013-D4: Replacement rewrite, all or nothing

- **Decision**: `ShowStore.rewriteMediaReferences(store:from:to:)` (ShowStorage) decodes every stored
  scene, rewrites the matching references in memory (`SceneDocument.replacingMediaReference`, SCN-001
  canonical bytes), writes each new file as `<id>.scene.json.relink-new`, keeps SCN-013's original
  backup, then per scene links the original to `<id>.scene.json.relink-old` and renames the new file
  over it. Any failure renames the kept originals back and removes the temporary files. After success
  the kept originals are removed. A test hook can fail any step.
- **Order**: stage the replacement copy in the store → rewrite scenes → rewrite settings values. A
  failure in the scene rewrite discards the staged copy; settings are untouched.
- **Rejected**: aliasing the old identifier to the new payload in the registry (the acceptance asks the
  scenes to name the new identifier; an alias would also hide that the content differs).

## MED-013-D5: Placeholder

- **Decision**: A small SwiftUI tile in the visualizer's banner stack ("Missing media", the scene name,
  Relink…), set when a show cue applies a scene with `missingAsset` warnings and cleared when the next
  scene has none or the media resolves after a relink. It is an accessibility element with a label and
  value. The compositor is not changed (other rows edit it in parallel; the layer already draws nothing
  for missing media).

## MED-013-D6: Scope of references

- **Decision**: Saved scenes (SHOW-001) are the durable references: photo assets, slideshow slides,
  logo assets and video assets. The settings values are rewritten on replacement when they still name
  the old identifier; they are not listed (they clean themselves on read). The scene autosave and
  history hold the live look (current media) and are not rewritten. Imported audio has no scene
  references (AUD-001), so nothing is relinked there.
