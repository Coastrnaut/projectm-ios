# Feature Specification: CMP-013 Render Caching

**Feature Branch**: `feature/cmp-013` (spec directory `113-cmp-013-render-caching`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14 (CMP-013-T01-T15 verified on the Mac host, the Linux shape and the iOS 27.2 simulator; no device run; report `docs/test-reports/render-caching.md`, ADR-0040)

**Input**: User description: "Implement CMP-013 (Render caching) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Skip recomposition of static layers until dependencies change."
Acceptance, verbatim: "Static source renders once over ten frames; parameter change invalidates
cache." Verification: unit tests, snapshots and GPU performance. P1, size L. Depends on CMP-001
(unified layer protocol)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-013-R1…`, success criteria `CMP-013-S1…`, tasks `CMP-013-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `a93c29db`)

The row's gap status is "Gap candidate". The audit confirms a full gap: every layer renders its whole
picture every frame, and the whole stack is composited every frame, whatever changed.

| Area | Today | Gap for this row |
|---|---|---|
| Layer contract (CMP-001) | A layer draws its whole compositor-owned picture each frame from the frame context (time, frame index and duration, output size, content scale, Reduce flashing) and the audio context. A layer declares a fallback and nothing else about its inputs. | No layer says what its picture depends on, so nothing can know a picture is still valid. |
| Photo layer (MED-001) | Draws the decoded image fitted (CMP-006) into its picture every frame. Its picture depends only on the image, the fit and the output size. | Static, rendered every frame. |
| Text layer (MED-009) | Blits a rasterized message every frame. Depends on the message rendering and the output size. | Static, rendered every frame. |
| Video (MED-002), camera (CAM-001), spectra (VIS-001/002), oscilloscope, projectM | Advance a clock, read a new frame or read the audio each frame. | Dynamic: must keep rendering every frame. |
| Procedural materials (SHD-001), generator graphs (SHD-002) | Advance a time and music motion every frame (`frameDuration`, band level). | Dynamic as built today. |
| Compositor | Per frame: every layer renders, then every visible layer is drawn (opacity, transform, blend, mask, group, solo/mute), then the flash guard and the output pass run. | No reuse at either level. |
| Faults (PERF-014), pool (PERF-004/006), capture (REC-001), recording (REC-003), flash guard (FX-019) | Work per frame on the finished composite. | Any cache must keep them exactly as they are. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no
human interaction); each answer is the recommended, conservative option.

- Q: How does a layer say it is static? → A: **By opting in.** A layer may declare, each frame, what
  its picture depends on: time, audio, modulation (MOD-002 bindings), external input (camera or video
  frames), and generation counters for its own content and its own parameters. A layer that declares
  nothing, or declares any time, audio, modulation or external-input dependency, renders every frame
  (unknown means always re-render). Rationale: a wrong "static" shows a stale picture; a missing
  declaration only costs work. Only the photo and text layers opt in in this row; every other layer
  keeps rendering every frame.
- Q: What is the cache key? → A: The set of input generations that can change a layer's own picture:
  the layer's content generation and parameter generation, the picture's description (size, pixel
  format, colour space), the frame context's content scale and Reduce flashing, and the compositor's
  cache epoch (bumped on every global invalidation). Equal keys reuse the picture; any difference
  renders once. The time terms of the frame context are never in the key (a cacheable layer does not
  read them).
- Q: Do composite settings (opacity, transform, blend, mask, group, solo/mute) invalidate a layer's
  picture? → A: **No.** They are applied when the picture is placed in the composite, not when the
  layer draws its picture, so they never cause a layer render. Fit (CMP-006) is different: the photo
  layer applies it inside its own picture, so a fit change is a parameter change of that layer and
  causes exactly one render. The acceptance's "parameter change invalidates cache" is met by the
  layer's own parameters (fit, content, message); the placement parameters are proved correct by the
  bit-identity test instead.
