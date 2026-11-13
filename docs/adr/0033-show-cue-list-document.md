# ADR-0033: Show Cue List Document, Version 1

- **Status**: Accepted 2026-11-13 (decided by Claude under the owner's best-judgement rule, owner
  rule 4)
- **Feature**: SHOW-001 (`specs/069-show-001-manual-cue-list`)
- **Constitution**: I (public APIs), VI (modular boundaries), VII (nothing on the audio path), X
  (evidence); Privacy (local only)
- **Builds on**: ADR-0028 (scene document), ADR-0023 decision 8 and SHOW-014 (output blackout)
- **Number**: 0031 is left free and 0032 is PERF-010's (parallel work); 0015, 0016, 0025 and 0026
  stay unused.

## Context

SHOW-001 asks to "arrange scenes into a sequential show with next and previous controls", accepted
when a "five-cue list advances deterministically and preserves scene IDs". There is no scene library
yet (SCN-004 to SCN-006 are later rows) and SCN-002's current-scene autosave was not integrated when
this was written. Later rows drive the same list: timed and beat advance (SHOW-002, SHOW-003),
transition overrides (SHOW-004), hold and skip (SHOW-005), notes (SHOW-012), OSC cue sync (OSC-012).

## Decisions

1. **Package.** `Packages/ShowControl`: target `ShowControl` (the pure model, Foundation only) and
   `ShowStorage` (the folder store, on SceneFormat). One library product. Builds and tests on Linux.
   `PerformanceControl` (OSC, tempo) gets no scene dependency; OSC-012 will depend on `ShowControl`.
2. **Document.** `show.json`: `format` "projectm-ios.show", `version` 1, `id`, `name`, ordered
   `cues` (`id`, `scene`, `label`), `position` (the active cue ID, or null for Standby). JSON with
   sorted keys; written whole. A newer version, a file over 1 MiB, more than 256 cues, duplicate cue
   IDs, non-canonical UUIDs or a bad label refuse the whole file, which is set aside as
   `show.damaged-<n>.json` and never deleted; a dangling position is Standby.
3. **Scene references.** Cues refer to scenes by SCN-001 scene ID. Each scene the show uses is stored
   next to it as canonical SCN-001 bytes, `Scenes/<scene ID>.scene.json`, whose document `id` must
   equal the name (otherwise treated as missing). "Add Current Scene" stores a snapshot with a new
   scene ID. Scenes are written before the show that refers to them; scene files no cue refers to are
   removed after the show is saved. A missing, unreadable or invalid scene is flagged on its cue,
   never fatal for the show.
4. **Stepping.** Next: Standby → cue 1, n → n + 1, the last cue → nothing (no wrap). Previous: n →
   n − 1, cue 1 and Standby → nothing. Go to: any cue (the active one shows again). The position is a
   cue ID, so it survives reorder; deleting the active cue stands on the cue before it (Standby if it
   was first) without applying. The model reads only its cues and position: no clock, no randomness.
5. **Applying.** A step that moves reads, validates (SCN-001 `liveState`) and applies the cue's
   scene through the same settings Settings changes (visual, spectrum options, glow, text) and the
   coordinator's existing visual switch; the audio source is never touched and a cue never selects
   Camera. A scene that cannot be shown leaves the output unchanged with a notice; the show still
   moves (a skip would break the operator's count). While blacked out the OUT-010 cover keeps the
   output black. The cue is not applied again at launch.
6. **Controls.** A show row in the visualizer's controls; Right Arrow / Page Down and Left Arrow /
   Page Up on the visualizer (B stays SHOW-014's); an editor in Settings → Show.

## Follow-ups

- **SCN-002**: the app's scene capture and restore here (`ShowSceneSnapshot`, same layer mapping and
  seven MOD-001 values as SCN-002's `SceneAutosaveCapture`) is a minimal path because SCN-002 was not
  integrated; unify them into one capture/restore once it is.
- **Scene library (SCN-004 to SCN-006)**: resolve a scene ID in the library first and the show folder
  second, then move folder scenes into the library without changing their IDs.
- **Photo and video**: the app stores one photo and one video (MED-001, MED-002), referenced by store
  ID; a cue whose photo was replaced shows the current one with a notice until stores keep several.

## Amendment 2026-11-13 (SCN-003, duplicate and rename)

Decided under the owner's standing approval (owner rule 4); specs/074-scn-003-scene-duplicate-and-rename.
No default is overridden.

- **Actions.** Settings → Show offers, per cue, Duplicate Scene (`ShowStore.duplicateScene`: the copy
  under a new scene ID is written whole, never over an existing file, then a cue "<label> copy" is
  inserted right after its source with `ShowCueList.insert(after:)` and the show saved) and Rename
  Scene… (`ShowStore.renameScene`: the scene file is rewritten whole under the same ID; `show.json` is
  not touched). SHOW-001's Rename… stays the cue label. Neither applies anything or moves the position.
  A full show (256 cues) or an unreadable scene is refused before any file is written.
- **References.** Cue → scene by ID: a rename keeps every cue's reference (all cues showing a scene see
  its new name); a duplicate leaves existing cues on the original. Deleting the original's last cue
  removes only its file (decision 3's cleanup); the copy is independent.
- **Media.** Scenes share the stored photo and video by store ID; nothing is copied and nothing is
  counted in a file. `ShowStore.referencedMediaIDs()` reads the stored scenes and lists every photo and
  video ID they name. Removing a scene file never deletes media. Obligations for later rows: FILE-010
  (cache cleanup) never deletes stored photos or videos; FILE-011 (erase) consults
  `referencedMediaIDs()` (and the library's equivalent) before deleting media a remaining scene names.
  Replacing the stored photo or video (MED-001-R6) is unchanged: every scene naming the old one shows
  the "no longer stored" notice.
- **Editor.** A row whose scene name differs from its label shows "Scene: <name>", and VoiceOver
  appends ", scene <name>" to the value.

## Consequences

- Deterministic stepping is provable by unit tests on any platform (`ShowAcceptanceTests`,
  `ShowPropertyTests`); scene IDs are preserved byte for byte (`ShowStoreTests`).
- The show file stays small (rewritten on every step for the position); scenes are written once.
- No transitions: a cue switches the look instantly (SCN-007, SHOW-004 later).
