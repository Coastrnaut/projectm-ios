# Feature Specification: CMP-006 Aspect Fitting

**Feature Branch**: `feature/cmp-006` (spec directory `101-cmp-006-aspect-fitting`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-006 (Aspect fitting) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Offer fill, fit, stretch and
pixel-accurate modes." Acceptance, verbatim: "Portrait media maintains chosen crop across landscape
output." Verification: unit tests, snapshots and GPU performance. Depends on CMP-005 (transform
controls, integrated); works with CMP-004 (blend modes, integrated) and SCN-001 (scene format)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-006-R1…`, success criteria `CMP-006-S1…`, tasks `CMP-006-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `50a0241d`)

The row's gap status is "Gap candidate". The audit confirms a partial gap: two of the four modes
exist for photos only, and nothing is chosen per layer or saved.

| Layer or area | How it is fitted to the output today | Gap for this row |
|---|---|---|
| Output size | Every layer draws into a picture of the output's pixel size (CMP-001). The output is the visual's drawable: the device screen (`contentScaleFactor` pixels per point), or the external display window at its render scale (OUT-001). Recordings (REC-003) and saved frames (REC-001) take the same composite, so they have the drawable's pixel size. Rotating the device or moving to an external display changes the output size; layers are re-prepared at the new size. | None; the size is known per frame (`LayerFrameContext.outputWidth/Height`, `contentScale`). |
| Photo (MED-001) | `ImagePictureGeometry` maps output points to image coordinates: `fill` (default; aspect fill, centred crop) or `fit` (aspect fit, transparent bars), fixed per `ImageLayerSource` at creation (`mode`). Nothing in the app or a scene chooses it. | No stretch or pixel-accurate mode; no anchor; not per stack entry; not saved. |
| Video (MED-002) | `VideoLayerSource` reuses CameraLayer's `CameraPictureGeometry`: aspect fill only, centred, after the track's quarter-turn rotation; alpha 1 everywhere. | Fill only; not chosen or saved. |
| Camera (CAM-001/002) | `CameraPictureGeometry`: aspect fill after rotation, optional mirror. CAM-007 (crop and rotation, in progress in parallel) is adding its own Fill/Fit there. | Out of scope here (CAM-007 owns the module); a later follow-up adopts the shared model (CMP-006-R12). |
| Text (MED-009) | `TextLayout` sizes text from the picture height and lays it out inside 5 % margins; it is drawn at output resolution. | None: no intrinsic pixel size, nothing to fit. |
| Generator graphs (SHD-002), materials (SHD-001) | The shaders use square units, `(p − size/2) ÷ min(width, height)`: drawn at output resolution, never stretched. | None. |
| Spectra (VIS-001/002) | The circular spectrum keeps its radius within the shorter side at any aspect; the linear spectrum spans the width. Drawn at output resolution. | None. |
| Layer transform (CMP-005) | Applied by the compositor to the whole layer picture (affine, bilinear sampling, transparent outside); pixel lengths kept under rotation. | Fitting must happen before it, inside the picture. |
| Scene format (SCN-001, ADR-0028) | `composite` is a closed object: `opacity`, `blend`, `transform`; other keys are dropped with `droppedField`. | No place for a fit mode. |
| UI | No screen edits a layer's opacity, transform, blend or fit; stacks come from code, scenes and show cues. | None required (Clarifications). |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: What does "one content pixel per output pixel" mean on a 3× screen versus a recording or an
  external display? → A: One content pixel per **output (drawable) pixel**, whatever the device's
  points-to-pixels scale (CMP-006-R4). The screen, saved frames, recordings and the external display
  all show the same composite, so a recording is pixel-identical to the screen and no pixel is ever
  resampled; the frame context's `contentScale` is not used. The function takes an optional
  output-pixels-per-content-pixel factor (default 1) so a later "point-accurate" option can reuse it.
  Rejected: scaling by `contentScale` (a 3× phone would triple each picture pixel, which is not
  pixel-accurate, and the recording would differ from an external display of the same size).
- Q: What does a layer with no fit set draw, and what is the default? → A: The layer kind's default,
  which for photo and video is `fill` anchored at the centre, exactly today's drawing (CMP-006-R7).
  "No fit" stays distinct from "fill set explicitly" so that old scenes re-save byte-identically
  (CMP-006-R9). No default changes, so no ADR is needed.
- Q: How is the fit saved in a scene? → A: As an optional closed object `composite.fit` =
  `{"mode": "<name>", "anchor": {"x": <0…1>, "y": <0…1>}}`; `mode` is required inside it, `anchor` is
  optional (centre) and clamped to 0…1 with a `valueClamped` warning. Written only when set; the
  format version stays 1, so QA-004's migration matrix gains no row. An unknown mode name is kept
  verbatim (decode, encode, load and capture), gives the new warning `unsupportedFitMode`, which
  SCN-012's repair report lists as a note, and is drawn as the layer's default (CMP-006-R9, R10).
  An older app reading a newer file drops `fit` with its existing `droppedField` warning.
