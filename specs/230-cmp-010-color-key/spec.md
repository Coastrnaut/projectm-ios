# Feature Specification: CMP-010 Color Key

**Feature Branch**: `feature/cmp-010` (spec directory `230-cmp-010-color-key`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement CMP-010 (Color key) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Remove selected color with tolerance and feather controls."
Acceptance, verbatim: "Green patch keys out and unrelated colors remain opaque." P2; depends on
CMP-001 (unified layer protocol, integrated). Follow CMP-009 Luma key's design."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `CMP-010-R1…`, success criteria `CMP-010-S1…`, tasks `CMP-010-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `96ee68c7`)

The row's gap status is "Gap candidate". The audit confirms a full gap: a layer can be cut by a shape
(CMP-007), faded by a gradient (CMP-008) or keyed by its brightness (CMP-009); nothing makes a layer
transparent by its hue.

| Area | Today | Gap for this row |
|---|---|---|
| Layer composite settings (CMP-001, `LayerCompositeSettings`) | opacity, blend, transform, fit, shape `mask`, `gradientMask`, `lumaKey`. | No colour key. |
| Compositor mask path (CMP-007 to CMP-009) | One per-layer mask block (shape × gradient × luma keep) in every draw path, no extra pass for normal layers. | Nothing reads the layer's hue. |
| CPU references | Shape and gradient geometry, `LayerBlend` (sRGB encode/decode), `LayerLumaKey`. | No colour key reference. |
| Scene format (SCN-001) | `composite.mask`, `composite.gradientMask`, `composite.lumaKey`, optional. Version 1. | No place for a colour key. |
| Layer inspector (CMP-015, CMP-009) | Mask, Gradient and Luma Key sections with help, undo and ACC-005 sliders. | No colour key editor and no colour picker. |
| Goldens (QA-002) | `LumaKey` goldens on the Mac host and the iOS simulator. | No colour key golden. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Key out a colour (Priority: P1) 🎯 MVP

A scene author turns on a colour key for a layer and picks the colour to remove (green by default).
The parts of the layer close to that colour become transparent; every other colour stays exactly as
it was. Tolerance sets how far from the key colour a pixel may be and still be removed; feather
widens the edge so the layer fades out gradually instead of cutting off. The classic use is a green
screen: a green patch in a visual disappears so the layers beneath show through, while red, blue,
white, skin tones and dark greens outside the tolerance stay opaque and unchanged.

**Why this priority**: It is the row's observable behavior and its acceptance criterion.

**Independent Test**: Composite a layer containing a green patch and unrelated colours over a known
background with a green key, read the pixels back, and check that the green patch contributes
nothing and the other colours are unchanged.

**Acceptance Scenarios**:

1. **Given** a layer with a green patch and patches of red, blue, white, a skin tone and a dark green
   outside the tolerance, and a green key, **When** composited, **Then** the green patch's alpha is 0
   (within 1/255) and every other patch's colour and alpha equal the unkeyed layer's (within 1/255).
2. **Given** a feather above 0, **When** a ramp of colours moving away from the key colour is
   composited, **Then** alpha never falls as the colour moves away from the key, is 0 within the
   tolerance and 1 beyond tolerance + feather.
3. **Given** a key together with a shape mask, a gradient and a luma key, **When** composited,
   **Then** the layer's alpha is the product of the four.

---

### User Story 2 - Edit the key in the inspector (Priority: P1)

In the layer inspector, the author turns the key on, picks the key colour with a colour picker and
sets Tolerance and Feather with sliders. Every control has help and an accessible name, the sliders
are adjustable with VoiceOver, and each drag or colour choice is one undo step.

**Why this priority**: The row says the colour is selected; without an editor it cannot be.

**Independent Test**: UI test: turn the key on, find the colour picker by its accessible name, drag a
slider, undo; unit tests of the edit rules.

**Acceptance Scenarios**:

1. **Given** a layer without a key, **When** the author turns the key on, **Then** a green key with
   default tolerance and feather appears.
2. **Given** a colour chosen in the picker, **Then** the key uses that colour's opaque value (any
   opacity in the choice is ignored).
3. **Given** an edit, **When** the author undoes, **Then** the previous key returns.

---

### User Story 3 - Scenes keep the key (Priority: P1)

A scene stores each layer's colour key. Opening and saving keeps it exactly.

**Why this priority**: Without persistence, the edit is lost on relaunch.

**Independent Test**: Decode → encode, and decode → load → capture → encode of scenes with a key.

**Acceptance Scenarios**:

1. **Given** a scene with a colour key, **When** decoded and encoded, **Then** the bytes are identical.
2. **Given** the same scene, **When** loaded and captured, **Then** the key is unchanged.
3. **Given** out-of-range values or unknown keys, **When** decoded, **Then** values are clamped with
   `valueClamped` and unknown keys dropped with `droppedField`.
