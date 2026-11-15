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
- Rectangle aspect different from the output: the layer's fit mode decides (fill crops the overflow, fit letterboxes); the acceptance uses rectangles of the output's aspect.
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
