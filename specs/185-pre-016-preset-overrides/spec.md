# Feature Specification: PRE-016 Preset parameter overrides

**Feature Branch**: `feature/pre-016` (spec directory `185-pre-016-preset-overrides`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row PRE-016 (`docs/FEATURE_ROADMAP_AUTONOMOUS.md`, PRE table), verbatim: "Store
user-adjusted visual parameters as overlay data." Acceptance, verbatim: "Overrides apply on load and
reset restores original values." Priority P1, effort L, depends on PRE-015 (integrated).

**ID convention**: requirements `PRE-016-R1…`, success criteria `PRE-016-S1…`, tasks `PRE-016-T01…`.
`PRE-012-…` cites `specs/008-pre-012-preset-import-validation/spec.md`, `PRE-015-…` cites
`specs/010-pre-015-user-preset-duplication/spec.md`, `PRE-003-…` cites `specs/149-pre-003-preset-tags/`,
`FILE-005-…` cites `specs/114-file-005-local-library-backup/`, `FILE-011-…` cites
`specs/120-file-011-local-data-erase/`.

## What already exists (audit of HEAD `11cf8cd0`, 2026-11-14)

| Area | What HEAD does | Evidence | Gap |
|---|---|---|---|
| PRE-015 | Duplicates a bundled preset into My Presets and edits the copy's whole text in a text editor; every save is checked statically and in an off-screen engine. No parameter is shown or adjusted by name. | `UserPresetEditing.swift`, `UserPresetsCoordinator`, `PresetBrowserView.menuItems` | No way to adjust a named value without editing text, and no way for a bundled preset at all. |
| Loading | `RendererPresetLoader.load` hands the engine an Included preset's bundle file path, a pack preset's bytes from `PresetArchive.bin`, or an imported preset's stored bytes. | `AppCoordinator.swift` (`RendererPresetLoader`) | No hook between the bytes and the engine. |
| Engine API | The bridge exposes `loadPresetAtPath` / `loadPresetData` only; projectM 4's C API has no setter for a preset's initial values. The engine's file parser takes `key=value` lines, keys case-insensitive and ending at the first space or `=`, **first occurrence wins**; missing keys keep built-in defaults (zoom 1, rot 0, warp 1, fDecay 0.98, wave_r/g/b 1, fGammaAdj 2). | `PMBridge.h`, `Vendor/projectM/.../PresetFileParser.cpp`, `PresetState.cpp/.hpp` | A text-level overlay is possible without any engine change. |
| Per-preset JSON records | PRE-003 keeps per-preset data (tags) in `PresetCollections/tags.json`, versioned, FILE-007 bounded, backed up by FILE-005 as an optional record, erased by FILE-011's Collections category, wiped by `-uitestResetNotice`. | `PresetTagsFile`, `PresetTagStore`, `LibraryBackupArchive`, `LibraryRestorePlan.planTags` | The pattern to follow. |
| Flash guard | ACC-002 screens per-frame code text (not initial values); FX-019's envelope limits every rendered frame whatever the preset. | `PresetFlashRisk.swift`, ADR-0011 | Applies unchanged to an adjusted preset. |

## Clarifications

### Session 2026-11-14

Answered under the standing delegation (owner rule 4; recommended option first). Each answer is
the conservative, local-first choice.

- Q: Engine hook or text overlay? → A: Text overlay, no engine change. Before the bytes reach the
  engine, each overridden parameter's first `key=value` line is rewritten (or, when absent, a line is
  inserted right after the `[preset00]` header), so it is the occurrence the engine reads. The bundled
  file, archive and stored user preset are never written. (Rejected: a new engine setter, which needs
  an upstream patch for something the file format already expresses.) Applied in R5-R7.
- Q: Which parameters may be overridden? → A: Eight initial values: `zoom`, `rot`, `warp`, `fDecay`,
  `wave_r`, `wave_g`, `wave_b`, `fGammaAdj` (brightness), each with a fixed safe range. Any other name
  is rejected. Applied in R2, R3.
