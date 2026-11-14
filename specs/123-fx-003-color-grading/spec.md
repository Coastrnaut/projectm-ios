# Feature Specification: FX-003 Color Grading

**Feature Branch**: `feature/fx-003` (spec directory `123-fx-003-color-grading`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FX-003 (Color grading) from docs/FEATURE_ROADMAP_AUTONOMOUS.md.
Observable behavior, verbatim: "Adjust lift, gamma, gain, saturation and temperature." Acceptance, verbatim:
"Neutral defaults are pixel-equivalent to bypass within tolerance." P1, effort M, depends on VIS-001
(integrated). Verification: snapshot tests, shader unit tests, and the device GPU in the last stage."

Identifiers in this feature carry the roadmap ID: requirements `FX-003-R1…`, success criteria
`FX-003-S1…`, tasks `FX-003-T01…`, research decisions `FX-003-D1…`. Other features are cited by their own
IDs: CMP-001 (the compositor and its output pass; ADR-0013), CMP-004 (blend modes; ADR-0037), CMP-013
(render caching; ADR-0040), CMP-014 (scene transition bus; ADR-0042), CMP-015 (layer inspector; ADR-0044),
FX-001 (bloom), FX-002 (tone mapping; ADR-0047), FX-019 (strobe safety envelope, the composite flash guard),
MOD-001 (parameter registry; ADR-0012), MOD-002 (audio-feature bindings), ACC-005 (accessible parameter
sliders), ACC-012 (sensory safety profile, in parallel), FILE-005 (library backup settings policy), REC-001
(frame capture), REC-003 (video recording), VIS-001 (circular spectrum), RenderGoldens (QA-002 golden images).

## Baseline: the audit (2026-11-14, commit `1a4da42b`)

**No grading exists.** No lift, gamma, gain, saturation or temperature control exists anywhere in the app or
its packages (a search over `Packages/*/Sources` and `Apps/projectM-iOS` finds only SHD-002's HSV graph node
and SHD-001's per-material "Saturation" parameter, both inside one layer's generator, not a picture grade). The only colour controls are the native spectra's palette (VIS-001, ACC-003's colour-blind-safe
ramp), FX-001's glow and ACC-008's overlay contrast; none changes the picture's tone or colour balance.

**Where the picture is finished.** Four visuals are compositor-backed (CMP-001): Camera, Photo, Video and Text
(each a circular spectrum over a camera feed, photo, video or text). Their frames go through one output pass
(`cmp_output`), which since FX-002 does: composite pixel → tone map (sanitise, identity in range, luminance-
keeping desaturation above white) → × the flash guard's gain → the target's encoding. Every output of those
visuals uses that pass: the screen and external display, REC-003 recording, REC-001 capture and CMP-014's
transition bus. FX-019's composite flash guard measures 4,096 samples through the same tone-map function, so
the limiter judges the colour shown.

