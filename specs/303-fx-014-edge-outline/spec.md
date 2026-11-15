# Feature Specification: FX-014 Edge Outline

**Feature Branch**: `feature/fx-014` (spec directory `303-fx-014-edge-outline`)

**Created**: 2026-11-15

**Status**: Implemented 2026-11-15 (FX-014-T01-T17 verified on the Mac and an own iOS 27.2 simulator; T18 `{device}` open)

**Input**: User description: "Implement FX-014 (Edge outline) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Highlight image gradients with adjustable threshold and color." Acceptance, verbatim: "Flat image
produces no outlines and checkerboard produces boundaries." P2, effort M, depends on VIS-001 (integrated)."

Identifiers in this feature carry the roadmap ID: requirements `FX-014-R1…`, success criteria `FX-014-S1…`, tasks
`FX-014-T01…`, research decisions `FX-014-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor),
FX-002 (tone map), FX-006 to FX-008 (chromatic split, directional and radial blur), FX-010 (echo), FX-012 (mosaic;
ADR-0110, the template), FX-013 (posterization, integrated in parallel), FX-019 (flash guard), FX-020 (effect chains;
ADR-0054), ACC-005 (accessible sliders), ACC-012 (sensory safety clamp), PERF-004 (texture pool), SHD-011 (shader
policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy).

## Baseline: the audit (2026-11-15, commit `8878f057`)

**No edge, outline or Sobel effect exists in the output chain.** Searching the packages and the app for "sobel",
"edge outline" and "outline" finds only unrelated uses (text stroke, UI borders).

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder` (Trails,
Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic) → FX-019 flash guard → output pass (grade, FX-002
tone map). FX-012 (mosaic) is the newest instance of the pattern this feature follows: an own pass writing one pooled
picture while active, walked in `Compositor.encodeOutputEffects`, its shader a module constant spliced into the
reviewed compile site in `Compositor.init` and listed in `CompositorShaderSources.archived`; Color listed before it is
folded into FX-020's grade pass right before it; scenes store the entry only while it is on.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: Which gradient, on which value? → A: A 3 × 3 Sobel operator on the linear-light luminance (Rec. 709 weights) of
  the composite's premultiplied colour, the value the output chain carries. Edge strength is the gradient magnitude
  divided by 4, so a hard step from black to white along a row or column has strength 1. Linear needs no transfer
  function in the pass, keeps the CPU reference exact, and is independent of FX-013's display-stage changes. Applied
  to FX-014-R3.
- Q: What does the threshold do? → A: Threshold 0.02…1 (default 0.2). The outline mask is 0 where the strength is at or
  below the threshold and rises smoothly to 1 over a fixed band of 0.1 above it (smoothstep). A strength at or below
  the threshold is never outlined, so contrast below the threshold draws nothing. The lower bound above 0 keeps
  floating-point noise on flat areas from ever drawing. Applied to FX-014-R4.
- Q: Which modes? → A: Overlay (default): the outline colour is mixed over the picture by the mask; where the mask is 0
  the pixel is the input pixel, unchanged. Outline only: the outline colour over opaque black. Applied to FX-014-R5.
- Q: Line width? → A: 1, 2 or 3 pixels (default 1): the Sobel taps sit that many pixels from the centre, so a step
  between two flat regions is outlined in a band 2 × width pixels wide, centred on the step. Applied to FX-014-R6.
- Q: Frame edges? → A: Every tap is clamped to the frame, so a flat picture has zero gradient everywhere including the
  border and no outline appears at the frame edge. Applied to FX-014-R3.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Is Edge outline a global setting or a per-scene value? → A: Both, like FX-006 to FX-012: a global setting the
  visuals use, which a scene or effect-chain preset with an `fx.edgeOutline` entry overwrites when opened; a scene
  without one leaves it alone. Applied to FX-014-R10, R11.
