# Feature Specification: SCN-002 Scene Autosave

**Feature Branch**: `feature/scn-002` (spec directory `067-scn-002-scene-autosave`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SCN-002 (Scene autosave) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Debounce edits into crash-safe
atomic local saves." Acceptance, verbatim: "Kill app after edit and relaunch; last committed scene is
intact." P0, effort M, depends on SCN-001 (versioned scene format)."

Identifiers in this feature carry the roadmap ID: requirements `SCN-002-R1…`, success criteria
`SCN-002-S1…`, tasks `SCN-002-T01…`. Other features' IDs are cited as they are: SCN-001 (scene
document, canonical bytes, validation, live adapters; ADR-0028), MOD-001 (parameter registry and
restore semantics), MOD-002 (audio feature bindings), MOD-013 (per-edge modulation restore and
preserved edges), MED-001/MED-002 (stored photo and video), MED-009 (text overlay), FX-001 (glow),
VIS-001/VIS-002 (native spectra), CAM-001 (camera, session only), FILE-001 (scene archives).

## Baseline: what exists today (audit of 2026-11-13, commit `a462a64`)

| Area | Today | Gap for this row |
|---|---|---|
| Scene document | `SceneFormat` (SCN-001): canonical bytes, decode, validation, `SceneDocument(capturing:)` and `liveState` (with MOD-013's per-edge modulation restore). | None in the format. |
| Use in the app | Only FILE-001's `SceneArchiveService` (export and import of a given document). Nothing captures the live visual as a scene, nothing writes a scene to disk. | The app must capture what it shows as a scene and keep it on disk. |
| What the user edits | No scene editor exists. The user's edits are Settings changes to the shown visual: the visual choice, bar count, linear spectrum orientation and spacing, glow on/off, intensity, radius and threshold (registered MOD-001 parameters), the Text visual's message and style, the stored photo and video. | These edits must be captured and committed. |
| Persistence | Each setting is written to UserDefaults at once (AppSettings, TextOverlayStore, PhotoStore/VideoStore identifiers). No scene file, no backup, no corruption fallback. | A crash-safe, atomic, validated scene file with a fallback. |
| Restore | Settings are read back from UserDefaults at launch. | The last committed scene restores the visual's parameters, text and bindings on launch, never blocking launch on a bad file. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: When the committed scene and the individually saved settings disagree at launch (an edit was
  saved as a setting but not yet committed as a scene), which one is shown? → A: The committed scene
  (when it is valid): its values are applied over the settings, so a kill never shows a mix of
  committed and uncommitted state (SCN-002-R10). Settings stay where they are today (other features
  read them); closing Settings commits at once, so in normal use both agree.
- Q: How many earlier copies are kept, and how? → A: One backup, the previous committed scene: before
  a new main file replaces the old one, the old one is linked as the backup (the old backup removed
  first); the backup is never refreshed from a main file that failed to read. Two files bound the
  storage (2 × at most 1 MiB, in practice a few KB) and always leave one complete scene.
