# Feature Specification: FX-009 Motion Feedback

**Feature Branch**: `feature/fx-009` (spec directory `130-fx-009-motion-feedback`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FX-009 (Motion feedback) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Blend previous frame with decay and reset on scene changes." Acceptance, verbatim: "Reset clears
prior scene content in the first new frame." P1, effort L, depends on VIS-001 (integrated). Verification: snapshot
tests, shader unit tests, and the device GPU in the last stage."

Identifiers in this feature carry the roadmap ID: requirements `FX-009-R1…`, success criteria `FX-009-S1…`, tasks
`FX-009-T01…`, research decisions `FX-009-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor;
ADR-0013), CMP-004 (blend modes), CMP-013 (render caching; ADR-0040), CMP-014 (scene transition bus; ADR-0042),
FX-001 (bloom), FX-002 (tone map; ADR-0047), FX-003/FX-004 (colour grade; ADR-0050), FX-019 (composite flash guard),
ACC-005 (accessible sliders), ACC-012 (sensory safety profile; ADR-0049), MOD-001 (parameter registry; ADR-0012),
PERF-004 (texture pool), PERF-014 (render health), SHOW-001 (cues), UIX-002 (scene switcher), SCN-002/SCN-010
(scene restore, undo), FILE-005 (backup settings policy), FILE-011 (local data erase; ADR-0048), FX-010 (echo
feedback, a later row that builds on this one), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-14, commit `3c373722`)

**No frame feedback exists in the app's own pipeline.** Searching the packages and the app for feedback, trails or
echo finds none: every compositor frame starts from a cleared composite (`Compositor.encodeStack`, load action
clear), and nothing keeps a previous output. projectM presets have their own internal feedback, which is the
engine's and out of scope.

**The compositor-backed visuals share one output chain.** Camera, Photo, Video and Text each own one CMP-001
`Compositor`: layers → composite (`rgba16Float`, linear premultiplied; CMP-004 blend modes may ping-pong it) →
FX-019 flash guard, measuring through FX-003's grade and FX-002's tone map → output pass (grade, tone map, × the
guard's gain) into the screen, external display, REC-003 recording or REC-001 capture. CMP-014's
`SceneTransitionBus` runs the same stack phase (`encodeScene`) for two scenes and its own guard and output pass. The
native spectra (with FX-001 bloom) and projectM do not use this compositor.

**CMP-013 can keep a composite.** When no layer rendered and nothing the composite is made of changed, the previous
composite is kept (level 2) and only the guard and output run.

**How a "new scene" is signalled today.** Each visual host calls `resetFlashHistory()` (FX-019-R11: a new scene)
and `resetRenderHealth()` whenever its frame loop starts, which covers a visual switch (the old host pauses, the
new one starts). Show cue apply (SHOW-001, also used by UIX-002's switcher), scene reopen (PERF-010/SCN-002) and
undo/redo (SCN-010) go through `visualSettingsChanged()`; when the visual does not change, no host restarts. A size
change re-creates the compositor's textures (`allocate`). PERF-014's `resetRenderHealth()` gives failing parts a
fresh start.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: How is the previous frame blended? → A: Trails by maximum: each frame shows, per channel, the larger of the
  new picture and the previous shown picture faded by the decay. Brightness can never grow beyond the brightest
  input, so feedback cannot run away. Applied to FX-009-R2.
- Q: What does the user call it? → A: "Trails" (FX-010 is "Echo feedback", a later, different effect). Applied to
  FX-009-R9.
- Q: Which visuals? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output; the native
  spectra and projectM are unchanged. Applied to FX-009-R1 and the Assumptions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Moving things leave fading trails (Priority: P1)

A performer shows the Camera visual and turns on Settings → Trails: moving dancers and the spectrum bars leave
trails that fade over a fraction of a second. A slider sets how long the trails last. The same frames appear on an
external display, in recordings and in still captures.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a bright patch, then move it away; the old place fades by half every half-life.

**Acceptance Scenarios**:

1. **Given** Trails on with a half-life H, **When** a white patch disappears, **Then** its old place shows half its
   value H seconds later and a quarter 2H seconds later, at 60 and at 120 frames per second alike.
2. **Given** Trails on, **When** the picture does not change, **Then** the output equals the picture (trails of a
   still picture are the picture itself).
3. **Given** Trails set, **When** the app is relaunched, **Then** the same on/off state and length are applied.

---

### User Story 2 - A new scene starts clean (Priority: P1)

The performer steps to the next show cue (or picks a scene in the switcher, switches visual, reopens a scene, undoes
a scene edit or rotates the device). The first frame of the new scene shows nothing of the previous scene: no ghost
of the old picture fades out over the new one.

**Why this priority**: it is the roadmap row's acceptance criterion.

**Independent Test**: show red with Trails on for several frames, trigger the scene change, show blue; the first
new frame is blue only.

**Acceptance Scenarios**:

1. **Given** Trails on and a red scene shown for several frames, **When** any scene change happens and the next scene
   is blue, **Then** every pixel of the first new frame equals the blue scene shown without Trails.
2. **Given** a scene change, **When** the following frames are shown, **Then** trails build up again from the new
   scene only.

---

### User Story 3 - Off is exactly today (Priority: P1)

A performer who never turns Trails on sees exactly what the app showed before this feature, at no extra cost.

**Acceptance Scenarios**:

1. **Given** Trails off (the default), **When** any frame is shown, **Then** every pixel is bit-identical to the
   output before this feature and no extra picture memory is held.

---

### User Story 4 - Trails cannot defeat the safety settings (Priority: P1)

Trails can hold bright areas on screen and change how a strobe looks. The flash limiter still judges the picture
actually shown, and the sensory safety profile and Reduce flashing shorten the trails.

**Acceptance Scenarios**:

1. **Given** a strobing source and Trails on, **When** frames are shown, **Then** the flash limiter still lowers its
   gain for flashes above the threshold.
2. **Given** the Strict profile (or Reduced, or Reduce flashing on), **When** Trails are on, **Then** the trails are
   at most as long as that setting allows (shorter than the user's choice when the choice is longer).

### Edge Cases

- The first frame after Trails are turned on shows the picture only (there is no previous frame yet).
- Turning Trails off returns the held picture memory; turning them on again starts clean.
- A size change (rotation, external display, split view) or an output colour format change starts clean.
- A long gap between frames (a stall, a pause and resume) fades more per frame, by the elapsed time; a resumed
  frame loop starts clean (it is a new scene for the flash guard as well).
- NaN or infinite picture values are not kept by the trails (they never spread into later frames).
- Transparent areas stay transparent once the trails have faded.
- Stored values missing, not numbers, NaN or out of range: off, or the nearest limit.
- Visuals that are not compositor-backed: unchanged (the section's help says which visuals show trails).

## Requirements *(mandatory)*

### Functional Requirements

- **FX-009-R1**: Trails (on/off, off by default) apply to the compositor-backed visuals (Camera, Photo, Video, Text)
  on every output of a frame: screen, external display, recording and still capture.
- **FX-009-R2**: With Trails on, each shown frame is, per channel, the larger of the new composite and the previous
  trails frame multiplied by a per-frame decay; the result never exceeds the brightest value either input holds.
- **FX-009-R3**: The decay follows a half-life in seconds, converted per frame from the frame's duration
  (decay = 0.5^(duration ÷ half-life)), so the fade per second is the same at any frame rate; the per-frame decay is
  never above a fixed ceiling.
- **FX-009-R4**: Trails are applied to the composite before the colour grade, the tone map and the flash guard, so
  the flash guard and every output see the trails result.
- **FX-009-R5**: Any scene change clears the trails history: show cue apply (including the scene switcher), visual
  switch or frame-loop start, scene reopen or restore, undo/redo of a scene state, the start of a scene
  transition, an output size change, an output format change, a render-health reset, and turning Trails on.
- **FX-009-R6**: The first frame after a reset contains the new composite only: every pixel equals the frame that
  would be shown without Trails.
- **FX-009-R7**: The sensory safety profile's intensity limit caps the half-life (limit × the longest half-life), and
  Reduce flashing caps it at half the longest half-life; a cap of zero turns Trails off. The flash guard measures
  the trails result under every profile.
- **FX-009-R8**: Trails off is bit-identical to the output before this feature and holds no extra picture memory;
  Trails on uses one extra pair of pooled pictures at output size and one extra full-screen pass per frame, with no
  per-frame allocation. Pictures go back to the shared pool when Trails turn off, the size changes or the visual is
  released.
- **FX-009-R9**: Settings has a "Trails" section: an on/off toggle, a "Length" slider (half-life) with a readout
  ("0.20 s") and an ACC-005 spoken value, and help text naming the visuals affected and the safety caps.
- **FX-009-R10**: Trails on/off and the half-life are registered parameters (MOD-001) with stable IDs, ranges,
  defaults and step hints.
- **FX-009-R11**: The two values are saved on the device, restored at launch, included in library backups, erased
  with the other settings, checked on read, and removed by the UI-test reset.
- **FX-009-R12**: The render cache never reuses a stored composite while Trails are on.
- **FX-009-R13**: A plain-software reference of the decay and the blend exists, testable without a GPU (Linux), and
  the GPU output matches it.

### Key Entities

- **Trails setting**: on/off and half-life (seconds).
- **Trails history**: the last shown trails frame of one visual; cleared by every reset trigger.
- **Effective trails**: the setting after the safety caps (what the visuals use).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-009-S1**: For each reset trigger, after several red frames with Trails on, the first frame of a blue scene
  equals the blue scene without Trails (no red in any pixel).
- **FX-009-S2**: The fade after one half-life is 0.5 within 1% at 60 and at 120 frames per second (computed from
  injected frame durations, no clock).
- **FX-009-S3**: Trails off output is bit-identical to the output before this feature; all RenderGoldens pass
  unchanged.
- **FX-009-S4**: With Trails on, the stored composite is never reused; with Trails off reuse works as before.
- **FX-009-S5**: Under Strict the effective half-life is at most a quarter of the longest; a strobing source with
  Trails still makes the flash limiter lower its gain.
- **FX-009-S6**: Turning Trails on and off and changing the size many times leaves the picture pool's checkouts
  where they started (no leak).
- **FX-009-S7**: A user can find Trails, turn it on, change the length and see the values survive a relaunch.
- **FX-009-S8**: The extra GPU time per frame with Trails on is recorded on the Mac; the device frame rate is
  checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003/FX-004 and FX-019 are as integrated.
- No zoom or rotation of the previous frame in this row (classic "zoom feedback" can come with FX-010 or later).
- Live audio-reactive modulation of the trails is not wired (no compositor-backed visual has a modulator); the
  registry entries make it possible later.
- The native spectra (with bloom) and projectM are unchanged; projectM's own preset feedback is the engine's.
- A slideshow slide change or a media change inside one visual is not a scene change (trails may soften the cut).