- Q: How is the colour stored? → A: In settings as a six-digit sRGB hex string (`settings.edgeOutline.color`,
  "FFFFFF"; anything unreadable is white); in the scene entry as `red`, `green`, `blue` numbers 0…1. The colour well
  offers no opacity (the outline is opaque). Applied to FX-014-R2, R10, R11.
- Q: How are width and mode chosen and stored? → A: Two segmented choices: Width "1 px / 2 px / 3 px" (stored as a
  whole number, rounded and clamped), Mode "Overlay / Outline only" (stored as the string `overlay` or `outlineOnly`,
  anything else reads as overlay; in a scene `mode` 0 or 1, ≥ 0.5 reads as outline only). Applied to FX-014-R9, R11.
- Q: What does VoiceOver say for the threshold? → A: "Threshold", the value with two decimals ("0.20"), one hundredth
  per swipe; the on-screen readout is the same "0.20". Applied to FX-014-R9.
- Q: What happens where the picture holds non-finite values? → A: A non-finite edge strength counts as no edge: the
  mask is 0 and overlay keeps the input pixel (FX-002 handles the non-finite value downstream). Applied to the Edge
  Cases and FX-014-R4.

### Session 2026-11-15 (speckit-analyze)

- Finding A1 (inconsistency): data-model.md described the shader block twice with different fields; it now gives one
  48-byte layout (`colour`, `last`, `threshold`, `width`, `mode`), as contract C2 uses. Finding A2 (coverage): R15
  (ACC-012 colour cap) is checked in the model test (T03) and the app's effective value (T14); R13's reference is
  T02/T03. Finding A3: no settings key may contain "focus", "exposure" or "whitebalance" (CAM-005 and siblings); the
  `settings.edgeOutline.*` keys do not. No constitution conflicts; 15/15 requirements and 7/7 success criteria have
  tasks (S7 is the `{device}` task T18).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Outline the picture's edges (Priority: P1)

A performer shows the Camera visual and turns on Settings → Edge outline: the boundaries between areas of different
brightness are drawn in a chosen colour over the picture. A Threshold slider sets how strong an edge must be to be
drawn, a Width choice sets the line width, a colour well sets the colour, and a mode switch shows the outline alone on
black.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: a checkerboard of 8-pixel squares shows outlines exactly along the square boundaries and nowhere
inside a square.

**Acceptance Scenarios**:

1. **Given** Edge outline on (overlay, width 1, threshold 0.2), **When** a black-and-white checkerboard of 8-pixel
   squares is shown, **Then** the pixels on both sides of every square boundary are the outline colour and every other
   pixel is unchanged.
2. **Given** the threshold above the checkerboard's contrast, **When** it is shown, **Then** no pixel is outlined.
3. **Given** the values set, **When** the app is relaunched, **Then** the same values are applied.

---

### User Story 2 - A flat picture has no outline (Priority: P1)

A performer shows a flat colour: nothing is drawn, at the borders included. With the effect off, the picture is exactly
what the app showed before.

**Acceptance Scenarios**:

1. **Given** Edge outline on in overlay mode, **When** a flat picture of any colour is shown, **Then** every output
   pixel is bit-identical to the input.
2. **Given** outline-only mode, **When** a flat picture is shown, **Then** every pixel is black.
3. **Given** the effect off, **When** any frame is shown, **Then** the output is bit-identical to the output without
   this feature and no extra picture memory is held.

---

