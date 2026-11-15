# Feature Specification: FX-010 Echo Feedback

**Feature Branch**: `feature/fx-010` (spec directory `297-fx-010-echo-feedback`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-010 (Echo feedback) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Render multiple delayed echoes using bounded history buffers." Acceptance, verbatim: "Echo count
is capped and memory use remains bounded." P2, effort L, depends on FX-009 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-010-R1…`, success criteria `FX-010-S1…`, tasks
`FX-010-T01…`, research decisions `FX-010-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor;
ADR-0013), CMP-013 (render caching; ADR-0040), FX-002 (tone map), FX-003 (colour grade), FX-006 (chromatic split;
ADR-0104), FX-007 (directional blur; ADR-0106), FX-009 (Trails; ADR-0051), FX-019 (composite flash guard), FX-020
(effect chains; ADR-0054), ACC-005 (accessible sliders), ACC-012 (sensory safety profile), PERF-004 (texture pool),
PERF-009 (pipeline archive), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy),
VIS-010/VIS-020 (fixed-allocation history textures), RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, integration commit `96f7dcce`)

**No echo effect exists.** FX-009 Trails (`TrailsPass`, `cmp_trails`) keeps a single feedback picture and blends
`max(composite, decay × previous)`: one exponentially fading smear, not separate delayed copies. Nothing in the
compositor keeps more than one past frame.

**The output effect chain.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (`rgba16Float`, linear premultiplied) → the FX-020 reorderable effects (Trails, Color, Chromatic
split, Directional blur, walked by `encodeOutputEffects` over `outputEffectOrder`) → FX-019 flash guard → output pass
(grade, tone map). FX-006 and FX-007 set the pattern this feature follows: a `*Pass.swift` with its own `cmp_*`
function, pooled `rgba16Float` pictures returned when unused, the shader spliced at the one reviewed compile site and
listed in `CompositorShaderSources.archived`, an `OutputEffectKind` case appended last, a `SceneEffectSettings`
entry, a global setting with an Effect order row. FX-008 (radial blur) is being built in parallel and appends its own
kind; this feature appends after whatever is there and never reorders.

**Fixed allocations.** VIS-010 and VIS-020 allocate their history textures once and prove it with texture identities
and `allocatedSize` in tests; this feature does the same for its history ring.

**Safety.** FX-009 limits Trails through ACC-012 (`MotionFeedback.limited(by:)`); the FX-019 flash guard always
measures the shown frame, after every output effect.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: Where do echoes apply? → A: The compositor-backed visuals (Camera, Photo, Video, Text), on every output, as a
  reorderable entry of the FX-020 effect chain ("Echo", stored kind `fx.echo`), appended after the last existing
  kind. The native spectra and projectM are unchanged. Applied to FX-010-R1, R9.
- Q: What is the echo cap? → A: At most 4 echoes. Any request above 4 (a slider, a scene value, a preset) gives
  exactly 4, and the GPU loop's bound is the same constant. Applied to FX-010-R3, R4.
- Q: How is memory bounded? → A: The history is a ring of exactly 4 pictures (the cap), allocated once when the effect
  turns on, at a reduced "history size": half the output in each direction, rounded to a multiple of 16 pixels, and
  scaled down so its longer side is at most 960 pixels. The worst case is 4 × 960 × 960 × 8 bytes = 29,491,200 bytes
  of picture data whatever the output size, echo count or delay. Applied to FX-010-R6, R7.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Is the echo delay counted in frames or in milliseconds? → A: Milliseconds on the compositor's frame clock (the
  injected frame durations Trails already use), 10…500 ms, so echoes are as far apart in time at 30, 60 or 120 fps.
  Applied to FX-010-R3, R5.
- Q: How are the echoes combined with the live picture: added, mixed, or the brighter of the two? → A: The brighter of
  the two per channel (like FX-009 Trails), with the echo weights summing to at most 1: the output is never brighter
  than the brightest frame it is made of, so Echo adds no new peak brightness, and the live picture is never dimmed.
  Applied to FX-010-R2, US3.
- Q: Are the stored frames copies of the picture entering Echo, or of Echo's own output (an echo of an echo)? → A: Of
  the picture entering Echo: no feedback loop, so each copy appears once with exactly its own weight and nothing
  accumulates. Applied to FX-010-R2, Assumptions.
- Q: When Echo turns off, is its history memory freed or kept for a quick return? → A: Freed (returned to the shared
  texture pool, fenced by the last command buffer), like every other output effect; turning it on again allocates the
  ring once and starts from an empty history. Applied to FX-010-R6.
- Q: Is Echo a global setting or a per-scene value? → A: Both, like Trails, the chromatic split and the directional
  blur: a global setting the visuals use, which a scene or effect-chain preset with an `fx.echo` entry overwrites when
  opened; a scene without one leaves it alone (FX-020's rule). Applied to FX-010-R13, R14.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Delayed copies of motion (Priority: P1)

A performer shows the Camera visual and turns on Settings → Echo: moving things leave a few fading copies behind them,
each copy a little older and dimmer than the one before. Sliders set how many copies (1 to 4), how far apart in time
they are, and how quickly they fade.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: a small bright dot moving one step per frame on black: with 3 echoes and the shortest delay, the
output shows the dot plus 3 dimmer copies at its previous positions, each dimmer than the one before.

**Acceptance Scenarios**:

1. **Given** Echo on with N echoes, **When** a dot moves across a black frame, **Then** N copies trail it at the
   expected delays, the k-th copy weighted by the fade to the power k (all scaled together when their sum would exceed
   1), so each copy is dimmer than the one before by the fade.
2. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - Capped count, bounded memory (Priority: P1)

However the echo is set — by the slider, a scene or a preset, with any delay — it never shows more than 4 copies, and
its memory never grows while it runs.

**Why this priority**: it is the roadmap acceptance.

**Acceptance Scenarios**:

1. **Given** a request for more than 4 echoes, **When** frames are drawn, **Then** exactly 4 copies are shown.
2. **Given** a long run with setting changes and size changes, **When** the history is inspected, **Then** it holds
   exactly 4 pictures, whose identities change only when the history size changes, and whose total memory never
   exceeds the documented bound; nothing is allocated per frame.

---

### User Story 3 - Off is exactly the picture, and never brighter (Priority: P1)

A performer who leaves Echo off sees exactly the picture the app showed before this feature; with Echo on, the
picture is never brighter than the frames it is made of.

**Acceptance Scenarios**:

1. **Given** Echo off (or 0 echoes), **When** any frame is shown, **Then** every output pixel is bit-identical to the
   output without this feature and no history memory is held.
2. **Given** Echo on at any setting, **When** frames are shown, **Then** the echo weights sum to at most 1 and no
   output value exceeds the brightest value of the current and stored frames; the flash guard measures the frame
   actually shown.

---

### User Story 4 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Echo on the Effect order screen, saves a scene and an effect-chain preset, and gets the same
echo back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Echo on, **When** it is opened, **Then** the echo's values and position are
   restored; a scene without an echo entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened, **Then** it renders and encodes exactly as
   before.

### Edge Cases

- Count, delay or fade missing, not a number or out of range: off, the default, or the nearest limit; a count above 4
  gives 4, a count of 0 is off.
- The first frames after Echo turns on, a scene change, a size change or an output-format change: no past frames are
  stored yet, so no echo is shown until frames have been captured (never content from before the reset).
- A size change that keeps the history size (a small resize) keeps the history; one that changes it (rotation, an
  external display) replaces the 4 pictures and starts the history again.
- Non-finite picture values (NaN, ±Inf): a non-finite current pixel passes through (FX-002 counts it); stored frames
  never hold non-finite values, so they never spread.
- A delay longer than the frame time: copies are taken at most once per frame; a delay shorter than a frame takes one
  copy every frame.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-010-R1**: Echo (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video, Text) on
  every output of a frame: screen, external display, recording and still capture.
- **FX-010-R2**: With Echo active, each output pixel is the brighter, per channel, of the current picture and the sum
  of the echoes, where echo k (k = 1…N) is the k-th most recent stored frame scaled by its weight; echo weights are
  fade^k, scaled down together when their sum exceeds the weight cap (1), so the sum never exceeds it.
- **FX-010-R3**: Echo count 1…4 on the slider (default 3; VoiceOver step 1; a stored 0 means off); delay 10…500 ms (default 100 ms; step 10 ms); fade
  0.1…0.9 (default 0.6; step 0.05).
- **FX-010-R4**: The count is capped at 4 everywhere: values above 4 read as 4, and the GPU loop's bound is the cap
  constant.
- **FX-010-R5**: Frames are stored on the frame clock: a frame is stored when at least the delay has passed since the
  last stored frame (the first frame after a reset is stored at once), at most once per frame, after the frame's
  echoes are drawn. Echo k is therefore between (k − 1) × delay and k × delay old, plus at most one frame.
- **FX-010-R6**: The history is a ring of exactly 4 pictures at the history size (half the output per direction,
  rounded to a multiple of 16 pixels, at least 16, longer side at most 960 pixels), allocated once when Echo turns on,
  kept for every change of count, delay and fade, replaced only when the history size changes, and returned to the
  pool when Echo turns off or the visual is released. Like FX-006/FX-007, the pass also holds one output picture at
  the output size while active (not part of the history bound). Nothing is allocated per frame.
- **FX-010-R7**: The history's memory never exceeds 4 × 960 × 960 × 8 bytes (29,491,200 bytes) of picture data; the
  test bound is 4 × the device's allocation size of one picture at the current history size.
- **FX-010-R8**: Echo is active only when on, the count is at least 1 and the weight cap is above 0; otherwise no pass
  runs and the output is bit-identical to the output before this feature.
- **FX-010-R9**: Echo is an FX-020 reorderable output effect (`fx.echo`), appended to the standard order. The flash
  guard and the tone map always run after it.
- **FX-010-R10**: ACC-012: a profile that caps intensity scales the weight cap by its intensity limit; Reduce flashing
  caps it at 0.5; a cap of 0 turns Echo off.
- **FX-010-R11**: A reset (scene change, cue, reopen, undo/redo, transition start, size or output-format change,
  turning on) empties the history, so no echo of the previous content appears.
- **FX-010-R12**: Settings has an "Echo" section: an on/off toggle, Echoes, Delay and Fade sliders with readouts ("3",
  "100 ms", "0.60") and ACC-005 spoken values, and help text. The Effect order screen lists it with its own switch.
- **FX-010-R13**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-010-R14**: Scenes and effect-chain presets store Echo as an `fx.echo` entry (`count`, `delay`, `decay`) in
  FX-020's `effects` list; out-of-range values are clamped and reported; scenes without it encode byte-identically.
- **FX-010-R15**: A plain-software reference (weights, the storing schedule, the history size, the downsample and one
  output pixel) exists, testable without a GPU (Linux), and the GPU output matches it.
- **FX-010-R16**: The shaders are module constants added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Echo setting**: on/off, count (1…4), delay (seconds), fade (0.1…0.9).
- **History ring**: 4 stored frames at the history size, the order they were stored in, how many are valid, the time
  since the last store.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-010-S1**: A request for 5, 8 or 1,000 echoes shows exactly 4 copies; the shader's loop bound is the cap.
- **FX-010-S2**: Over 600 frames with setting changes and resizes, the history holds 4 pictures at all times while
  on, their identities change only at history-size changes, the total memory stays at or under the bound, and the
  allocation count rises only when Echo turns on or the history size changes.
- **FX-010-S3**: A moving dot shows N copies at the expected delays with weights fade^k (scaled to the cap); the GPU
  output matches the software reference within half-float filtering precision; the weight sum never exceeds 1.
- **FX-010-S4**: Off and 0 echoes are bit-identical to the output without the feature on random content and hold no
  history; all existing RenderGoldens pass unchanged.
- **FX-010-S5**: A scene and a preset with Echo round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-010-S6**: A user can find Echo, turn it on and change the count (UI test under 30 s).
- **FX-010-S7**: The device frame rate with Echo on at 4 echoes is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002 to FX-007, FX-009, FX-019 and FX-020 are as integrated.
- Echo copies are of the picture entering the echo (no echo of an echo), so brightness stays bounded without feedback.
- History pictures at reduced resolution are acceptable for faded copies; the live picture keeps full resolution.
- Live audio-reactive modulation of Echo is not wired.