- Q: How hard does a commit push the bytes to storage? → A: The temporary file is flushed with a full
  storage flush (Apple's `F_FULLFSYNC`; plain `fsync` if that is refused) before the rename, and the
  folder is flushed after it. At most one commit per second keeps the cost (milliseconds, on a
  background queue) away from the frame loop. `Data.write(options: .atomic)` is not used: it renames
  but does not document a storage flush.
- Q: Does restoring a scene switch the stored photo or video when it refers to another one? → A: No.
  The stores keep a single current photo and video (MED-001/MED-002); a reference that is not the
  stored one is a `missingAsset` warning, kept in the document, and the stores are never changed by a
  restore. Switching stored media is FILE-001's import (all or nothing).
- Q: Where do the files live and are they backed up? → A: `Library/Application Support/Scenes`
  (`current.scene`, `current.scene.bak`, transient `current.scene.tmp`), private to the app and
  included in the user's own device backups like the stored photo and video. No file timestamps are
  read (required-reason API).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - My last committed look survives a crash or a forced quit (Priority: P1)

A performer adjusts the shown visual (for example the bar count or the glow, or the Text visual's
message), and the app is killed (crash, force quit, the system ending it). On the next launch the
visual comes back exactly as it was at the last commit: never a half-written mix, never a blank
default because a file was cut off.

**Why this priority**: This is the row's acceptance: "Kill app after edit and relaunch; last committed
scene is intact."

**Independent Test**: Make an edit, wait until it is committed, make a second edit and kill the app
before the second is committed; relaunch: the first edit is shown, complete.

**Acceptance Scenarios**:

1. **Given** an edit that was committed, **When** the app is killed and relaunched, **Then** the
   committed state is restored.
2. **Given** a committed edit followed by an uncommitted one, **When** the app is killed before the
   second commit, **Then** the relaunched app shows the first edit, not a mix of both and not the
   defaults.
3. **Given** a save that was interrupted after the new bytes were written but before they replaced the
   old file, **When** the app relaunches, **Then** the previous committed scene is restored.

### User Story 2 - Saving never gets in the way (Priority: P1)

Rapid edits (dragging a slider, typing a message) do not each cause a write. They are coalesced and
written in the background shortly after the user stops, and never on the frame loop, so the visual
stays smooth.

**Why this priority**: "Debounce edits" is the row's observable behavior.

**Independent Test**: With a controllable clock, a burst of edits produces one write after the quiet
period; continuous edits still produce a write within the maximum latency.

**Acceptance Scenarios**:

1. **Given** ten edits 0.1 s apart, **When** the user stops, **Then** exactly one write happens, 1 s
   after the last edit.
2. **Given** edits every 0.5 s without pause, **When** 5 s pass since the first unsaved edit, **Then**
   a write happens even though edits continue.
3. **Given** the user closes Settings, the visual changes, or the app goes to the background or is
   about to terminate, **When** an edit is pending, **Then** it is written at once.

### User Story 3 - A damaged file never stops the app (Priority: P2)

If the saved scene is damaged (cut off, edited by hand, from a newer app version), the app still
launches: it uses the previous good copy if there is one, otherwise the current settings, and
records a diagnostics event. It never crashes and never shows an error at launch.

**Why this priority**: Crash safety must include the read side.

**Independent Test**: Truncate the main file: the backup is used. Damage both: launch uses the
current settings and a diagnostics event is recorded.

**Acceptance Scenarios**:

1. **Given** a truncated or corrupt main file and a good backup, **When** the app launches, **Then**
   the backup's scene is restored and an event names the fallback.
2. **Given** both files damaged, **When** the app launches, **Then** nothing is restored, the current
   settings stay, an event is recorded, and the next commit writes a good file.
3. **Given** a scene from a newer app version, **When** the app launches, **Then** nothing is restored
   and the file is never overwritten by this version.

### User Story 4 - Content this version does not understand is kept (Priority: P3)

A scene written by a newer version (or imported later) contains layers, fields, bindings or
connections this version does not use. Autosaving keeps them instead of dropping them.

**Independent Test**: A saved scene with an unknown layer kind, an unknown document field and an
orphaned binding is restored; after the next edit the saved file still contains all three.

### Edge Cases

- The visual is projectM: the scene holds the parameters but no compositor layers; unknown layers
  from the restored document are still kept.
- The Camera visual (session only, CAM-001-R11): the scene records the visual chosen before Camera,
  never the camera.
- The stored photo or video is missing or was replaced: the reference is kept and reported as a
  warning; the store is never changed by a restore.
- No photo or video is stored while Photo or Video is chosen: that layer is left out (it shows
  nothing).
- An unknown layer's instance number equals one of the live layers': it is renumbered; more than 8
  layers in all: the extra unknown layers are dropped with an event.
- The disk is full or a write fails: the previous committed files stay; the next edit retries.
- A leftover temporary file from a killed save is removed at launch and never read.
- A restore does not count as an edit (no write just for launching).

## Requirements *(mandatory)*

### Functional Requirements

- **SCN-002-R1**: The app keeps one current scene: the layer stack of the chosen compositor visual,
  the values of the registered visual parameters the app holds, the text overlay of the Text visual,
  the stored photo or video reference of the Photo or Video visual, and the live audio feature
  bindings with the modulation section. The visual choice itself and every setting ADR-0028 excludes
  are never in it.
- **SCN-002-R2**: Edits are coalesced: a write happens 1 s after the last edit (quiet period) and at
  most 5 s after the first unsaved edit (maximum latency).
- **SCN-002-R3**: A pending edit is written at once when Settings closes, when the visual choice
  changes, when the app moves to the background and when it is about to terminate.
- **SCN-002-R4**: Capturing reads the current state on the main thread without touching the frame
  loop; encoding and writing run on a background queue, one write at a time, in edit order.
- **SCN-002-R5**: A write is atomic and durable: the bytes go to a temporary file in the same folder,
  are flushed to storage, and replace the main file by a rename; the folder is then flushed. At every
  moment at least one complete committed scene exists on disk once one was committed.
- **SCN-002-R6**: The previous committed scene is kept as a backup; a main file that could not be read
  at launch is never copied over the backup.
- **SCN-002-R7**: On launch the main file is read and validated with SCN-001's decoder and validation;
  if it is missing, damaged, too large, from a newer version or has errors, the backup is tried; if
  both fail, nothing is restored and the current settings stay. Each fallback records a diagnostics
  event; none is shown to the user and none blocks launch.
- **SCN-002-R8**: A restore applies the scene's parameter values with MOD-001 restore semantics
  (clamping, orphaned IDs reported, not applied), the text overlay, and the live bindings (MOD-013
  per-edge restore) to the visual; photo and video references are checked against the stores and a
  missing one is a warning, never a store change.
- **SCN-002-R9**: Content the app does not use is kept on the next save: unknown layers (at their
  position), unknown document fields, unknown assets, preserved (orphaned and rejected) bindings and
  connections, the modulation section, and the scene ID and name.
- **SCN-002-R10**: The committed scene is the one restored: after a kill, edits that were not yet
  committed are not restored, so the visual never shows a mix of committed and uncommitted state.
- **SCN-002-R11**: The scene files hold only what the user created or chose; no audio, no file paths,
  no device or account data. The privacy policy's list of stored data names them.
- **SCN-002-R12**: UI tests reset the scene files with the other stored state; a DEBUG-only probe
  reports the last committed revision so a test can wait for a commit.
- **SCN-002-R13**: The files are `current.scene` (main), `current.scene.bak` (backup) and a transient
  `current.scene.tmp` in `Library/Application Support/Scenes`; at most two committed copies exist.

### Key Entities

- **Current scene**: one SCN-001 document (scene ID created once, name "Current Scene").
- **Scene files**: the main file, its backup and a transient temporary file in one app-private folder.
- **Edit revision**: a counter of edits; the committed revision is the newest one written.
- **Autosave event**: a diagnostics record of a fallback, a failed write or dropped content.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SCN-002-S1**: In the kill-and-relaunch test, the relaunched app shows the last committed edit and
  never the uncommitted one (simulator UI test; on device, a force quit from the app switcher).
- **SCN-002-S2**: A save interrupted between writing and replacing leaves the previous scene readable
  in 100 % of the injected-failure cases tested.
- **SCN-002-S3**: A truncated or corrupt main file falls back to the backup, and two damaged files fall
  back to the current settings, in every case tested, with one event each and no crash.
- **SCN-002-S4**: A burst of edits produces exactly one write after the quiet period; continuous
  edits produce a write within the maximum latency (controllable clock).
- **SCN-002-S5**: Capture, save, load and restore give back the same scene (semantic equality), and
  unknown content survives a save.
- **SCN-002-S6**: Unit tests finish in about 1-2 s each; the UI test in under 30 s.

## Assumptions

- No scene editor or scene library exists yet; the "current scene" is the autosave target for the
  shown visual. The library (SCN-004…006), undo (SCN-010) and lock mode (SCN-015) build on it.
- UserDefaults keeps holding each setting as before (other features read it); the scene file is the
  committed record that wins on launch when valid.
- A force quit from the app switcher passes through the background first, so it commits pending
  edits; only a crash or a kill within the quiet period loses the newest edits.

## Scope

| In this row | Later rows |
|---|---|
| Current scene capture, debounce, atomic save with backup, validated load with fallback, restore, unknown content kept | Scene library, folders, tags, previews (SCN-004…006), duplicate and rename (SCN-003), undo (SCN-010), validation screen (SCN-012), migrations (SCN-013), lock mode (SCN-015), a modulation editor |