- Q: What is the anchor, and is it saved? → A: A point in content fractions (0…1; default centre)
  that lands on the same fraction of the output in fill, fit and pixelAccurate (stretch ignores it).
  In fill it picks the kept part of the crop; in fit and pixelAccurate it places the picture inside
  the output. It is saved with the mode, because it is the "chosen crop" of the acceptance
  criterion (CMP-006-R5).
- Q: Is there a fit-mode picker in the UI? → A: No. No screen edits a layer's opacity, transform,
  blend or fit today (stacks come from code, scenes and show cues); the inspector row that edits a
  stack adds the picker. The row's "GPU performance" is a Mac measurement of a photo layer per mode,
  recorded as not device evidence, with no wall-clock assertion in tests (CMP-006-S5).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose how a photo or video fills the output (Priority: P1)

A scene author (or a show cue, or code) chooses for a photo or video layer one of four modes:
fill (cover the output, crop the overflow), fit (show the whole picture, transparent bars),
stretch (cover the output exactly, ignoring the picture's shape) or pixel-accurate (one picture
pixel per output pixel, centred, cropped if larger).

**Why this priority**: It is the row's observable behavior.

**Independent Test**: Compute the placement of portrait and landscape pictures in portrait and
landscape outputs for each mode and check coverage, visibility and shape; then render a marker
picture on the GPU and read the pixels back.

**Acceptance Scenarios**:

1. **Given** a 1080 × 1920 picture and a 1920 × 1080 output, **When** the mode is fill, **Then**
   every output pixel shows the picture, the picture keeps its shape, and the crop is centred.
2. **Given** the same, **When** the mode is fit, **Then** the whole picture is visible, keeps its
   shape, and the bars left and right are transparent.
3. **Given** the same, **When** the mode is stretch, **Then** the picture's corners land on the
   output's corners.
4. **Given** a 300 × 500 picture and an 800 × 600 output, **When** the mode is pixel-accurate,
   **Then** the picture covers exactly 300 × 500 output pixels, centred, each output pixel showing
   one picture pixel unresampled.

---

### User Story 2 - The chosen crop survives a change to landscape output (Priority: P1)

A portrait photo or video shown in fill, fit or pixel-accurate mode keeps the same behaviour and
the same anchor when the output turns landscape: the device rotates, the visual moves to an
external display, or a landscape recording is made.

**Why this priority**: It is the row's acceptance criterion.

**Independent Test**: The same picture, mode and anchor placed in a portrait output and then in a
landscape output: the anchor point of the picture lands on the same fractional point of the output
both times, the shape is kept, and the mode's rule (cover, fully visible, 1:1) still holds; on the
GPU, marker pixels are found where the geometry predicts at both sizes.

**Acceptance Scenarios**:

1. **Given** a portrait picture in fill with the anchor at the top centre, **When** the output goes
   from portrait to landscape, **Then** the picture's top centre stays at the output's top centre
   and the output stays covered.
2. **Given** any mode except stretch, **When** the output size changes, **Then** one picture pixel
   stays square on the output (pixel aspect 1).
3. **Given** a layer that also has a CMP-005 transform and a CMP-004 blend mode, **When** the output
   size changes, **Then** fitting happens inside the layer picture first and the transform and
   blend apply to the fitted picture exactly as before.

---

### User Story 3 - Scenes keep the mode (Priority: P2)

A scene stores each layer's fit mode and anchor. Opening it shows the mode; saving writes it back;
a mode name from a newer version is kept, reported, and drawn as the layer's default.

**Why this priority**: Scenes are how layer settings reach users today.

**Independent Test**: Decode, validate, load, capture and encode a scene with each mode and one
unknown mode.

**Acceptance Scenarios**:

1. **Given** a scene with a photo in `pixelAccurate` anchored at (0.5, 0), **When** it is loaded and
   captured again, **Then** the saved bytes carry the same mode and anchor.
2. **Given** a layer with an unknown mode name, **When** loaded, **Then** the repair report lists
   it, the layer draws in its default mode, and capture writes the unknown name back.
3. **Given** a scene written before this feature (no fit), **When** loaded and saved, **Then** the
   bytes are unchanged and the layers draw exactly as before.

### Edge Cases

- A zero or negative content or output size: the identity placement (nothing to fit; no crash).
- A picture exactly the output's shape: fill, fit and stretch are the same placement.
- Pixel-accurate with a picture larger than the output: cropped around the anchor; with an odd
  size difference, the picture's origin is rounded to a whole output pixel so no pixel is resampled.
- Anchor values outside 0…1: clamped (warning when read from a scene).
- A fit set on a layer without intrinsic pixel size (text, spectra, materials, graphs, projectM):
  kept and saved, no effect on drawing.
