# Feature Specification: CMP-009 Luma Key

**Feature Branch**: `feature/cmp-009` (spec directory `220-cmp-009-luma-key`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-009 (Luma key) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Convert selected luminance range to transparency." Acceptance,
verbatim: "Black key test eliminates dark region without affecting bright patch." Verification: unit
tests, snapshots and GPU performance. P2; depends on CMP-001 (unified layer protocol, integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-009-R1…`, success criteria `CMP-009-S1…`, tasks `CMP-009-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `31da9491`)

The row's gap status is "Gap candidate". The audit confirms a full gap: a layer can be cut by a shape
(CMP-007) or faded by a gradient (CMP-008), both by position; nothing makes a layer transparent by its
own brightness.

| Area | Today | Gap for this row |
|---|---|---|
| Layer composite settings (CMP-001, `LayerCompositeSettings`) | opacity, blend, transform, fit, the CMP-007 shape `mask` and the CMP-008 `gradientMask`. | No key. |
| Compositor mask path (CMP-007, CMP-008) | One coverage term (shape × gradient, from one per-layer mask block) in every draw path: normal layers through the masked "over" pass (no extra pass), other modes in the blend pass. | The coverage depends only on position, never on the layer's colour. |
| CPU references | `LayerMaskGeometry`, `LayerGradientGeometry`, `LayerBlend` (sRGB encode/decode of straight colour). | No key reference. |
| Scene format (SCN-001) | `composite.mask`, `composite.gradientMask`, optional, written only when set. Version 1. | No place for a key. |
| Layer inspector (CMP-015, CMP-008) | Mask and Gradient sections with help, undo and ACC-005 sliders. | No key editor. |
| Goldens (QA-002) | `GradientMask` goldens on the Mac host and the iOS simulator. | No key golden. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the recommended, conservative option.

- Q: Is the key a new kind of the CMP-007 mask, a field with its own `enabled` flag, or a separate
  optional value whose presence turns it on? → A: **A separate optional value**:
  `LayerCompositeSettings.lumaKey` and the saved `composite.lumaKey`; nil (absent) means no key, as for
  `mask` and `gradientMask`. No `enabled` flag (it would add a second "off" state that saves and
  round-trips differently from absence); the inspector's toggle sets or removes the value. The key
  joins the CMP-007/CMP-008 mask block (one more four-float row), so no pass and no pipeline is added
  (layer alpha = shape coverage × gradient alpha × key keep factor).
- Q: In which space is luminance measured: linear light, or the displayed (sRGB-encoded) values? →
  A: **Displayed values**: Rec. 709 luma Y′ = 0.2126·R′ + 0.7152·G′ + 0.0722·B′ of the layer's straight
  colour (premultiplied colour ÷ alpha, alpha 0 reads 0), each channel clamped to 0…1 and sRGB-encoded
  with the same curve the CMP-004 blend modes use. Thresholds then follow what the user sees (a mid
  grey on screen is Y′ ≈ 0.5, not 0.21), which is how video luma keys are set. Rejected: linear-light
  luminance (dark thresholds crowd into the bottom 5 % of the slider).
- Q: What shape does the transition at the edge of the range take, and what are the limits? → A: A
  **linear ramp** outside the range: keyed amount k = 1 for low ≤ Y′ ≤ high, k = 1 − (low − Y′)/s below
  and 1 − (Y′ − high)/s above, clamped to 0…1 (s = softness; s = 0 is a hard cut, Y′ inside keyed);
  keep factor = 1 − k, or k when inverted. Low and high are each clamped to 0…1 with low ≤ high (the
  live model swaps a reversed pair; the decoder swaps with `valueClamped`); softness is clamped to
  0…0.5. Linear rather than smoothstep keeps the ramp strictly monotonic and the CPU reference exact.
- Q: Where does the key read the colour, relative to opacity, masks and transforms? → A: On the
  layer's **sanitised picture colour at the shown pixel** (the same value the draw path already has:
  per-pixel read for identity transforms, bilinear sample for transformed layers), before opacity, so
  opacity never changes which pixels are keyed. Its keep factor multiplies the premultiplied colour
  and alpha together with the masks' coverage in both the masked "over" path and the blend path.
