# Feature Specification: MED-007 Image Ken Burns

**Feature Branch**: `feature/med-007` (spec directory `251-med-007-ken-burns`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement MED-007 (Image Ken Burns) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Pan and zoom still images with keyframed bounds." Acceptance, verbatim: "Start/end frames match
specified crop rectangles." Priority P2, depends on MED-001 (photo layer)."

Identifiers in this feature carry the roadmap ID: requirements `MED-007-R1…`, success criteria `MED-007-S1…`,
research decisions `MED-007-D1…`, tasks `MED-007-T01…`. Other features are cited by their own IDs: MED-001 (photo
layer), MED-006 (image slideshow), CMP-005 (layer transform), CMP-006 (aspect fitting), CMP-013 (render caching),
SHOW-008 (keyframe tracks), ACC-001 (Reduce Motion), SCN-001 (scene format), FILE-005 / FILE-011 (settings backup
and erase).

## Baseline: what exists today (audit of 2026-11-14, commit `72aa7e3a`)

| Question | Today |
|---|---|
| Photo layer | `ImageLayerSource` (MED-001) draws one decoded still through `LayerFitPlacement` (CMP-006: fill by default, fit, stretch, pixel-accurate, anchor). The shader maps each output point to an image coordinate `offset + p · visible`; outside 0…1 is transparent. |
| Slideshow | MED-006 swaps the photo layer's content on a schedule (Time: 2…60 s; Beats: 1…16 beats on a reliable tempo grid); a change is a one-render cut, the next slide is decoded ahead. One arrangement for the whole slideshow. |
| Render caching | CMP-013: the photo layer declares itself still (content = load generation, parameters = fit generation), so an unchanged photo renders once and is reused. A moving photo must not be cached. |
| Frame clock | Every layer receives `LayerFrameContext` (monotonic presentation time, frame duration clamped to 0…0.1 s), injected by tests. |
| Keyframes | SHOW-008 (on its feature branch) evaluates a track exactly at keyframe times and interpolates by a segment-relative fraction computed from integer nanoseconds. |
| Reduce Motion | ACC-001's `MotionPolicy` and `settings.systemReduceMotion`; native visuals stop decorative motion under it. |
| Scene | A `photo` asset carries optional fields verbatim (`slideshow`, MED-006); new fields need no version bump. |
| Pan / zoom | **None.** A photo is always static. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rules 4 and 9: best judgement, no human
interaction); each answer is the conservative, local-first option, recommended option first.