- Q: Out-of-range values? → A: Clamped to the range; non-finite values are rejected. Applied in R3.
- Q: Where are overrides stored, backed up and erased? → A: `Application Support/PresetCollections/
  overrides.json` beside the tags (version 1, FILE-007 limits), backed up by FILE-005 as the optional
  record `collections/overrides.json` (no backup version change, like PRE-003), erased by FILE-011's
  "Collections, tags, favorites and history" category (the whole folder is erased), wiped by
  `-uitestResetNotice`. No UserDefaults key. Applied in R8-R11.
- Q: Per-frame code that assigns the same variable every frame? → A: The override sets the
  **initial value**; per-frame code still runs as written, so a preset that recomputes `zoom` each
  frame may look unchanged. The sheet says so. Overrides never rewrite code. Applied in R6, R13.
- Q: Which presets can be adjusted? → A: Any playable preset (Included, unlocked pack, playable
  user preset). A locked preset offers the purchase instead (FR-106). Applied in R12.
- Q: Thumbnails and the warm-up? → A: They keep using the original text (a thumbnail shows the
  preset as shipped); only the visible load applies overrides. Applied in R7.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Adjust a preset's look (Priority: P1)

A user likes a preset but wants it slower or darker. From the preset's touch-and-hold menu they
choose "Adjust Parameters…". A sheet lists the adjustable values with the preset's original value
and a slider each. Moving a slider stores the change and, when that preset is on screen, reloads it
with the change. The next time the preset loads (by tap, Next, Random, or after a relaunch) it
loads adjusted. The preset's own file is never changed.

**Independent Test**: override two values of a fixture preset; the text handed to the engine carries
the new values; the source bytes are identical before and after.

**Acceptance Scenarios**:

1. **Given** a playable preset with `zoom=1.000` and `fDecay=0.980`, **When** the user sets zoom to
   1.05 and decay to 0.95, **Then** the preset loads with `zoom=1.05` and `fDecay=0.95` and its file is
   byte-identical.
2. **Given** overrides were saved, **When** the app is relaunched and the preset loads, **Then** the
   overrides still apply.
3. **Given** a preset without a `wave_r` line, **When** wave red is overridden, **Then** a `wave_r` line
   is added so the engine reads it.

### User Story 2 - Reset to original (Priority: P1)

The sheet's "Reset to Original" removes every override of that preset and reloads it if it is on
screen; the values shown return to the original ones, and the preset loads from exactly its original
bytes.

**Acceptance Scenarios**:

1. **Given** a preset with overrides, **When** the user taps Reset to Original, **Then** the overrides
   are removed, the change is announced, and the next load uses the original bytes exactly.