- Q: What does the inspector offer, with which defaults and undo steps? → A: A "Luma Key" section
  after Gradient: a **Luma Key** toggle (`layerControl.lumaKey`); when on, **Low**, **High** (0…1, step
  0.05) and **Softness** (0…0.5, step 0.02) ACC-005 sliders (`layerControl.lumaLow|lumaHigh|lumaSoftness`)
  and an **Invert Key** toggle (`layerControl.lumaInverted`). Turning it on gives a black key: low 0,
  high 0.1, softness 0.05, not inverted. Dragging Low above High moves High with it (and the reverse).
  Each drag or toggle is one undo step with key `layer.<kind>.<parameter>`, as the CMP-015 sliders.
  "GPU performance" is an opt-in Mac bench (never asserted, "not device evidence") plus a `{device}`
  task for D1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Key out a luminance range (Priority: P1) 🎯 MVP

A scene author turns on a luma key for a layer and chooses a luminance range (low and high). The
parts of the layer whose luminance lies inside the range become transparent; the rest stays exactly
as it was. A softness widens the edge of the range so the layer fades out gradually instead of
cutting off. Invert keeps only the range and hides everything else. The classic use is a "black key":
the dark background of a visual disappears so the layers beneath show through, while the bright
parts stay untouched.

**Why this priority**: It is the row's observable behavior and its acceptance criterion.

**Independent Test**: Composite a layer containing a black region and a bright patch over a known
background with a black key, read the pixels back, and check that the black region contributes
nothing and the bright patch is unchanged.

**Acceptance Scenarios**:

1. **Given** a layer with a black region and a bright patch and a black key (range from 0 to a low
   threshold), **When** composited, **Then** the black region's alpha is 0 (within 1/255) and the
   bright patch's colour and alpha equal the unkeyed layer's (within 1/255).
2. **Given** a softness above 0, **When** a luminance ramp is composited, **Then** alpha never rises
   as luminance moves into the range from either side, and is 1 beyond the softness band.
3. **Given** Invert, **When** composited, **Then** only the range is kept (the complement of 1).
4. **Given** a key together with a shape mask and a gradient, **When** composited, **Then** the
   layer's alpha is the product of the three.

---

### User Story 2 - Edit the key in the inspector (Priority: P1)

In the layer inspector, the author turns the key on, sets Low, High and Softness with sliders and
flips Invert. Every control has help, is adjustable with VoiceOver and is one undo step per drag.

**Why this priority**: The row says the range is selected; without an editor it cannot be.

**Independent Test**: UI test: turn the key on, drag a slider, undo; unit tests of the edit rules.

**Acceptance Scenarios**:

1. **Given** a layer without a key, **When** the author turns the key on, **Then** a black key
   appears with default values.
2. **Given** Low dragged above High (or High below Low), **Then** the other end follows, so the range
   is never empty-inverted.
3. **Given** an edit, **When** the author undoes, **Then** the previous key returns.

---

### User Story 3 - Scenes keep the key (Priority: P1)

A scene stores each layer's key. Opening and saving keeps it exactly.

**Why this priority**: Without persistence, the edit is lost on relaunch.

**Independent Test**: Decode → encode, and decode → load → capture → encode of scenes with a key.

**Acceptance Scenarios**:

1. **Given** a scene with a key, **When** decoded and encoded, **Then** the bytes are identical.
2. **Given** the same scene, **When** loaded and captured, **Then** the key is unchanged.
3. **Given** out-of-range values or unknown keys, **When** decoded, **Then** values are clamped with
   `valueClamped` and unknown keys dropped with `droppedField`.
4. **Given** a scene written before this feature, **When** decoded and encoded, **Then** the bytes and
   the format version are unchanged.

### Edge Cases

