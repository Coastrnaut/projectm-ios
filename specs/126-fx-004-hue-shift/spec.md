# Feature Specification: FX-004 Hue Shift

**Feature Branch**: `feature/fx-004` (spec directory `126-fx-004-hue-shift`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "Implement FX-004 (Hue shift) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Rotate hue without changing grayscale content." Acceptance, verbatim: "Gray ramp stays
neutral and red test patch rotates predictably." P1, effort S, depends on VIS-001 (integrated). Verification:
snapshot tests, shader unit tests, and the device GPU in the last stage. Builds on FX-003 colour grading
(ADR-0050)."

Identifiers in this feature carry the roadmap ID: requirements `FX-004-R1…`, success criteria `FX-004-S1…`,
tasks `FX-004-T01…`, research decisions `FX-004-D1…`. Other features are cited by their own IDs: FX-003 (colour
grading; ADR-0050, `specs/123-fx-003-color-grading`), FX-002 (tone mapping; ADR-0047), FX-019 (the composite
flash guard), CMP-001 (the compositor's output pass; ADR-0013), CMP-014 (scene transition bus), MOD-001
(parameter registry; ADR-0012), ACC-005 (accessible parameter sliders), ACC-012 (sensory safety profile;
ADR-0049), FILE-005 (library backup settings policy), FILE-011 (local data erase; ADR-0048), RenderGoldens
(QA-002 golden images).

## Baseline: the audit (2026-11-14, commit `784a1c76`)

**No picture hue rotation exists.** "Hue" appears only inside single generators or palettes: SHD-002's HSV graph
node (`GraphNodeKind`), the native spectra's palette hues (`VisualPalette`) and ACC-003's colour-blind-safe
ramp. None rotates the hue of the finished picture.

**FX-003 grades the finished composite.** The compositor-backed visuals (Camera, Photo, Video, Text) send every
output (screen, external display, REC-003 recording, REC-001 capture, CMP-014's bus) through one output pass:
composite → FX-003's grade (temperature, lift, gamma, gain, saturation, in linear light; every control neutral =
the pixel untouched) → FX-002's tone map → × the flash guard's gain. FX-019's guard measures through the same
graded, tone-mapped function. The grade is one global setting (five UserDefaults keys `settings.colorGrade.*`),
shown in Settings → Color, and registered as MOD-001 parameters `effect.colorGrade.*`. The native spectra and
projectM are not graded.

## Clarifications

### Session 2026-11-14 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction);
each answer is the conservative option.

- Q: A new effect, or part of FX-003's grade? → A: A sixth control of FX-003's colour grade ("Hue" in
  Settings → Color), on the same visuals and outputs, saved and reset with the other five. No second pass or
  setting group. Applied to FX-004-R1, R7, R8.
- Q: What does "without changing grayscale content" mean? → A: Two things: a grey (equal red, green and blue)
  stays exactly that grey, and every colour keeps its luminance (its grayscale value), so a black-and-white
  copy of the picture is unchanged by the hue control within tolerance. Applied to FX-004-R2, R3.
- Q: Which visuals? → A: FX-003's: the compositor-backed visuals on every output; the native spectra and
  projectM are not shifted. Applied to FX-004-R1 and the Assumptions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shift the colours of a visual (Priority: P1)

A performer shows the Camera visual and wants the stage's reds to read as purples: they open Settings → Color,
move "Hue" and see every colour turn around the colour wheel at once, while white, black and greys stay as they
were and the picture keeps its brightness. The setting is kept at the next launch.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: render a grey ramp and a red patch through the output pass at several hue angles and
compare with the reference; relaunch and check the value is kept.

**Acceptance Scenarios**:

1. **Given** any hue angle, **When** the visual shows greys from black to white (and brighter than white),
   **Then** every grey stays neutral and keeps its value.
2. **Given** a hue of +120 degrees, **When** the visual shows pure red, **Then** the result has the hue of
   green with red's luminance; at +240 (equal to −120) degrees it has the hue of blue with red's luminance.
3. **Given** a hue set, **When** the app is relaunched, **Then** the same hue is shown and applied.

---

### User Story 2 - Zero is exactly "off" (Priority: P1)

A performer who never touches the hue, or taps "Reset to neutral", sees exactly what FX-003 showed.

**Why this priority**: the grade must cost nothing for people who do not use it.

**Independent Test**: render FX-003's reference image with hue 0 and compare with the output before this
feature.

**Acceptance Scenarios**:

1. **Given** hue 0 and the other controls neutral, **When** a frame is shown, **Then** every pixel is
   bit-identical to the ungraded output.
2. **Given** hue 0 and other controls active, **When** a frame is shown, **Then** it equals FX-003's grade of
   those controls bit for bit.

---

### User Story 3 - A hue shift cannot defeat the flash limiter (Priority: P1)

The strobe limiter (FX-019) judges the picture after the hue shift, so changing the hue can neither hide a flash
nor stop the limiter from acting on the colours actually shown.

**Independent Test**: alternate frames that flash above the threshold; with a hue shift the limiter still
engages.

**Acceptance Scenarios**:

1. **Given** frames alternating above the flash threshold, **When** a hue shift is active, **Then** the limiter
   lowers its gain as it does without the shift.

### Edge Cases

- Hue +180 and −180 degrees give the same picture.
- A saturated colour rotated toward a darker primary (red toward blue) cannot reach that primary at red's
  luminance: it becomes a lighter tint of the target hue (still the target hue, same luminance); a rotation
  toward a brighter primary that would need a negative channel is pulled toward grey just enough to stay
  displayable, keeping hue and luminance.
- Colours brighter than display white after the shift: tone-mapped by FX-002 (hue and luminance kept).
- NaN or infinite composite channels: treated as 0, as FX-003 does.
- Stored values missing, not numbers, NaN or out of range: 0 or the nearest limit.
- Visuals that are not compositor-backed: unchanged (the section's help already says which are graded).

## Requirements *(mandatory)*

### Functional Requirements

- **FX-004-R1**: A hue control (degrees, −180…+180, neutral 0) is a sixth master control of FX-003's colour grade
  and applies to the same visuals and outputs.
- **FX-004-R2**: Greys are fixed points: for every angle, an input with equal red, green and blue (any value,
  including above white) leaves the hue step with the same three equal values.
- **FX-004-R3**: The hue step keeps each colour's Rec. 709 luminance (within float rounding), and keeps hue and
  luminance when it must pull an undisplayable (negative) result toward grey.
- **FX-004-R4**: Rotation is predictable: the angle is measured around the grey axis so that +120 degrees maps the
  hue of red to that of green and green to blue, +240 degrees red to blue; the documented reference gives the
  exact expected values of a red patch at 0, 120 and 240 degrees.
- **FX-004-R5**: At hue 0 the hue step is skipped: with every other control neutral the output is bit-identical to
  the ungraded output, and with other controls active it is bit-identical to FX-003's grade.
- **FX-004-R6**: The hue step's place in FX-003's operator order is fixed and documented; the flash limiter
  measures the shifted, graded, tone-mapped colour.
- **FX-004-R7**: The hue is a registered parameter (MOD-001) with a stable ID, range, default and step hint.
- **FX-004-R8**: The hue is saved on the device with the other grade values, restored at launch, included in
  library backups, erased with the other settings, checked on read (missing, NaN, non-number → 0; out of range →
  clamped), and reset by "Reset to neutral".
- **FX-004-R9**: Settings → Color has a "Hue" slider with a readout and a spoken value ("plus 30 degrees"),
  VoiceOver-adjustable in steps.
- **FX-004-R10**: A plain-software reference of the hue step exists, testable without a GPU (Linux), and the GPU
  output matches it within FX-003's tolerances.
- **FX-004-R11**: No new render pass, texture or per-frame allocation; every existing golden image is unchanged.

### Key Entities

- **Color grade** (FX-003) gains **hue**: degrees, −180…+180, neutral 0.
- **Grey ramp**: greys from 0 to 1 plus over-range greys (above display white).
- **Red test patch**: linear (1, 0, 0).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-004-S1**: Through the real output pass at hue 30, 90, 180 and −120 degrees, every grey-ramp pixel stays
  neutral (its red, green and blue are equal within the stated tolerance) and keeps its displayed value.
- **FX-004-S2**: A red patch at 0, 120 and 240 degrees matches the reference values within one 8-bit step
  (screen) and 0.002 (half float).
- **FX-004-S3**: Over at least 10,000 sampled colours and angles, the reference keeps greys exactly neutral and
  luminance within 1e-9, in under 2 seconds.
- **FX-004-S4**: Hue 0 output is bit-identical to FX-003's (neutral and with other controls active); all
  RenderGoldens pass unchanged.
- **FX-004-S5**: With a hue shift active, frames flashing above the threshold make the limiter lower its gain.
- **FX-004-S6**: A user can find the Hue slider, change it and reset to neutral; the value survives a relaunch.
- **FX-004-S7**: The device frame rate with a hue shift is checked in the last stage (`{device}`).

## Assumptions

- FX-003's grade, FX-002's tone map and FX-019's guard are as integrated (ADR-0050).
- Live audio-reactive modulation of the hue is not wired (no compositor-backed visual has a modulator); the
  registry entry makes it possible later.
- The native spectra and projectM are not shifted (FX-003's scope).