### User Story 3 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Edge outline on the Effect order screen, saves a scene and an effect-chain preset, and gets the
same outline back when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Edge outline on, **When** it is opened, **Then** its values and position are restored;
   a scene without the entry leaves the current values as they are (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes exactly
   as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit; a fractional width is
  rounded; an unreadable colour is white.
- A frame smaller than 2 pixels in either direction: passes through.
- Transparent areas: luminance is taken from the premultiplied colour; the overlay mixes premultiplied colour and alpha
  together (the outline colour is opaque).
- Non-finite picture values: a non-finite edge strength counts as no edge (mask 0); FX-002 handles the value
  downstream.
- Sensory safety: under a profile with an intensity limit below 1 the outline colour is scaled by that limit; the flash
  guard still judges the shown frame.
- Visuals that are not compositor-backed: unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-014-R1**: Edge outline (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-014-R2**: Settings: threshold 0.02…1 (default 0.2, step 0.01), width 1…3 pixels (default 1), colour (sRGB, default
  white), mode Overlay (default) or Outline only.
- **FX-014-R3**: Edge strength at pixel p is |(Gx, Gy)| ÷ 4, Gx and Gy the 3 × 3 Sobel responses of linear luminance with
  taps at offsets of −width, 0, +width, each tap clamped to the frame.
- **FX-014-R4**: The mask is smoothstep(threshold, threshold + 0.1, strength): exactly 0 at or below the threshold and
  where the strength is not finite.
- **FX-014-R5**: Overlay: where the mask is 0 the output pixel is the input pixel bit for bit; elsewhere the input mixed
  toward the opaque outline colour by the mask. Outline only: opaque black mixed toward the outline colour by the mask.
- **FX-014-R6**: A step between two flat regions is outlined on 2 × width pixels across the step and nowhere else.
- **FX-014-R7**: Edge outline is an FX-020 reorderable output effect (`fx.edgeOutline`), appended after Mosaic in the
  standard order. Its position is honoured; the flash guard and the tone map always run after it.
- **FX-014-R8**: The effect is active only when on and the frame is at least 2 × 2; otherwise no pass runs and the
  output is bit-identical to the output before this feature.
- **FX-014-R9**: Settings has an "Edge outline" section: a toggle and, while on, a Threshold slider with ACC-005 spoken
  values, a Width choice, a colour well, a mode choice and help text. The Effect order screen lists it with its own
  switch.
- **FX-014-R10**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-014-R11**: Scenes and effect-chain presets store the effect as an `fx.edgeOutline` entry in FX-020's `effects`
  list, written only while it is on; out-of-range values are clamped and reported; scenes without it encode
  byte-identically.
- **FX-014-R12**: An active outline uses one pooled picture at output size and one full-screen pass per frame, no
  per-frame allocation; the picture returns to the pool when it turns inactive, the size changes or the visual is
  released.
- **FX-014-R13**: A plain-software reference of the strength, the mask and the output exists, testable without a GPU
  (Linux), and the GPU output matches it on the acceptance pictures.
- **FX-014-R14**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.
- **FX-014-R15**: Under ACC-012 an intensity limit below 1 scales the outline colour's linear components by the limit.

### Key Entities

- **Edge outline setting**: on/off, threshold, width, colour (sRGB), mode.
- **Outline mask**: per pixel, 0…1, from the edge strength and the threshold.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-014-S1**: Flat pictures of several colours: overlay output is bit-identical to the input; outline-only output is
  black at every pixel, border pixels included.
- **FX-014-S2**: An 8-pixel checkerboard: the outlined pixels are exactly the software reference's mask (both sides of
  every boundary, within the width), and none lie inside a square.
- **FX-014-S3**: With the threshold above the checkerboard's contrast, no pixel is outlined.
- **FX-014-S4**: Off is bit-identical to the output without the feature; all existing RenderGoldens pass unchanged.
- **FX-014-S5**: A scene and a preset with Edge outline round-trip to the same values; a scene from before the feature
  encodes byte-identically.
- **FX-014-S6**: A user can find Edge outline, turn it on and change the threshold (UI test under 30 s); the values
  survive a relaunch (setting test with a reloaded store).
- **FX-014-S7**: The device frame rate with Edge outline on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-006 to FX-012, FX-019 and FX-020 are as integrated; FX-013 changes the colour grade in parallel and
  adds no effect kind.
- Live audio-reactive modulation of the threshold is not wired.
