# Data Model: SCN-011 Scene Template Gallery

## manifest.json (bundled, read-only)

| Field | Type | Rule |
|---|---|---|
| `format` | string | `projectm-ios.scene-templates` |
| `version` | int | 1 (other versions: the catalog offers nothing) |
| `templates` | array | display order; IDs unique |

**Template**: `id` (lowercase slug, unique), `name` (1…120), `summary` (description, 1…200), `symbol` (SF Symbol name), `tags` (SCN-005 tags, e.g. `["template"]`), `scenes` (1…8).

**Template scene**: `file` (`<name>.scene.json` in the same folder), `label` (cue label 1…80), `transition` (optional: `type` `cut`/`crossfade`/`dipToBlack`, `seconds` 0…10), `assets` (array of asset records).

**Asset record**: `key` (the scene's asset key), `kind` (asset type), `source` (sentence), `licence` (SPDX, must be `MIT`).

## Template scene file

An SCN-001 document (format `projectm-ios.scene`, version 1) with layer kinds only `spectrum.circular`, `spectrum.linear`, `text`; assets only `text` (system font); parameters only the seven app-held values.

## Copy (in the show store)

Same content as the template scene with a new canonical uppercase UUID `id`, stored as `Scenes/<ID>.scene.json`; one cue per template scene appended; tag "template"; no folder.
