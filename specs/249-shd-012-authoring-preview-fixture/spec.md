# Feature Specification: SHD-012 Authoring Preview Fixture

**Feature Branch**: `feature/shd-012` (spec directory `249-shd-012-authoring-preview-fixture`)
**Created**: 2026-11-14
**Status**: Draft
**Input**: User description: "Implement SHD-012 (Authoring preview fixture) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Preview generator against deterministic sample audio and clock." Acceptance,
verbatim: "Two preview runs yield same parameter trajectory and frame sequence." P1, depends on ANL-016
(integrated)."

Identifiers carry the roadmap ID: requirements `SHD-012-R1…`, success criteria `SHD-012-S1…`, tasks
`SHD-012-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `372c75ed`)

| Area | Today | Gap for this row |
|---|---|---|
| Deterministic offline export (REC-013) | `OfflineFrameClock` (frame n at n × 1e9 / fps, analysis up to sample round(n × 44,100 / fps)), `OfflinePCMSource`, `OfflineAnalysisDriver` (ANL-016 pipeline stepped synchronously with a clock that reads 0), `OfflineFixtureAudio` (seeded 120 BPM kick, chord and noise hits), per-frame SHA-256 of the read-back bytes, `OfflineSceneRenderer` for native visuals. | Built for whole video exports of native visuals; no parameter trajectory, nothing for materials. |
| Noise editor (SHD-006) | Settings › Noise editor: one still of Noise Flow at phase 0 (no music) drawn by `MaterialPreviewRenderer` with the material's own GPU code; generic metadata controls. | A still cannot show how the texture moves with music or how a binding moves a parameter. |
| Material motion (SHD-001) | `MaterialMotion` integrates the phase from the frame duration, speed and a smoothed band level; deterministic, plain Swift. | — |
| Bindings (MOD-002, MOD-003…005, MOD-011) | `AudioFeatureModulator`: validated bindings (feature → parameter, range, curve, envelope, mix mode), advanced with an explicit time; effective value from the manual value. | Nothing evaluates bindings against fixture audio or records their output. |
| Metadata controls (SHD-003) | Material parameters are MOD-001 descriptors: floats modulatable, ints and colours manual. | — |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: What is the "generator" the preview drives? → A: A procedural material (SHD-001 catalog), shown in the
  Noise editor for Noise Flow. Material layers are the generators authors tune today (SHD-006); the native
  spectra already have REC-013's offline export. The package API takes any material definition.
- Q: What is the "deterministic sample audio and clock"? → A: REC-013's `OfflineFixtureAudio` for a seed
  (default seed 1), 4 s long, analysed by `OfflineAnalysisDriver` (the live ANL-016 analysis, stepped
  synchronously) and paced by `OfflineFrameClock` at 30 fps: 120 frames. Live audio, the display link and the
  wall clock are never read.
- Q: What is the "parameter trajectory"? → A: Per frame: the effective value of every bound parameter (after
  MOD-002 modulation, as stored by the material's clamping rules), plus the material's motion phase and smoothed
  audio level. Values are Doubles compared with exact equality.
- Q: What is the "frame sequence"? → A: The SHA-256 of each frame's read-back pixels (linear half-float RGBA, as
  REC-013 and SHD-006 read them), drawn by the material layer's own GPU code with the trajectory's values, at
  128 × 128 pixels. Exact equality is promised on the same GPU class only (SHD-006's rule).
- Q: Where do the bindings come from? → A: The editor offers one preview binding: a target (any modulatable
  Noise Flow parameter, or none) and a source from the features the fixture analysis feeds (kick, band mean,
  lowest band), full range, linear, no smoothing. Default: Warp amount ← kick. The package takes any list of
  MOD-002 bindings.
- Q: Are the preview binding and fixture seed saved? → A: No. They are authoring-session state of the editor
  (no new UserDefaults keys, nothing in backups); the Noise settings themselves stay as SHD-006 stores them.
- Q: How is it shown? → A: A "Fixture preview" section in the Noise editor: "Play fixture" renders the whole
  run once, then loops the frames at 30 fps; "Stop" ends the loop. A frame slider scrubs; with Reduce Motion on
  the loop does not auto-play (the slider still works). A summary line reads the frame count, the bound
  parameter's range over the run and a short run digest (first 8 hex characters of a SHA-256 over all frame
  checksums), so an author can see that a repeat run is identical.
- Q: Flashing? → A: The preview draws with Reduce flashing on (as SHD-006's still does), in a small inline
  picture, and plays only on request.
- Q: Pacing and chunking? → A: The run can be stepped one frame at a time or in chunks of any size; the result
  is the same as one pass because everything is a function of the frame index. Tests prove it.
- Q: Where does a run execute, and what does the editor show meanwhile? → A: Off the main thread, with its own
  renderer and layer (nothing shared with the still preview); the button reads "Rendering…" and is disabled
  until the frames are ready. A 120-frame run of 128 × 128 pixels should finish in about a second; no wall-clock
  assertion is made in tests.
- Q: Which fixture seeds can an author pick? → A: 1…99 with a stepper (default 1). Each seed is a different
  REC-013 fixture (different noise hits), so a seed change shows how robust a binding is to the music.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview a material against the fixture (Priority: P1)

An author in the Noise editor taps "Play fixture". The texture plays as a short loop driven by the built-in
fixture music, with the chosen binding moving its parameter on every kick. The summary shows the frame count, the
bound parameter's range and a run digest.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: A UI test opens the editor, taps Play fixture, waits for the summary and checks the frame
count and digest; tapping again gives the same digest.

**Acceptance Scenarios**:

1. **Given** the Noise editor, **When** Play fixture is tapped, **Then** a looping preview and a summary "120
   frames" with a digest appear.
2. **Given** a finished run, **When** Play fixture is tapped again with the same settings, **Then** the digest is
   unchanged.

### User Story 2 - Two runs are identical (Priority: P1)

The same material, settings, bindings, fixture seed and frame count always give the same trajectory and the same
frame checksums; a different seed or binding gives a different trajectory.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests run the trajectory twice (and stepped in different chunk sizes) and compare
arrays exactly; GPU tests render the frame sequence twice and compare checksums.

**Acceptance Scenarios**:

1. **Given** fixed inputs, **When** two runs are recorded, **Then** trajectories are equal Double for Double and
   frame checksums are equal.
2. **Given** fixed inputs, **When** one run is stepped frame by frame and another in chunks of 7, **Then** both
   equal a single-pass run.
3. **Given** a changed fixture seed or binding, **When** a run is recorded, **Then** the trajectory differs.

### Edge Cases

- No binding: the trajectory still records phase and audio level; parameters stay at their manual values.
- A binding on a parameter that cannot be modulated (integer, colour) is refused before the run.
- A frame count of 0 gives an empty run; more frames than the fixture audio holds read silence after its end.
- No Metal: the trajectory is still recorded; the picture shows the "needs Metal" text.
- Changing a setting while a loop plays stops the loop (the frames no longer match the settings).

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-012-R1**: The preview MUST be driven only by fixture audio for a given seed and a fixed frame clock;
  it MUST NOT read live audio, the wall clock or the display refresh.
- **SHD-012-R2**: For every frame the preview MUST record the effective value of each bound parameter, the
  material's motion phase and its smoothed audio level (the trajectory).
- **SHD-012-R3**: Bindings MUST be MOD-002 bindings validated against the material's parameter registry; a
  refused binding MUST be reported and the run not started.
- **SHD-012-R4**: For every frame the preview MUST draw the material with the frame's values through the
  material's own GPU code and record a checksum of the frame's pixels.
- **SHD-012-R5**: Same material, settings, bindings, seed, frame rate, frame count and picture size MUST give
  identical trajectories and (same GPU class) identical checksum sequences, however the run is stepped.
- **SHD-012-R6**: The Noise editor MUST offer a fixture preview: binding choice, fixture seed, Play fixture /
  Stop, a looping picture, a frame slider and a summary (frames, bound range, run digest).
- **SHD-012-R7**: The loop MUST respect Reduce Motion (no auto-play) and draw with Reduce flashing on.
- **SHD-012-R9**: A run MUST NOT block the interface: it renders off the main thread and the editor shows that it
  is rendering; changing a setting or leaving the editor stops a loop.
- **SHD-012-R8**: The trajectory part MUST be plain Swift that builds on Linux.

### Key Entities

- **Fixture**: seed, duration, frame rate → audio and frame count.
- **Preview request**: material, base values, bindings, fixture, picture size.
- **Trajectory**: per frame, the time, the bound parameters' values, the phase and the audio level.
- **Frame sequence**: per frame, a pixel checksum; the run digest summarises it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-012-S1**: Two runs of the same request give equal trajectories (exact) and equal frame checksum
  sequences on the host GPU — the acceptance.
- **SHD-012-S2**: Frame-by-frame, chunk-of-7 and single-pass runs give equal trajectories.
- **SHD-012-S3**: A changed fixture seed changes the bound parameter's trajectory; a changed binding target or
  source changes it; a changed setting changes the frame checksums.
- **SHD-012-S4**: The UI test opens the preview, plays it twice and reads the same digest in under 30 s.
- **SHD-012-S5**: Unit tests under 10 s each; package suites under one minute.

## Assumptions

- Exact checksums hold per GPU class (SHD-006); the acceptance is proven on the Mac's GPU and the simulator. A
  look on a physical device is a `{device}` task.
- The fixture analysis feeds bands and the kick envelope; other features (loudness, centroid, …) read 0 in the
  preview and are not offered as sources.