- Q: How is a crop rectangle expressed and validated? → A: x, y, width, height as fractions of the image (0…1, top-left origin). Valid when every value is finite, width and height are at least 0.05 (at most 20× zoom) and the rectangle lies inside the image (tolerance 1e-9). Edits clamp (size first, then position); a stored rectangle that is invalid makes the whole stored movement read as absent (MED-007-R2).
- Q: What happens when a rectangle's shape differs from the screen's? → A: The rectangle is treated as the layer's content and fitted with the layer's own CMP-006 fit: fill (the default) crops the overflow around the anchor, fit letterboxes with transparent bars, stretch fills; pixel-accurate reads as fit (a zoom cannot be pixel-accurate). Presets and Custom produce rectangles of the image's own shape, so at fill the first frame of "Zoom in" looks like the plain photo. The acceptance uses rectangles of the output's shape, so the frame shows exactly the rectangle in every mode (MED-007-R3).
- Q: How is the rectangle between start and end computed? → A: Each edge (x, y, width, height) moves linearly with an eased fraction u = elapsed / duration, computed from integer nanoseconds (SHOW-008's segment-relative fraction): elapsed 0 gives the stored start values exactly, elapsed ≥ duration the stored end values exactly. Easing Linear or Ease in and out (smoothstep 3u² − 2u³; default Ease in and out); both are monotonic, so every edge moves monotonically (MED-007-R3, R4).
- Q: Which clock drives the movement, and what happens after the end? → A: Elapsed time starts at 0 on the first drawn frame of a picture and adds each frame's duration from the injected frame clock (already clamped to 0.1 s per frame), so a pause, the background or a stall never makes it jump. After the duration the end rectangle holds (no loop, no reverse: no sudden cut back) until the picture or the movement changes, which restarts it (MED-007-R5).
- Q: How long does the movement last? → A: Duration 2…60 whole seconds, default 10, for a single photo. In a slideshow every slide's movement lasts its dwell: Time mode the slideshow's seconds; Beats mode beats × the beat period while a reliable tempo grid exists, else the seconds setting (MED-007-R8).
- Q: What does Reduce Motion do? → A: The layer shows the start rectangle and does not move (the user's chosen framing, no animation); the photo is cached as a still. Settings notes "Reduce Motion is on: the photo stays at its start framing." (MED-007-R7).
- Q: Is there a movement per slide? → A: No: one setting for the photo layer, shared by the single photo and every slide (each slide restarts it). Per-slide movements are out of scope; the stored shape (one object) can gain a per-slide map later without a version change.
- Q: Which movements does Settings offer? → A: A Ken Burns switch, then Movement: Zoom in (whole image → the centre 2/3), Zoom out (the reverse), Pan left to right (80 % of the image, from its left edge to its right edge, vertically centred), Pan right to left (the reverse), Custom. Custom shows for Start and End a Zoom slider (100…400 %) and Horizontal and Vertical position sliders (0…100 %), all through ACC-005's accessible parameter helper; a preset's values become Custom's starting values. Then Duration (stepper, seconds) and Easing (MED-007-R11).
- Q: Where is the setting stored, backed up and erased? → A: One UserDefaults key `settings.photo.kenBurns` (JSON; absent = off), written by its own store; included in FILE-005 settings backups; erased with Settings (a preference, not media) by FILE-011; removed by the UI-test reset (`AppSettings.allKeys`) (MED-007-R9).
- Q: How do scenes record it? → A: The optional object `kenBurns` on the `photo` asset: `{"start": {"x","y","width","height"}, "end": {…}, "durationMilliseconds": int, "easing": "linear"|"easeInOut"}`, written only when Ken Burns is on; carried verbatim by older versions (`SceneAsset.extra`), no version change. Restoring a document with a photo layer applies it, or turns Ken Burns off when absent or malformed; documents of other visuals leave it unchanged (MED-007-R10).
- Q: How does render caching treat it? → A: While moving, the photo layer declares a time dependency (rendered every frame); while holding (finished, start = end, Reduce Motion, or off) it declares itself still, with a parameter generation that changes whenever the movement, Reduce Motion or the fit changes (MED-007-R6).
- Q: How is acceptance proven? → A: GPU read-back on the Mac through the real compositor with injected frame times: the first frame against the image cropped on the CPU to a 1:1 start rectangle (every pixel within 1/255 in linear light), the frame at the end time against a 2× zoomed end rectangle of a block-coloured image (every pixel not next to a block edge within 1/255), plus a CPU test that every edge is monotonic over a run, a scene round trip, a Reduce Motion GPU test and one UI test under 30 s (MED-007-S1 to S5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A photo slowly zooms and pans (Priority: P1)

A performer shows a photo behind the spectrum and turns on Ken Burns with "Zoom in": the picture starts showing the
whole photo and slowly zooms to its centre over the chosen duration, then holds there.

**Why this priority**: This is the roadmap row: pan and zoom a still between keyframed bounds.

**Independent Test**: Render the photo layer on the GPU with injected frame times; the first frame equals the image
cropped to the start rectangle and the frame at the end time equals the image cropped to the end rectangle.

**Acceptance Scenarios**:

1. **Given** a photo with Ken Burns from a start to an end rectangle, **When** the first frame is drawn, **Then** it shows exactly the start rectangle of the image.
2. **Given** the same, **When** the frame at (or after) the end time is drawn, **Then** it shows exactly the end rectangle.
3. **Given** the same, **When** frames between are drawn, **Then** the shown rectangle moves monotonically from start to end, with no jumps.
4. **Given** Ken Burns turned off, **When** frames are drawn, **Then** the photo is drawn as before (MED-001, CMP-006).

### User Story 2 - Choose the movement in Settings (Priority: P1)

The performer picks a movement (Zoom in, Zoom out, Pan left to right, Pan right to left, or Custom), a duration and an
easing; with Custom they set the start and end framing (zoom and position) with accessible controls.

**Independent Test**: A UI test turns Ken Burns on, picks a movement and sees the summary change.

**Acceptance Scenarios**:

1. **Given** Settings › Photo, **When** Ken Burns is turned on, **Then** the movement, duration and easing controls appear with "Zoom in" chosen.
2. **Given** Custom, **When** the start zoom or position changes, **Then** the stored start rectangle changes and stays inside the image.
3. **Given** VoiceOver, **When** each control is focused, **Then** it reads a name and a value.

### User Story 3 - Ken Burns in a slideshow and in scenes (Priority: P2)

With the slideshow on, every slide moves with the chosen movement, starting again at each slide change and lasting
the slide's dwell. A saved scene recalls the movement.

**Acceptance Scenarios**:

1. **Given** a slideshow in Time mode at 8 s, **When** a slide appears, **Then** it starts at the start rectangle and reaches the end rectangle 8 s later.
2. **Given** a scene saved with Ken Burns, **When** it is restored, **Then** the same rectangles, duration and easing are restored; a scene without the field turns Ken Burns off.

### User Story 4 - Reduce Motion (Priority: P2)

With the system's Reduce Motion on, the photo does not move.

**Acceptance Scenarios**:

1. **Given** Reduce Motion on and Ken Burns on, **When** frames are drawn, **Then** every frame shows the start rectangle, and the layer is cached as a still.

### Edge Cases

- A rectangle outside the image, with zero or negative size, or non-finite: refused by the editor (clamped) and read as absent from a scene.
- Rectangle aspect different from the output: the layer's fit mode decides (fill crops the overflow, fit letterboxes, pixel-accurate reads as fit); the acceptance uses rectangles of the output's aspect.
- Beats mode without a reliable tempo: the movement lasts the slideshow's seconds setting.
- The movement finished: the end rectangle holds until the picture changes.
- Start equals end: a still crop.
- The app paused or in the background: the movement holds and continues on return (frame-duration clamp), it never jumps.
- The photo changes (new photo, slide change, scene restore): the movement starts again from the start rectangle.
- A new photo still loading: the transparent fallback, as before; the movement starts on its first drawn frame.
- A scene from an older version: no field, Ken Burns off. A scene from this version opened by an older one: the field is carried verbatim.

## Requirements *(mandatory)*

### Functional Requirements

- **MED-007-R1**: A Ken Burns movement MUST consist of a start and an end crop rectangle in normalised image coordinates, a duration and an easing.
- **MED-007-R2**: A rectangle MUST be finite, lie inside the image and have a positive size not below a minimum; invalid input MUST be clamped by edits and read as absent from stored data.
- **MED-007-R3**: The first frame drawn after the movement starts MUST show exactly the start rectangle; every frame at or after the duration MUST show exactly the end rectangle.
- **MED-007-R4**: Between them the rectangle MUST follow the easing from start to end monotonically, evaluated on the injected frame clock.
- **MED-007-R5**: The movement MUST restart when the shown picture changes, and MUST NOT jump after a pause or a stall.
- **MED-007-R6**: While the movement is running, the photo layer MUST NOT reuse a cached picture; when it holds (finished, start equals end, Reduce Motion) it MUST be cacheable again.
- **MED-007-R7**: With Reduce Motion on, the layer MUST show the start rectangle without movement.
- **MED-007-R8**: In a slideshow, every slide MUST run the movement over the slide's dwell, restarting at each change.
- **MED-007-R9**: The setting MUST be stored in one UserDefaults key, backed up with the settings, erased with Settings and reset by the UI-test reset.
- **MED-007-R10**: Scenes MUST record the movement as an optional field of the photo asset, with no version change; restore MUST apply it or turn Ken Burns off when absent.
- **MED-007-R11**: Settings MUST offer the presets, Custom with accessible start and end controls, the duration and the easing.
- **MED-007-R12**: The plain movement model MUST build and be tested on Linux; per-frame evaluation MUST NOT allocate.

### Key Entities

- **Crop rectangle**: x, y, width, height in image fractions (0…1, top-left origin).
- **Ken Burns movement**: start, end, duration, easing.
- **Ken Burns setting**: the movement or off.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **MED-007-S1**: On the GPU, the first frame matches the image cropped to the start rectangle and the end frame matches it cropped to the end rectangle, every compared pixel within 1/255.
- **MED-007-S2**: Across a run, each rectangle edge changes monotonically from start to end.
- **MED-007-S3**: A scene with a movement round-trips unchanged; malformed fields read as absent.
- **MED-007-S4**: Under Reduce Motion every frame equals the start-rectangle frame and the photo renders once, then is reused.
- **MED-007-S5**: The Settings UI test passes in under 30 s; every new unit test runs in under 2 s.

## Assumptions

- One setting for the photo layer, shared by the single photo and every slide of the slideshow.
- Rendering stays in the existing photo layer (no new layer kind).
- Real-device smoothness (D1) is a `{device}` task.
