# Data Model: SCN-014 Scene Dependency Pack

## Scene pack (`.pmscene`, FILE-001 format version 1)

| Entry | Content |
|---|---|
| `manifest.json` | `format`, `formatVersion` 1, `files` (path, length, SHA-256), `scene` = `scene.json`, `assets` (key, type, path), **`slides` (optional, SCN-014)** |
| `scene.json` | SCN-001 canonical scene; media named by store UUIDs of the exporting device |
| `assets/<key>.<ext>` | photo (`png`/`jpg`), video (`mov`), logo (`png`) |
| `assets/<key>-slide-<NN>.<ext>` | slideshow picture NN (01…20) of photo asset `key` (`png`/`jpg`) |

## Slide record (manifest `slides[]`)

- `key`: the photo asset's key (must be the scene's photo asset with a slideshow).
- `index`: 1…N, consecutive, N = the slideshow's identifier count (≤ 20).
- `path`: exactly `assets/<key>-slide-<NN>.<ext>`, NN = index with two digits.

## Pack preview (app, `ScenePackPreview`)

- `archiveSHA256`, `sceneName`, media counts (photo, slides, logo, video), `totalBytes`.
- `remapped`: the scene with the derived identifiers (SCN-014-D3).
- `showPlan`: FILE-004 plan for `[remapped]` (kind: new, identical, conflict → copy).
- `repairEntries`: SCN-012 entries for `remapped` against the stores plus the pack's media.
- `licenses`: always empty.
- `refusal`: why the pack cannot be imported (then the rest is empty).

## Import outcome

- `installed(cue label, scene name)`, `alreadyInShow`, `refused(message)`.