2. **Given** one adjusted parameter, **When** the user resets it alone (its row's reset), **Then** only
   that override is removed.

### User Story 3 - Overrides travel with the library (Priority: P2)

A library backup includes the overrides; a restore brings them back; erasing Collections removes
them.

**Acceptance Scenarios**:

1. **Given** overrides, **When** the library is backed up and restored onto an empty library, **Then**
   the same overrides exist.
2. **Given** overrides, **When** the user erases "Collections, tags, favorites and history", **Then** no
   override remains.

### Edge Cases

- Parameter name not on the list (for example `bInvert`), or a non-finite value: rejected, nothing
  stored.
- Value outside the range: clamped (zoom 3.0 → 1.2).
- The file has the key twice: only the first occurrence (the one the engine reads) is rewritten.
- Key written in another case (`Zoom=`): matched without regard to case, rewritten in place.
- CRLF line endings or non-UTF-8 bytes: every other byte is kept as it was; inserted lines use the
  file's line ending.
- An override equal to the original value: still stored (the user chose it) until reset.
- A user preset is removed: its overrides are removed with it (as its tags are, PRE-003-R7).
- Saved overrides from a newer app version: shown as unavailable, never interpreted or overwritten.
- Unreadable overrides file: set aside (one copy kept), never deleted.
- More than 20,000 presets with overrides, or a file over 1 MiB: the change is refused.

## Requirements *(mandatory)*

### Functional Requirements

- **PRE-016-R1**: The app MUST store, per preset ID, a set of parameter overrides as local overlay
  data, separate from every preset file.
- **PRE-016-R2**: Only these parameters MUST be accepted, with these ranges: zoom 0.8-1.2, rot
  -0.2-0.2, warp 0-2, fDecay 0.9-1.0, wave_r/wave_g/wave_b 0-1, fGammaAdj 1-3. Names match without
  regard to case and are stored in this spelling.
- **PRE-016-R3**: A value outside its range MUST be clamped to it; a non-finite value or an unknown
  name MUST be rejected with nothing stored.
- **PRE-016-R4**: Every change MUST be saved before it is shown; a refused change or failed save MUST
  leave memory and disk unchanged.
- **PRE-016-R5**: When a preset with overrides loads for display, the engine MUST receive the
  preset's bytes with each overridden parameter's first `key=value` line set to the override, or a
  new line inserted after the `[preset00]` header (else at the start) when the key is absent.
- **PRE-016-R6**: The overlay MUST change no other byte of the text, and MUST NOT rewrite per-frame,
  per-pixel or shader code.
- **PRE-016-R7**: Bundled files, the pack archive and stored user-preset files MUST never be
  written. A preset without overrides MUST load exactly as before; thumbnails and the warm-up keep
  the original text.
- **PRE-016-R8**: The overrides document MUST be versioned (version 1), bounded (1 MiB, FILE-007
  limits), read leniently (damaged entries dropped and counted), a newer version never interpreted
  or written, an unreadable file set aside.
- **PRE-016-R9**: FILE-005 backups MUST include the overrides as an optional record; restore MUST
  plan them per preset (Keep both keeps the device's values for parameters both set and adds the
  backup's others, Replace takes the backup's set, Skip keeps the device's).
- **PRE-016-R10**: FILE-011's Collections category MUST erase the overrides and count each preset
  with overrides in its inventory.
- **PRE-016-R11**: `-uitestResetNotice` MUST start UI tests without overrides.
- **PRE-016-R12**: Every playable preset's touch-and-hold menu MUST offer "Adjust Parameters…",
  opening a sheet with one slider per allowed parameter (the ACC-005 accessible parameter helper),
  each showing the current value and the original value, a per-row reset, and "Reset to Original".
- **PRE-016-R13**: The sheet MUST say that adjustments set starting values and that the preset's own
  code may still change them.
- **PRE-016-R14**: Each change and reset MUST be announced on the announcer's library lane; a change
  to the preset on screen MUST reload it so it looks adjusted.
- **PRE-016-R15**: "Reset to Original" MUST remove every override of the preset; its next load MUST
  hand the engine its original bytes exactly.
- **PRE-016-R16**: Removing a user preset MUST remove its overrides.
- **PRE-016-R17**: The flash guard (FX-019 envelope; ACC-002 Reduce flashing) MUST apply to an
  adjusted preset as to any preset; overrides cannot turn on a whole-frame toggle (no toggle is on the
  list).

### Key Entities

- **Parameter override set**: preset ID → { parameter name → value }, values within their ranges.
- **Override parameter**: name, range, step, engine default, display label.
- **Overrides document**: `{ "schemaVersion": 1, "overrides": { "<preset ID>": { "zoom": 1.05 } } }`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **PRE-016-S1**: For a fixture preset with 3 overridden parameters, the loaded text carries the 3
  overridden values and the source bytes are byte-identical (acceptance test).
- **PRE-016-S2**: After Reset to Original, the loaded bytes equal the original bytes exactly, and the
  shown value equals the original value (acceptance test and UI test).
- **PRE-016-S3**: Overrides saved before a relaunch apply after it (acceptance test, new store over the
  same folder).
- **PRE-016-S4**: 100% of unknown names and non-finite values are refused; 100% of out-of-range values
  are stored clamped (unit tests).
- **PRE-016-S5**: A backup and restore onto an empty library gives the same overrides (round-trip test).
- **PRE-016-S6**: A user adjusts one parameter and resets it in under 30 s of UI-test time.

## Assumptions

- Overrides affect what the engine starts from; per-frame code is not analysed.
- Values are written with up to 4 decimals in the POSIX locale (the engine parses them with `stof`).
- Thumbnails and FILE-003 snapshots are unaffected.
- Simulator results are not device evidence; the feature changes no capture or performance path.