4. **Given** a scene written before this feature, **When** decoded and encoded, **Then** the bytes and
   the format version are unchanged.

### Edge Cases

- Fully transparent pixels read as black (no hue); they stay transparent whatever the key.
- Over-bright (above 1) colour: measured on the colour clamped to 0…1.
- Greys (white, black, any neutral) are equally far from every saturated key colour; a key colour
  that is itself grey keys neutral pixels.
- Tolerance 0 and feather 0: only colours with exactly the key's hue and saturation are keyed.
- A transformed layer (CMP-005): the key reads the layer's resampled colour at the shown pixel.
- Every blend mode and any opacity: the key applies before blending, as the masks do; opacity never
  changes which pixels are keyed.
- A key that keys nothing in the picture: the layer is drawn as without a key (within 1/255).
- Spill (green fringes on kept pixels): not changed by this feature (see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

- **CMP-010-R1**: The layer contract MUST offer an optional colour key per layer, independent of the
  masks and the luma key, with a key colour, a tolerance and a feather.
- **CMP-010-R2**: The key's keep factor at colour distance d from the key colour MUST be 0 for
  d ≤ tolerance, 1 for d ≥ tolerance + feather, and rise linearly in between (monotonic in d).
- **CMP-010-R3**: The colour distance MUST be measured on the layer's own straight (unpremultiplied)
  colour, clamped to 0…1, as displayed, in a space where brightness differences of the same hue count
  less than hue differences (see Clarifications), independent of the layer's opacity.
- **CMP-010-R4**: The keep factor MUST multiply the layer's colour and alpha (premultiplied), so a kept
  pixel's colour and alpha are unchanged.
- **CMP-010-R5**: A plain reference calculation (no GPU, every platform) MUST give the keep factor of
  any colour, matching the GPU within 1/255.
- **CMP-010-R6**: The key MUST combine with shape mask, gradient and luma key by multiplication and
  work with every blend mode, opacity and transform.
- **CMP-010-R7**: The key MUST NOT add a render pass or pipeline for normal-mode layers, and layers
  without a key MUST be drawn exactly as before.
- **CMP-010-R8**: The scene format MUST store the key as an optional value written only when set,
  with the format version unchanged; scenes without it MUST encode byte-identically and a key MUST
  round-trip byte for byte.
- **CMP-010-R9**: Out-of-range values MUST be clamped on decode with `valueClamped`, and unknown keys
  dropped with `droppedField`.
- **CMP-010-R10**: The layer inspector MUST turn the key on and off and edit the key colour (a colour
  picker with an accessible name), tolerance and feather, with help, VoiceOver-adjustable sliders and
  one undo step per drag or choice.
- **CMP-010-R11**: A key change applied to the stack MUST show from the next frame without
  re-creating the layer or its pictures.

### Key Entities

- **Colour key**: key colour (displayed red, green, blue, each 0…1), tolerance, feather; absent means
  no key. Default when turned on: pure green.
- **Keep factor**: 0…1 per pixel from the pixel's distance to the key colour, multiplying the layer's
  colour and alpha (with the other masks' factors when set).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **CMP-010-S1**: In a GPU read-back of the green-key fixture, 100 % of green-patch pixels have alpha
  ≤ 1/255 and 100 % of the red, blue, white, skin-tone and dark-green pixels match the unkeyed colour
  and alpha within 1/255.
- **CMP-010-S2**: Over a colour ramp with feather, 0 samples move against the expected direction by
  more than 1/255, and every sample matches the reference within 1/255.
- **CMP-010-S3**: One green-key golden matches on the Mac host and the iOS simulator under QA-002's
  rule.
- **CMP-010-S4**: 100 % of key scene round trips are byte-identical; scenes without keys and existing
  goldens are unchanged; QA-004's meta-test passes with no new version.
- **CMP-010-S5**: The GPU time of a full-screen keyed layer is measured on the Mac and recorded as
  "not device evidence"; the device measurement on D1 is a `{device}` task.
- **CMP-010-S6**: In the UI test, turning the key on, finding the colour picker, one slider drag and
  one undo complete in under 30 s.

## Assumptions

- The key is a separate optional field (`composite.colorKey`) beside the masks and the luma key, so it
  combines with all of them.
- Older app versions drop the new field with `droppedField` (format version 1 tolerates unknown keys)
  and draw the layer unkeyed, as for any newer optional value.
- Spill suppression (removing the key colour's tint from kept pixels) is out of scope: it would change
  the colour of kept pixels, which the acceptance requires to stay unchanged; it can be a later row.
- Picking the key colour from the picture (an eyedropper) is out of scope; the system colour picker is
  used.
