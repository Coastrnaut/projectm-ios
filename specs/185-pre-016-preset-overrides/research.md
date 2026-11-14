# Research: PRE-016 Preset parameter overrides

## PRE-016-D1 — Text overlay, not an engine hook

- **Decision**: rewrite the preset bytes before `loadPresetData`.
- **Rationale**: projectM 4's C API (`projectM.h`, bridged by `PMBridge.h`) has no setter for a
  preset's initial values. Its `PresetFileParser::ParseLine` splits each line (on `\r` or `\n`) at the
  first space or `=`, lower-cases the key and keeps the **first** occurrence; `PresetState` reads the
  values with `GetFloat` (`std::stof`) and keeps built-in defaults for missing keys (`PresetState.hpp`:
  zoom 1, rot 0, warpAmount 1, decay 0.98, waveR/G/B 1, gammaAdj 2). So rewriting the first occurrence
  (or inserting one before any other) controls exactly what the engine starts from.
- **Alternatives**: an engine patch adding `projectm_set_preset_value` — needs an upstream PR and a
  fork pin move for something the format already expresses (Constitution VIII: minimize patches).
  Per-frame injection (`per_frame_1=zoom=…`) — changes code, alters per-frame semantics and can trip
  the ACC-002 screen; rejected.

## PRE-016-D2 — Overlay algorithm

- Scan lines exactly as the engine does (`\r` and `\n` both end a line; empty lines skipped).
- Key = bytes before the first space or `=`, ASCII lower-cased; delimiter at position 0 → no key.
- For each override, the first line whose key matches is replaced, from line start to line end, by
  `<canonical name>=<value>`; the line terminator is kept.
- Missing keys: one line each, in allow-list order, inserted after the first line that starts with `[`
  (the `[preset00]` header; a UTF-8 BOM allowed before it), else at byte 0. The inserted lines end with
  `\r\n` when the file contains `\r\n`, else `\n`.
- Value text: rounded to 4 decimals, `String(format: "%.4f")` (POSIX), trailing zeros and a bare `.`
  trimmed (`1.0500` → `1.05`, `1.0000` → `1`).
- Every other byte unchanged, so non-UTF-8 and CRLF files survive.

## PRE-016-D3 — Original values

`PresetTextOverlay.originalValues(_:)` returns each allowed parameter's value as the engine would read
it: the first matching line's value parsed like `stof` (leading spaces, optional sign, digits, `.`,
exponent; unparsable → default), else the engine default.

## PRE-016-D4 — Storage

`PresetCollections/overrides.json` beside PRE-007's collections and PRE-003's tags (one folder for
per-preset library data, so FILE-005 restore staging, FILE-011 erase, storage and UI-test reset treat
it alike). Version 1, FILE-007 limits (1 MiB, depth 4, 20,000 elements), lenient body (damaged
entries dropped and counted), newer version never interpreted or written, unreadable file set aside as
`overrides.unreadable.json`. Store modelled on `PresetTagStore`.

## PRE-016-D5 — Backup, restore, erase

- Optional backup record `collections/overrides.json`, no format version change (as PRE-003-D6: no
  shipped release reads FILE-005 backups).
- `LibraryRecords` key `preset-overrides`.
- Restore section `overrides`, key `overrides/<preset id>`; Keep both = the device's values plus the
  backup's other parameters (`.union`), Replace = the backup's set, Skip = the device's. A user preset
  added as a Keep-both copy carries its overrides to the derived ID (same as tags).
- FILE-011: the Collections category already removes the whole folder; its inventory count adds the
  presets with overrides. The category label stays "Collections, tags, favorites and history"
  (unchanged string; the folder's other contents are already summarised by it) — decision: no label
  change, to keep existing UI tests and translations stable; the erase dialog's count includes them.

## PRE-016-D6 — App integration

- `RendererPresetLoader.overrides: PresetOverrideStore?`; in `load`, when the preset has overrides,
  the original bytes (bundle file, archive or stored user copy) are overlaid and passed as `data`.
- `PresetOverridesCoordinator` (@Observable, main actor) holds the store, reads originals through the
  loader, saves on drag end, reloads the preset on screen via `PresetCoordinator.select`, announces
  through `presets.announceLibrary` (library lane).
- `PresetBrowserView` row menu: "Adjust Parameters…" for unlocked, playable presets → sheet.
- Thumbnails and warm-up keep original text (spec Clarification).
- Flash: no toggle (`bInvert`, `bBrighten`, …) is on the list; FX-019's envelope still runs on every
  frame; ACC-002's screen reads per-frame code, which the overlay never changes.