- Q: Is the whole composite cached too (level 2)? → A: **Yes, conservatively.** When no layer
  rendered this frame, every drawn layer reused the same picture as last frame, every shown opacity
  (layer and group) is unchanged, and nothing was applied or invalidated since the last successful
  frame, the compositor keeps the previous composite and skips only the layer drawing passes. The
  flash guard, the output pass, frame capture and recording still run every frame on that composite,
  so the flash history keeps advancing in time and every consumer gets a fresh output frame (the
  caller's drawable is new each frame). The external display has its own compositor and follows the
  same rule. Rejected: skipping the output pass or the flash guard (a drawable must be filled; the
  envelope must see every frame's duration).
- Q: What invalidates? → A: A layer's own parameter or content change (its generations); a new
  output size; a colour-space or format change of the pictures; a Reduce Flashing or content-scale
  change; a memory warning that purges the texture pool (PERF-006); a GPU error, a device fault or a
  render-health reset (PERF-014); a layer re-prepared or given new pictures; a render that failed or
  was skipped; a frame that returned without finishing. Solo, mute, group and any applied stack change
  invalidate the composite (level 2) but not the layer pictures. After any invalidation no stale
  picture is shown: the next frame renders.
- Q: Can caching be switched off? → A: **Yes**, per compositor (on by default), for tests,
  diagnostics and as a field kill switch; with caching off the compositor behaves exactly as before.
  The output with caching on is bit-identical to caching off.
- Q: Does the photo's "frames shown" count still grow while its picture is reused? → A: **Yes.**
  The layer is told when its picture was reused, so "frames that showed the photo" keeps counting
  frames shown (the app's diagnostics and UI tests rely on it); a separate count reports actual
  renders.
- Q: Extra memory? → A: **None for layer pictures**: a reused picture is the layer's own existing
  picture. The level-2 composite is the compositor's existing composite. Nothing new is allocated
  per frame.
- Q (clarify pass): What outcome does a layer whose picture was reused report? → A: **`rendered`,
  unchanged** (its picture is this frame's valid picture); a separate per-layer "reused" flag tells
  them apart. Rationale: a new outcome case would break every exhaustive switch in the app and the
  health rules that read outcomes. Rejected: a new `reused` outcome.
- Q (clarify pass): How quickly must a GPU error invalidate the cache? → A: **At the next frame tick
  that observes it** (PERF-014 polls the last three command buffers at the start of each tick). A
  picture drawn in a buffer that failed can therefore be reused for at most the frames until the
  failure is observed (normally 1–3); those frames also showed the failed work without caching, so
  the output stays identical. Recorded, not changed.
- Q (clarify pass): Does a hidden static layer (solo/mute, opacity 0, disabled group) render while
  hidden? → A: **It stays cached** (CMP-012 says hidden layers keep rendering so that un-hiding shows
  a current frame; a cached picture is current by definition). A hidden dynamic layer keeps rendering
  every frame as before.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A static photo is drawn once, not every frame (Priority: P1) 🎯 MVP

A performer shows a still photo, alone or under other layers. Its picture is drawn once and reused
while nothing it depends on changes, so the device spends less GPU time and battery per frame with
the same picture on screen.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: Composite ten frames of a stack with a loaded photo layer and count the photo
layer's renders: exactly one. Change its fit: exactly one more render on the next frame, then none.

**Acceptance Scenarios**:

1. **Given** a loaded photo layer, **When** ten frames are composited, **Then** the photo is rendered
   exactly once and shown in all ten.
2. **Given** a cached photo, **When** its fit changes, **Then** the next frame renders it exactly
   once and later frames reuse it.
3. **Given** a cached photo, **When** a new image finishes loading, **Then** the next frame renders
   it, and the old picture is never shown again.
4. **Given** a cached photo, **When** its opacity, transform, blend mode or mask changes, **Then** it
   is not rendered again and the frame shows the change.

---

### User Story 2 - Caching never changes what is shown (Priority: P1)

Whatever the scene does, the picture on screen with caching on is exactly the picture with caching
off.

**Why this priority**: A cache that shows a stale or different frame is a bug the audience sees.

**Independent Test**: Run the same scripted sequence of changes (content, fit, opacity fades,
transform, blend, mask, group, solo/mute, size, Reduce flashing, purge) through two compositors, one
with caching on and one off, read every output frame back and compare bytes.

**Acceptance Scenarios**:

1. **Given** a scripted sequence, **When** each frame is read back from both compositors, **Then**
   every frame is byte-identical.
2. **Given** a stack whose every layer is static, **When** nothing changes, **Then** the composite
   is reused and the output is still byte-identical.

---

### User Story 3 - Every invalidation shows a fresh picture (Priority: P1)

Each event that can change a cached picture forces one fresh render.

**Why this priority**: A missed invalidation shows a stale picture.

**Independent Test**: One test per trigger: count renders before and after the trigger and check the
read-back.

**Acceptance Scenarios**:

1. **Given** a cached static layer, **When** any trigger in the invalidation table happens, **Then**
   the next frame renders it exactly once (or, for a composite-only trigger, recomposites without
   rendering it).

---

### User Story 4 - Dynamic layers are never cached (Priority: P1)

Spectra, video, camera, projectM, materials, graphs and anything bound to audio or time keep rendering
every frame.

**Independent Test**: With caching on, a spectrum layer, a layer that declares time, audio,
modulation or external input, and a layer that declares nothing each render ten times in ten frames.

**Acceptance Scenarios**:

1. **Given** a dynamic layer, **When** ten frames are composited with caching on, **Then** it renders
   ten times.

---

### User Story 5 - GPU time is measured (Priority: P2)

The GPU time of a static-heavy stack with and without caching is recorded on the Mac.

**Independent Test**: A bench composites a stack of static layers with caching on and off and prints
the GPU time per frame (recorded, not asserted).

### Edge Cases

- A layer that throws "not ready" (a photo still loading) is never cached; its fallback is shown.
- A render that fails after a reuse: a one-picture layer's picture is overwritten, so the cache entry
  is dropped before the render; a last-good-frame layer keeps showing its last good picture.
- A held fault (PERF-014 back-off) shows the fallback with no render, as before; the cache entry is
  dropped.
- A frame that fails half way, or a command buffer that later reports an error: everything is
  invalidated, so a picture that may not have been drawn is never reused.
- A layer added or removed, reordered or regrouped: the composite is redrawn; kept layers keep their
  cached pictures.
- A hidden layer (solo/mute, opacity 0, disabled group) that is static stays cached; un-hiding draws
  its cached picture at once.
- An opacity fade running: the composite is redrawn every frame of the fade; the static layer is not
  rendered.
- Frame capture or recording during a reused composite: both read the composite as shown.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-013-R1**: A layer MAY declare its render dependencies each frame: time, audio, modulation,
  external input, a content generation and a parameter generation. A layer that declares nothing is
  unknown and renders every frame.
- **CMP-013-R2**: A layer is cacheable in a frame only when it declares no time, audio, modulation or
  external-input dependency.
- **CMP-013-R3**: The cache key of a cacheable layer is its content and parameter generations, the
  picture description, the content scale, Reduce flashing and the compositor's cache epoch.
- **CMP-013-R4**: The compositor MUST skip a cacheable layer's render and show its last good picture
  when its key equals the key of that picture; otherwise it renders and, only on success, records
  the new key.
- **CMP-013-R5**: Composite placement (opacity, transform, blend, mask, group, solo/mute) MUST NOT
  cause a layer render.
- **CMP-013-R6**: The compositor MUST reuse the previous composite (skip only the layer drawing
  passes) when no layer rendered, every drawn layer shows the same picture as in the last frame,
  every shown layer and group opacity is unchanged, and nothing was applied or invalidated since the
  last successful frame. The flash guard, output pass, capture and recording still run every frame.
- **CMP-013-R7**: Every trigger in the invalidation table MUST invalidate as listed; after an
  invalidation the cache holds no stale picture.
- **CMP-013-R8**: Caching MUST be switchable per compositor (on by default); off behaves exactly as
  before this row.
- **CMP-013-R9**: Output frames with caching on MUST be bit-identical to caching off.
- **CMP-013-R10**: Caching MUST allocate nothing per frame and no extra textures.
- **CMP-013-R11**: The photo and text layers MUST declare their dependencies; a reused frame still
  counts as a frame shown, and each reports its actual renders separately.
- **CMP-013-R12**: The dependency and key model MUST be plain Swift that builds and is tested on
  Linux.
- **CMP-013-R13**: The compositor MUST report, for tests and diagnostics, the layers reused in the
  last frame, whether the last composite was reused, and the cache epoch.

### Invalidation table

| Trigger | Layer pictures | Composite (level 2) |
|---|---|---|
| Layer content change (new photo loaded, new message rendered) | That layer renders once | Redrawn |
| Layer parameter change (fit) | That layer renders once | Redrawn |
| Output size change | All render | Redrawn |
| Picture colour space or format change (fixed by the CMP-001 picture contract today; in the key for when it varies) | All render (key) | Redrawn |
| Reduce Flashing or content-scale change | All cacheable layers render | Redrawn |
| Memory warning (texture pool purge) | All render | Redrawn |
| GPU error observed, render-health reset, layer re-prepared or new pictures | All render (that layer for a re-prepare) | Redrawn |
| Render failed, skipped or held | That layer's entry dropped | Redrawn |
| Frame returned without finishing | All render | Redrawn |
| Opacity (layer or group) shown value changed | — | Redrawn |
| Transform, blend, mask, group, solo/mute, stack apply | — | Redrawn |
| Explicit `invalidate` call | All render | Redrawn |

### Key Entities

- **Render dependencies**: what a layer's picture reads in a frame (flags and two generations).
- **Render cache key**: the input generations a cached picture was drawn with.
- **Cache epoch**: a compositor-wide counter bumped by every global invalidation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-013-S1**: A static photo layer renders exactly once over ten frames; a fit change causes
  exactly one more render.
- **CMP-013-S2**: Every invalidation trigger has a test, and each passes.
- **CMP-013-S3**: Over a scripted sequence of at least 20 frames with every kind of change, every
  output frame is byte-identical with caching on and off.
- **CMP-013-S4**: Dynamic and undeclared layers render on 10 of 10 frames with caching on.
- **CMP-013-S5**: The GPU time per frame of a static-heavy stack with and without caching is
  recorded on the Mac.
- **CMP-013-S6**: Existing suites (Compositor, RenderGoldens, SceneFormat, ImportFuzz, ShowControl,
  SceneArchive, VisualGenerators, app unit tests, photo and text UI tests) still pass; goldens are
  unchanged.

## Assumptions

- Materials and generator graphs keep rendering every frame: their motion advances with time and
  music today. A graph without time or music nodes could opt in later (follow-up, not this row).
- Video has no paused state in its layer (its clock follows presentation time), so it is never cached.
- Device and simulator GPU timings are not evidence for performance claims; the Mac bench is recorded
  only.
- No UI and no setting: caching is on by default and has no user-visible control.