- Fully transparent pixels: their luminance is taken as 0; whatever the key, they stay transparent.
- Over-bright (HDR, above 1) colour: luminance is measured on the colour clamped to 0…1.
- Low equal to High with softness 0: only that exact luminance is keyed.
- Low above High in a file: the two are swapped (with a warning).
- A transformed layer (CMP-005): the key reads the layer's resampled colour at the shown pixel.
- Every blend mode and any opacity: the key applies before blending, as the masks do.
- A key whose range keys nothing in the picture: the layer is drawn as without a key (within 1/255).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-009-R1**: The layer contract MUST offer an optional luma key per layer, independent of the
  shape and gradient masks, with a range low…high (0…1), a softness and an invert flag.
- **CMP-009-R2**: The key's keep factor at luminance Y MUST be 0 inside low…high, 1 at or beyond
  softness outside the range, and rise linearly in between; inverted, it MUST be 1 minus that. Hence
  monotonic on each side of the range.
- **CMP-009-R3**: Luminance MUST be the Rec. 709 luma of the layer's own straight (unpremultiplied)
  colour, clamped to 0…1 and sRGB-encoded, independent of the layer's opacity (see Clarifications).
- **CMP-009-R4**: The keep factor MUST multiply the layer's colour and alpha (premultiplied), so a kept
  pixel's colour and alpha are unchanged.
- **CMP-009-R5**: A plain reference calculation (no GPU, every platform) MUST give the keep factor of
  any colour, matching the GPU within 1/255.
- **CMP-009-R6**: The key MUST combine with shape and gradient masks by multiplication and work with
  every blend mode, opacity and transform.
- **CMP-009-R7**: The key MUST NOT add a render pass or pipeline for normal-mode layers, and layers
  without a key MUST be drawn exactly as before.
- **CMP-009-R8**: The scene format MUST store the key as an optional value written only when set,
  with the format version unchanged; scenes without it MUST encode byte-identically and a key MUST
  round-trip byte for byte.
- **CMP-009-R9**: Out-of-range values MUST be clamped on decode with `valueClamped`, a reversed range
  swapped with `valueClamped`, and unknown keys dropped with `droppedField`.
- **CMP-009-R10**: The layer inspector MUST turn the key on and off and edit low, high, softness and
  invert, with help, VoiceOver-adjustable controls and one undo step per drag or choice.
- **CMP-009-R11**: A key change applied to the stack MUST show from the next frame without
  re-creating the layer or its pictures.

### Key Entities

- **Luma key**: low, high (0…1, low ≤ high), softness (0…0.5), invert; absent means no key.
  Default when turned on: low 0, high 0.1, softness 0.05, not inverted.
- **Keep factor**: 0…1 per pixel from the pixel's luminance, multiplying the layer's colour and alpha
  (with the shape coverage and gradient alpha when set).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-009-S1**: In a GPU read-back of the black-key fixture, 100 % of dark-region pixels have alpha
  ≤ 1/255 and 100 % of bright-patch pixels match the unkeyed colour and alpha within 1/255.
- **CMP-009-S2**: Over a luminance ramp with softness, 0 samples move against the expected direction
  by more than 1/255, and every sample matches the reference within 1/255.
- **CMP-009-S3**: One black-key golden matches on the Mac host and the iOS simulator under QA-002's
  rule.
- **CMP-009-S4**: 100 % of key scene round trips are byte-identical; scenes without keys and existing
  goldens are unchanged; QA-004's meta-test passes with no new version.
- **CMP-009-S5**: The GPU time of a full-screen keyed layer is measured on the Mac and recorded as
  "not device evidence"; the device measurement on D1 is a `{device}` task.
- **CMP-009-S6**: In the UI test, turning the key on, one slider drag and one undo complete in under
  30 s.

## Assumptions

- The key is a separate optional field (`composite.lumaKey`) beside the masks, so it combines with
  both.
- Older app versions drop the new field with `droppedField` (format version 1 tolerates unknown keys)
  and draw the layer unkeyed, accepted as for any newer optional value.
- Chroma keys and keying by other channels are out of scope.
