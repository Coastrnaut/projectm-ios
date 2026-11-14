# Feature Specification: FX-002 Tone Mapping

**Feature Branch**: `feature/fx-002` (spec directory `122-fx-002-tone-mapping`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FX-002 (Tone mapping) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Convert HDR-like intermediate values into display range safely."
Acceptance, verbatim: "Reference gradient preserves ordering and never clips to NaN." P1, effort M,
depends on VIS-001 (integrated). Verification: snapshot tests, shader unit tests, and the device GPU in
the last stage."

Identifiers in this feature carry the roadmap ID: requirements `FX-002-R1…`, success criteria
`FX-002-S1…`, tasks `FX-002-T01…`, research decisions `FX-002-D1…`. Other features are cited by their own
IDs: CMP-001 (the compositor and its output pass; ADR-0013), CMP-003 (per-layer sanitising), CMP-004
(blend modes; ADR-0037), CMP-014 (scene transition bus; ADR-0042), FX-001 (bloom; ADR-0010), FX-019
(strobe safety envelope, the composite flash guard), REC-001 (frame capture), REC-003 (video recording),
OUT-001 (external display), VIS-001 (circular spectrum), RenderGoldens (QA-002 golden images).

## Baseline: the audit (2026-11-14, commit `89d78f88`)

**Where values come from.** The compositor (CMP-001) accumulates every layer into a linear, premultiplied
`rgba16Float` composite. Each layer draw sanitises its picture first (non-finite channels read 0, colour
≥ 0, alpha 0…1; CMP-001-R10, CMP-003), but nothing bounds colour from above: a layer may write values
above 1 (glow, materials, generator graphs, an emissive picture with colour above its alpha), "over"
accumulates them, and half floats overflow to +Inf above 65504. Blend modes (CMP-004) clamp their own
function to 0…1 (ADR-0037) but pass the backdrop's colour through. An infinite composite channel times a
later opaque layer's (1 − α) = 0 in the fixed-function blend gives NaN. So the composite can hold values
above 1, +Inf and (rarely) NaN, although no single layer can inject NaN or negatives.

**Today's output pass** (`cmp_output`, used for the screen and external display, REC-003 recording, REC-001
capture and CMP-014's bus): composite.rgb × the flash guard's gain, alpha untouched, no clamp. The
target's format does the rest. Measured on the Mac (Apple GPU) by running the real shader on a
hand-filled composite (`OutputPassRig`, 2026-11-14):

| Composite pixel (linear RGBA) | `bgra8Unorm_srgb` (screen) | `rgba16Float` (capture) |
|---|---|---|
| (NaN, 0.5, 0.5, 1) | (0, 0.737, 0.737, 1): NaN → 0, a hardware-defined result | (NaN, 0.5, 0.5, 1) |
| (+Inf, 0.5, 0.5, 1) | (1, 0.737, 0.737, 1) | (+Inf, 0.5, 0.5, 1) |
| (−Inf or −0.5, 0.5, 0.5, 1) | (0, 0.737, 0.737, 1) | passed through (negative) |
| (2, 0.5, 0.25, 1) | (1, 0.737, 0.537, 1): each channel clipped, the hue shifts from orange toward yellow | (2, 0.5, 0.25, 1) |
| (16, 16, 16, 1) | white | (16, 16, 16, 1) |
| (0.5, 0.5, 0.5, NaN) | alpha 0 | alpha NaN |
| (0.5, 0.5, 0.5, 2) | alpha 1 | alpha 2 |
| (0.9, 0.9, 0.9, 1) | 0.953 (= sRGB of 0.9) | 0.8999 |

**The flash guard** (FX-019 on the composite, `CompositeFlashGuard`) measures luminance on the raw composite
(colour ≥ 0, no upper bound) before the output pass, so a frame at 16 counts as sixteen times brighter
than white although the screen shows white: it measures something the user does not see.

Findings: (1) over-range colour is clipped per channel by the 8-bit target, which shifts hues and is
format-dependent; (2) NaN reaches the 8-bit screen as a hardware-defined value and reaches captures as
NaN; (3) `rgba16Float` outputs (frame capture) carry over-range, infinite and NaN values unchanged; (4)
the flash guard measures pre-display values; (5) no test drives out-of-range values through the output
pass.

Out of scope, recorded for follow-up: the standalone native spectrum host (`NativeSpectrumHost`, VIS-001
with FX-001's bloom) and the projectM (ANGLE) path draw straight into 8-bit drawables and do not use the
compositor's output pass; their values are clipped by the hardware as before.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative option.

- Q: Where does the tone map run? → A: Once, inside the compositor's existing output pass, which feeds the
  screen, the external display, recording and frame capture, and CMP-014's bus (the same shader). No new
  pass. Applied to FX-002-R1, R9.
- Q: Which curve? → A: Identity for every pixel whose largest colour channel is at most 1 (display white),
  so every frame that is in range today is unchanged bit for bit and no golden changes. Above that, the
  colour keeps its luminance and hue and loses saturation toward white just enough for its largest channel
  to fit; a pixel whose luminance is 1 or more becomes white. A knee below 1 (for example 0.8 with a soft
  shoulder) was rejected: it would darken every in-range highlight (pure white to about 0.93 with a C¹
  shoulder) and change every golden. Applied to FX-002-R3, R4.
- Q: What do NaN, ±Infinity and negative values become? → A: 0 per channel, matching the layer passes'
  sanitising (CMP-001-R10); alpha is also clamped to 0…1. Applied to FX-002-R2.

### Session 2026-11-14 (speckit-clarify)

Four questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Does the ordering guarantee include +Infinity, which maps to 0 and so below the largest finite
  values? → A: No. +Infinity is invalid data (a half-float overflow), treated like a layer's infinite channel
  (0, counted by FX-002-R7); the ordering guarantee covers every finite value, however large. Applied to
  FX-002-R5 and the edge cases.
- Q: Which output passes count non-finite pixels, and how is the count exposed? → A: Only the pass that
  writes the screen (the compositor's `composite` and the bus's frame), so a recorded or captured frame is
  not counted twice; a cumulative count since the compositor (or bus) was created, readable for diagnostics
  and tests, never logged per frame. Applied to FX-002-R7.
- Q: What tolerance does the GPU-versus-reference comparison use? → A: One 8-bit step (1/255 of the encoded
  value) for the sRGB screen format and 0.002 absolute for the half-float capture format (half precision
  near 1 is about 0.0005, plus float-versus-double rounding). Applied to FX-002-S1.
- Q: Is there a GPU-time budget on the Mac? → A: No pass/fail budget (simulator and Mac timings are never
  device evidence); the output pass's GPU time with and without the tone map is measured on the Mac and
  recorded, and the device frame rate is checked in the last stage (FX-002-S6). Applied to FX-002-R9, S7.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bright layers look right, never broken (Priority: P1)

A performer stacks a glowing spectrum, a bright material and a photo; some regions add up beyond display
white. Those regions show as bright, correctly hued colours that fade toward white, never as hue-shifted
clipping, black holes or garbage pixels, on the device screen and on an external display.

**Why this priority**: it is the roadmap row's subject and protects every composited scene.

**Independent Test**: render a reference gradient from 0 to 16 (grey and coloured), plus NaN, ±Infinity and
negatives, through the real output pass and check ordering, range and the absence of NaN.

**Acceptance Scenarios**:

1. **Given** a gradient from 0 to 16 in linear light, **When** it is shown, **Then** every output channel is
   non-decreasing along the gradient, within 0…1, and never NaN.
2. **Given** a pixel holding NaN, +Infinity, −Infinity or a negative value, **When** it is shown, **Then** that
   channel shows 0 and the rest of the pixel is unaffected.
3. **Given** a frame whose values are all within display range, **When** it is shown, **Then** it is
   identical to today's output.

---

### User Story 2 - Recordings and captures match the screen (Priority: P1)

The performer records a video and saves a still while bright regions are on screen. Both show the same
colours as the screen, never over-range or NaN values.

**Why this priority**: recordings and captures are shared; differences would be visible defects.

**Independent Test**: one frame with the reference gradient shown, recorded and captured; the three
outputs agree within 8-bit quantisation.

**Acceptance Scenarios**:

1. **Given** an over-range frame, **When** it is shown, recorded and captured, **Then** the recording and the
   capture equal the screen within one 8-bit step.

---

### User Story 3 - The flash limiter judges what the viewer sees (Priority: P1)

A frame flickers between display white and an even brighter over-range value. The screen shows steady white,
so the strobe limiter (FX-019) must not dim it; a real flicker between black and over-range white is still
limited.

**Why this priority**: sensory safety must be measured on the picture as shown.

**Independent Test**: alternate 1.0 and 16.0 frames (no visible change: gain stays 1) and 0 and 16.0 frames (a
visible flash: the limiter engages).

**Acceptance Scenarios**:

1. **Given** frames alternating between 1 and 16, **When** they are shown with the limiter on, **Then** the
   limiter's gain stays 1.
2. **Given** frames alternating between 0 and 16, **When** they are shown, **Then** the limiter lowers the gain
   as it does for 0 and 1.

### Edge Cases

- Grey above 1: white. A saturated colour above 1 whose luminance is below 1 (for example (4, 0.1, 0.1)):
  same hue and luminance, less saturated.
- Alpha NaN or above 1: 0 or 1. Colour above alpha (emissive): kept on screen as today.
- Half-float overflow (+Inf in the composite): that channel shows 0, as a layer's infinite channel already does.
- The flash guard's gain is applied after the tone map, so the shown value is gain × mapped colour.
- Scenes without over-range values (every current golden): unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-002-R1**: One tone-map stage runs in the compositor's output pass for every output it writes: the
  screen and external display, recording, frame capture and the scene transition bus.
- **FX-002-R2**: Non-finite and negative colour channels map to 0; alpha maps non-finite to 0 and is
  clamped to 0…1.
- **FX-002-R3**: A pixel whose largest colour channel is at most 1 (after R2) is output unchanged.
- **FX-002-R4**: A pixel with a channel above 1 keeps its luminance (Rec. 709 / WCAG weights) and hue and is
  desaturated toward white just enough to fit; at luminance 1 or more it becomes white.
- **FX-002-R5**: The mapping is monotonic over finite inputs: along any ray of colours (one hue scaled from
  0 upward) no output channel decreases, and output luminance never decreases when any input channel
  increases. Every output is within 0…1 and never NaN.
- **FX-002-R6**: The flash limiter (FX-019's composite flash guard) measures the tone-mapped colour, and its
  gain multiplies the tone-mapped colour.
- **FX-002-R7**: The number of non-finite composite pixels the screen output pass met is counted for
  diagnostics (cumulative, screen pass only; recording and capture passes do not count).
- **FX-002-R8**: A plain-software reference of the mapping exists, testable without a GPU (Linux), and the
  GPU output matches it within half-float and 8-bit tolerance.
- **FX-002-R9**: No new render pass, texture or per-frame allocation; the cost is a few arithmetic steps in
  the existing output shader.
- **FX-002-R10**: Every existing golden image is unchanged.

### Key Entities

- **Tone map**: the per-pixel mapping from a composite pixel to a display pixel (R2-R5).
- **Reference gradient**: grey and coloured ramps from 0 to 16 in linear light plus special values.
- **Non-finite counter**: the cumulative number of non-finite composite pixels met by the screen pass.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-002-S1**: The reference gradient through the real output pass is non-decreasing per channel, has no
  NaN and lies within 0…1, in both the 8-bit screen format and the half-float capture format, and matches the
  software reference within one 8-bit step (screen) or 0.002 (half float).
- **FX-002-S2**: All existing RenderGoldens pass unchanged (zero re-recorded goldens).
- **FX-002-S3**: Alternating 1 and 16 keeps the limiter's gain at 1; alternating 0 and 16 lowers it.
- **FX-002-S4**: The recording and capture of an over-range frame equal the screen within one 8-bit step.
- **FX-002-S5**: The software reference's monotonicity and range properties hold over at least 10,000
  sampled colours, in under 2 seconds.
- **FX-002-S6**: On D1, a scene with over-range glow shows no hue-shifted clipping or broken pixels and the
  frame rate is unchanged (`{device}`, last stage).
- **FX-002-S7**: The output pass's GPU time with and without the tone map is measured on the Mac and
  recorded (no pass/fail threshold).

## Assumptions

- Display range is 0…1 in linear light (SDR drawables, 8-bit sRGB); extended-range (EDR) output is not
  part of this feature.
- No user setting: in-range pixels are untouched, so there is nothing a user would turn off, and the
  previous behaviour (format-dependent clipping, NaN pass-through) is not a choice worth keeping. No new
  UserDefaults key.
- The standalone native spectrum host and projectM's ANGLE path are out of scope (see the audit).