**Not compositor-backed.** The standalone native spectra (circular, linear, oscilloscope; `NativeSpectrumHost`,
with FX-001's bloom) and projectM (ANGLE) draw straight into 8-bit drawables and never reach the output pass
(FX-002's audit recorded the same).

**Caching.** CMP-013 reuses unchanged layer pictures and an unchanged composite; the flash guard and output
pass run every frame. A step after the composite therefore never invalidates cached layers.

**Parameters.** The MOD-001 registry (`VisualParameterCatalog` plus `ProceduralMaterialCatalog`) is what scenes,
scene archives, bindings and goldens validate parameter IDs against. Live MOD-002 bindings are wired only to the
native spectra's glow intensity; no compositor-backed visual has a modulator.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction);
each answer is the conservative option.

- Q: Which visuals are graded? → A: The compositor-backed visuals (Camera, Photo, Video, Text) on every output
  they write (screen, external display, recording, capture, transition bus), through the existing output pass.
  The standalone native spectra and projectM are not graded in this feature (no output pass to extend; a shared
  native step is a follow-up), and the Settings help says so. Applied to FX-003-R1, R11 and the Assumptions.
- Q: One global grade or per layer / per scene? → A: One global grade, a visual setting saved on the device
  (like the glow and Reduce flashing), applied to the finished composite. Per-layer grading (CMP-015's
  inspector) and a per-scene field are later options. Applied to FX-003-R8.
- Q: Where in the chain does grading run? → A: In linear light on the finished composite, before FX-002's tone
  map, so graded colours above display white are tone-mapped safely, and before the flash guard measures, so
  the limiter judges the graded, tone-mapped colour. Applied to FX-003-R2, R6.

### Session 2026-11-14 (speckit-clarify)

Four questions, each answered by Claude with the recommended option (owner rule 4).

- Q: What ranges do the controls have? → A: Temperature −1…+1 (cool to warm, neutral 0), lift −0.1…+0.1
  (linear-light offset of black, neutral 0), gamma 0.5…2 (neutral 1; above 1 brightens mid-tones), gain
  0.5…2 (neutral 1), saturation 0…2 (neutral 1). Lift and gain stay well inside the ranges where luminance
  ordering holds (gain > 0, lift < 1). Applied to FX-003-R4, R7 and Key Entities.
- Q: Are lift, gamma and gain master controls or per colour channel (colour wheels)? → A: Master controls,
  one value each for all three channels; per-channel wheels are a later option. Applied to FX-003-R1.
- Q: Is temperature in Kelvin? → A: No: a unitless cool-to-warm scale (red and blue gains moved in opposite
  directions, normalised so a grey keeps its luminance). The UI says "Cool" or "Warm" with the amount, never
  a Kelvin value it cannot back up. Applied to FX-003-R5, R9.
- Q: What tolerances do the GPU comparisons use? → A: FX-002's: one 8-bit step (1/255 of the encoded value)
  for the sRGB screen format and 0.002 absolute for the half-float format; bit-identity is checked separately
  for in-range pixels at neutral. Applied to FX-003-S1, S2.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Grade the look of a composited visual (Priority: P1)

A performer shows the Photo visual and wants a warmer, punchier look: they open Settings → Color, warm the
temperature, lower the gamma slightly, raise the saturation, and see the visual change at once. The look stays
the next time they open the app.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: set each control in Settings and check the rendered output changes as the reference
mathematics predicts; relaunch and check the values are kept.

**Acceptance Scenarios**:

1. **Given** the Photo visual, **When** the user raises the gain, **Then** the picture gets brighter; lowering
   the saturation to 0 makes it grey with the same brightness.
2. **Given** a warm temperature, **When** the visual shows a neutral grey, **Then** the grey turns warmer (more
   red, less blue) and keeps its brightness.
3. **Given** grading values set, **When** the app is relaunched, **Then** the same values are shown and applied.

---

### User Story 2 - Neutral is exactly "off" (Priority: P1)

A performer who never touches grading, or who taps "Reset to neutral", sees exactly what they saw before this
feature existed.

**Why this priority**: it is the roadmap row's acceptance; grading must cost nothing for people who do not
use it.

**Independent Test**: render a reference image with gradients, primaries and greys through the output pass with
neutral grading and with grading bypassed, and compare.

**Acceptance Scenarios**:

1. **Given** neutral grading, **When** a frame is shown, recorded or captured, **Then** every in-range pixel is
   bit-identical to the output without grading, and every pixel is within tolerance.
2. **Given** a graded look, **When** the user taps "Reset to neutral", **Then** every control returns to its
   neutral value and the output is again identical to bypass.

---

### User Story 3 - Grading can never defeat the flash limiter (Priority: P1)

A performer raises the gain on a flickering video. The strobe limiter (FX-019) judges the picture as shown after
grading, so it still limits a flash the grading makes visible, and grading cannot hide a flash from it.

**Why this priority**: sensory safety must be measured on the picture as shown.

**Independent Test**: alternate dark and mid-grey frames that are under the limiter's threshold without grading;
with a high gain they become a visible flash, and the limiter lowers its gain.

**Acceptance Scenarios**:

1. **Given** frames alternating below the flash threshold, **When** a high gain makes the change large, **Then**
   the limiter engages exactly as it would for an ungraded flash of the same shown size.

### Edge Cases

- Graded colour above display white (gain 2 on white): tone-mapped by FX-002 (hue kept, never clipped or NaN).
- Lift below 0 on dark pixels: never negative (clamped at black); lift above 0 raises black evenly.
- Saturation above 1 pushing a channel below 0: that channel stops at 0.
- NaN or infinite composite channels: treated as 0 before grading, as FX-002 does.
- Stored values that are missing, not numbers, NaN or out of range: the neutral value or the nearest limit.
- Transparent composite pixels: graded as the colour shown (the composite over black); alpha unchanged.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged; the section's help says which
  visuals are graded.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-003-R1**: Five master grading controls (one value for all channels) — temperature, lift, gamma, gain
  and saturation — apply to the
  compositor-backed visuals on every output they write (screen, external display, recording, capture, the
  transition bus).
- **FX-003-R2**: The operators run in linear light on the finished composite, in a fixed, documented order
  (temperature, then lift, gamma and gain, then saturation), before the tone map.
- **FX-003-R3**: At neutral values (temperature 0, lift 0, gamma 1, gain 1, saturation 1) grading is bypassed:
  every output pixel equals the ungraded output (bit-identical; the acceptance tolerance is a second check).
  Each control at its neutral value is an exact identity for that operator while others are active.
- **FX-003-R4**: Lift, gamma and gain never make a brighter input darker: output luminance is non-decreasing in
  input luminance for every value within their ranges.
- **FX-003-R5**: Saturation 0 gives a grey of the same luminance; temperature keeps the luminance of greys.
- **FX-003-R6**: The flash limiter measures the graded and tone-mapped colour, and its gain multiplies that
  colour.
- **FX-003-R7**: The five controls are registered parameters (MOD-001) with stable IDs, ranges, defaults and
  step hints, so scenes, bindings and safety clamps can see them.
- **FX-003-R8**: The values are one global visual setting saved on the device, restored at launch, included in
  library backups, and checked on read (missing, NaN or non-number → neutral; out of range → clamped).
- **FX-003-R9**: Settings has a "Color" section with one slider per control (VoiceOver-adjustable in the
  control's step, with a spoken value; temperature reads "Cool" or "Warm" with its amount, never Kelvin),
  short help text naming the graded visuals, and a "Reset to neutral" button.
- **FX-003-R10**: A plain-software reference of the grading exists, testable without a GPU (Linux), and the GPU
  output matches it within half-float and 8-bit tolerance.
- **FX-003-R11**: No new render pass, texture or per-frame allocation; cached layers stay reusable (grading is
  after the composite); every existing golden image is unchanged.

### Key Entities

- **Color grade**: the five values, each with a range and neutral: temperature −1…+1 (0), lift −0.1…+0.1 (0),
  gamma 0.5…2 (1), gain 0.5…2 (1), saturation 0…2 (1). Master values (the same for all three channels).
- **Reference image**: horizontal grey and colour ramps, the primaries and secondaries, and fixed greys.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-003-S1**: With neutral grading, the reference image through the real output pass is bit-identical to the
  ungraded output for every in-range pixel, and within one 8-bit step (screen) or 0.002 (half float) overall.
- **FX-003-S2**: Each operator at a few representative settings matches the software reference within one 8-bit
  step (screen) and 0.002 (half float).
- **FX-003-S3**: Over at least 10,000 sampled settings and inputs, the software reference keeps luminance
  ordering under lift, gamma and gain, gives luminance-keeping grey at saturation 0 and identity at neutral
  temperature, in under 2 seconds.
- **FX-003-S4**: Frames alternating under the flash threshold that grading turns into a visible flash make the
  limiter lower its gain; the same frames ungraded keep it at 1.
- **FX-003-S5**: All existing RenderGoldens pass unchanged (zero re-recorded goldens).
- **FX-003-S6**: A user can find the Color section, change a control and reset to neutral (UI test); values
  survive a relaunch.
- **FX-003-S7**: The output pass's GPU time with neutral and with active grading is measured on the Mac and
  recorded (no pass/fail threshold); the device frame rate is checked in the last stage (`{device}`).

## Assumptions

- Display range and tone mapping are FX-002's (SDR, 0…1 in linear light).
- The grade is applied to the composite as shown, i.e. the premultiplied colour over black; alpha passes
  through unchanged.
- Live audio-reactive modulation of grading is not wired in this feature (no compositor-backed visual has a
  modulator yet); the registry entries make it possible later.
- The standalone native spectra and projectM are not graded (see Clarifications).
