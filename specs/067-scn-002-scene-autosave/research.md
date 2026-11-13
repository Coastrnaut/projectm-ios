# Research: SCN-002 Scene Autosave

Decided by Claude under the owner's standing approval (owner rule 4), conservative and local-first.

## SCN-002-D1: What is the "current scene", and where does the code live?

- **Decision**: one autosaved document for the shown visual. Layers: the stack the chosen compositor
  visual builds (bottom first): Circular Spectrum `[spectrum.circular]`, Linear Spectrum
  `[spectrum.linear]`, Photo `[photo, spectrum.circular]` (photo left out when none is stored), Video
  `[video, spectrum.circular]` (likewise), Text `[spectrum.circular, text]`, projectM `[]` (the engine is
  not a compositor layer). Camera is session only (CAM-001-R11): the scene records the visual chosen
  before Camera. Parameters: the registered values the app holds (`visual.circularSpectrum.barCount`,
  `visual.linearSpectrum.orientation`, `visual.linearSpectrum.spacing`, `effect.bloom.enabled`,
  `…intensity`, `…radius`, `…threshold`). Assets: `photo`, `video` (store UUIDs), `text` (the MED-009
  stored JSON, embedded). Bindings: the native spectrum's live MOD-002 bindings. Scene ID: a UUID made
  on the first save, kept; name "Current Scene". The visual choice stays a setting (ADR-0028 decision 8).
  The code lives in the app: it reads AppSettings, the text, photo and video coordinators and the native
  host; only `SceneJSON.parse` is added to SceneFormat.
- **Rationale**: these are the edits a user can make today; the stacks match the hosts' fixed stacks.
- **Later rows**: the scene library (SCN-004…006) saves named copies of this document; undo (SCN-010)
  keeps a command history over the same capture; SCN-003 duplicates it under a new ID; SCN-015 locks
  edits (the autosave then sees none).
- **Alternatives**: a new package (more CI and project churn for code that needs app types); capturing
  the hosts' compositors directly (needs Metal; same stacks).

## SCN-002-D2: Which wins at launch, the scene or the settings?

- **Decision**: a valid committed scene is applied over the settings (parameters through a scratch
  `ParameterStore.restore`, so MOD-001 clamping applies; then written to AppSettings; the text spec to
  `TextOverlayCoordinator`). Settings keep their UserDefaults keys; closing Settings commits at once.
- **Rationale**: the acceptance ("last committed scene is intact") and SCN-002-R10: never a mix.
- **Alternatives**: settings win (the scene would be write-only, the acceptance untestable); stop
  writing settings (touches every feature that reads them).

## SCN-002-D3: Debounce numbers

- **Decision**: quiet period 1 s after the last edit, maximum latency 5 s after the first unsaved edit;
  at once on a visual change, Settings closing, background and terminate. DEBUG launch arguments
  `-uitestSceneAutosaveQuiet <s>` and `-uitestSceneAutosaveMaxLatency <s>` lengthen them so the UI test
  can kill the app before a commit deterministically.
- **Rationale**: a slider drag or typing produces one write per pause; a continuous drag still commits
  every 5 s; at most one F_FULLFSYNC per second.

## SCN-002-D4: Atomic and durable write

- **Decision**: POSIX: `open(tmp, O_WRONLY|O_CREAT|O_TRUNC, 0600)`, `write` loop, `fcntl(F_FULLFSYNC)`
  (fallback `fsync`), `close`; `unlink(bak)`; `link(main, bak)` when the main file is known good;
  `rename(tmp, main)`; `fsync` of the folder. `rename(2)` within one APFS volume atomically replaces
  the destination (POSIX guarantee, APFS honours it). `Data.write(options: .atomic)` also ends in a
  rename but its documentation makes no storage-flush promise, and it writes its temporary file where
  it chooses, so it is not used. `F_FULLFSYNC` asks the drive to flush its cache (Apple's documented way;
  `fsync` alone may leave data in the drive cache).
- **Invariant**: after the first commit, every intermediate state leaves at least one complete,
  committed file: after `unlink(bak)` the main file; after `link` both; after `rename` the new main and
  the old backup. A failure at any step throws, leaves these files, removes the temporary file and is
  retried by the next commit.
- **Alternatives**: two alternating slots with a sequence number (needs both read and compared at
  launch; no gain over link + rename); `replaceItemAt` (more steps, may create its own backup copies).

## SCN-002-D5: Load and fallback

- **Decision**: remove a leftover temporary file (never read it); read the main file through a file
  handle, at most `SceneLimits.maximumBytes + 1` bytes (no attribute or timestamp reads); decode; then
  `liveState(registry:assets:)` (errors refuse; warnings kept). If the main file fails, try the backup;
  if that fails, restore nothing. Events: `mainUnreadable(reason)`, `restoredFromBackup`,
  `backupUnreadable(reason)`, `nothingRestored`. A newer-version file (main or backup) is refused and
  moved once to `<its name>.newer` (`current.scene.newer` or `current.scene.bak.newer`; left alone if
  that name exists), never written and never read
  again (event `setAsideNewer`), so a later save cannot overwrite another version's scene (analysis I1).
- **Main known good**: set after a good read of the main file or a successful save; while false, saves
  skip the `link` step so a damaged main file never replaces a good backup.

## SCN-002-D6: Unknown and unowned content

- **Decision**: the restored document is the **carry**: its ID, name, extra fields, unknown-kind layers
  (with their index), known layers (matched to captured layers by kind in order: instance ID, values,
  composite and extra kept), assets other than the app-owned keys `photo`, `video`, `text`, parameter
  values other than the seven the app holds, and the restored bindings, expressions, modulation graph
  and preserved edges. Capture writes the app's state over it. Unknown layers are inserted at their
  original index (clamped); one whose instance collides is renumbered (largest + 1); beyond 8 layers the
  extra unknown layers are dropped with an event `droppedLayers(count)`.
- **Bindings**: the native spectrum's live bindings when it exists, otherwise the carried ones;
  expressions kept for bound targets; the modulation section and preserved edges always carried.
  Restored bindings are applied to the native spectrum when it is created. No user binding editor
  exists yet, so bindings are not tracked as edits (they are written with the next commit).

## SCN-002-D7: Threading, probe and events

- **Decision**: the coordinator is main-actor; capture builds a `SceneDocument` (Sendable) on the main
  actor; one serial utility queue encodes and writes; the committed revision returns to the main actor.
  Background: commit inside a UIKit background task; terminate: synchronous on the queue. Events go to
  `DiagnosticsLog.app` with private values and to an in-memory list (tests, probe). The DEBUG probe
  (`sceneAutosave`, shown with `-uitestDiagnostics`) reads
  `restored=<main|backup|none> committed=<n> pending=<0|1> events=<n>`.

## SCN-002-D8: Privacy and required-reason APIs

- **Decision**: no file timestamps, attributes or disk-capacity calls (bounded read through a file
  handle). The privacy policy lists the scene files: the shown visual's settings, the text the user
  typed and the identifiers of the stored photo and video; never audio, paths, device or account data.
  The privacy manifest needs no new category (checked with `check_privacy_manifest.py`).