- A video with a quarter-turn rotation: fitted on its upright size.
- Fit bars on a video: transparent (the video was opaque everywhere before).
- Device rotation during playback: the next frame uses the new output size; nothing is reloaded.

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-006-R1**: The layer contract MUST offer four fit modes with stable names `fill`, `fit`,
  `stretch` and `pixelAccurate`.
- **CMP-006-R2**: A plain function (no GPU, every platform) MUST compute, from the content's pixel
  size, the output's pixel size, the mode and an anchor (default centre), the visible part of the
  content as a texture-coordinate rectangle, and from it the content-to-output placement composed
  with a CMP-005 transform.
- **CMP-006-R3**: fill MUST scale uniformly so the content covers the output and crop the overflow
  around the anchor; fit MUST scale uniformly so the content is fully visible, with transparent
  output outside it; stretch MUST map the content's corners to the output's corners.
- **CMP-006-R4**: pixelAccurate MUST show one content pixel per output pixel, positioned by the
  anchor, with the content's origin on a whole output pixel, cropped where it overflows and
  transparent where it does not reach.
- **CMP-006-R5**: The anchor MUST be a point in content fractions (0…1, clamped) that lands on the
  same fraction of the output, in every mode except stretch, at every output size.
- **CMP-006-R6**: In every mode except stretch, one content pixel MUST cover a square area of output
  pixels (pixel aspect 1).
- **CMP-006-R7**: Photo and video layers MUST draw with their stack entry's fit mode and anchor,
  shown from the next frame after a stack apply, without reloading or re-decoding; with no fit set
  they MUST draw exactly as before this feature (fill, centred).
- **CMP-006-R8**: Fitting MUST happen inside the layer picture, before the CMP-005 transform,
  CMP-003 opacity and CMP-004 blend mode, which MUST apply unchanged.
- **CMP-006-R9**: The scene format MUST store a layer's fit as an optional `composite.fit` value
  (mode name and anchor), written only when set, with the format version unchanged; scenes without
  it MUST encode byte-identically.
- **CMP-006-R10**: An unknown mode name MUST be kept through decode, encode, load and capture,
  warned about by validation and listed by SCN-012's repair report, and drawn as the layer's
  default.
- **CMP-006-R11**: Layers without intrinsic pixel size MUST keep drawing at output resolution; a fit
  set on them is kept and saved but has no effect.
- **CMP-006-R12**: The specification MUST record how the camera layer adopts the shared model after
  CAM-007, with compatible mode names.

### Key Entities

- **Fit mode**: one of fill, fit, stretch, pixelAccurate.
- **Fit**: a fit mode plus an anchor (content fractions, default centre), per layer.
- **Fit placement**: the visible content rectangle (size and offset in content fractions) for one
  content size, output size and fit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-006-S1**: For a table of portrait and landscape content × portrait and landscape output ×
  four modes, 100 % of cases meet their rule: fill covers the output, fit shows all of the content,
  stretch maps corners to corners, pixelAccurate is 1:1, and pixel aspect is 1 except in stretch.
- **CMP-006-S2**: For every mode except stretch and anchors at the centre, a corner and an edge
  midpoint, the anchor lands on the same output fraction in a portrait and a landscape output
  (within 1e-9, or within one output pixel for pixelAccurate's rounding).
- **CMP-006-S3**: GPU read-back of a portrait marker picture composited into a portrait and then a
  landscape output finds every marker where the geometry predicts, for each mode, including one
  case with a non-normal blend mode and one with a CMP-005 transform.
- **CMP-006-S4**: Scene round trips keep every mode and anchor; scenes without a fit and every
  existing golden render are unchanged.
- **CMP-006-S5**: The GPU time of a photo layer per mode is measured on the Mac and recorded as
  "not device evidence"; no mode adds a render pass.

## Assumptions

- No layer-editing screen exists, so no UI is added; the inspector row that edits a stack adds a
  picker later.
- The camera layer is left to CAM-007; video stops depending on CameraLayer's fill geometry but
  keeps its rotation type.
- Older app versions read a scene with `composite.fit` and drop it with a `droppedField` warning
  (version 1 tolerates it); that loss is accepted, as for any newer optional value.

## Camera adoption (follow-up after CAM-007; CMP-006-R12)

CAM-007 adds Fill/Fit to the camera layer inside the CameraLayer module, which this feature does
not touch. Once both are integrated, a follow-up row:

1. maps CAM-007's mode names onto `LayerFitMode` (`fill`, `fit`, plus `stretch` and
   `pixelAccurate`; the names here were chosen to match);
2. computes the camera's visible rectangle with the shared fit function on the **upright** camera
   size (after rotation, before the mirror), as video does here, so a portrait camera keeps its
   crop on a landscape output too;
3. makes the camera layer adopt the compositor's fit hook so a stack entry's `composite.fit`
   reaches it, and adds letterbox transparency to the camera shader for `fit`.
