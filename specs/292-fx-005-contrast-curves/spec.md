# Feature Specification: FX-005 Contrast Curves

**Feature Branch**: `feature/fx-005` (spec directory `292-fx-005-contrast-curves`)

**Created**: 2026-11-15

**Status**: Clarified 2026-11-15

**Input**: User description: "Implement FX-005 (Contrast curves) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Provide S-curve, filmic and linear presets." Acceptance, verbatim: "Neutral curve is identity
and extreme values stay bounded." P2, effort M, depends on VIS-001 (integrated). Verification: snapshot tests,
shader unit tests, and the device GPU in the last stage. Builds on FX-003 colour grading (ADR-0050), FX-004 hue
shift and FX-020 effect chains."

Identifiers in this feature carry the roadmap ID: requirements `FX-005-R1…`, success criteria `FX-005-S1…`,
tasks `FX-005-T01…`, research decisions `FX-005-D1…`. Other features are cited by their own IDs: FX-002 (tone
mapping; ADR-0047), FX-003 (colour grading; ADR-0050, `specs/123-fx-003-color-grading`), FX-004 (hue shift,
`specs/126-fx-004-hue-shift`), FX-019 (composite flash guard), FX-020 (effect chains; ADR-0054,
`specs/142-fx-020-effect-chains`), MOD-001 (parameter registry), ACC-005 (accessible sliders), ACC-012 (sensory
safety profile), FILE-005 (library backup settings policy), FILE-011 (local data erase), SCN-001 (scene format),
RenderGoldens (QA-002 golden images).

## Baseline: the audit (2026-11-15, commit `3b447170`)

**No contrast curve exists.** The only tone curves on the finished picture are FX-003's gamma (a power curve, not
an S-shape: it brightens or darkens mid-tones but has no pivot) and FX-002's tone map (identity up to display
white; above it a luminance-keeping desaturation, no toe or shoulder). Neither offers a contrast preset.

**FX-003 grades the finished composite.** The compositor-backed visuals (Camera, Photo, Video, Text) send every
output through one output pass: composite → FX-003's grade (temperature, lift, gamma, gain, saturation, FX-004
hue; every control neutral = the pixel untouched, bit for bit) → FX-002's tone map → × the flash guard's gain.
FX-019's guard measures through the same function. FX-020 can run the grade as its own pass before Trails (without
the tone map). The grade is one global setting (`settings.colorGrade.*`), shown in Settings → Color, registered as
MOD-001 parameters `effect.colorGrade.*`, and saved in a scene's `effects` list as the `fx.grade` entry.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction);
each answer is the conservative option.

- Q: A new effect, or part of FX-003's grade? → A: Part of the grade: a "Contrast" choice (Linear, S-curve,
  Filmic) and a "Contrast strength" in Settings → Color, on the same visuals and outputs, saved, restored and
  reset with the other grade values and in the scene's grade entry. No new effect kind in FX-020's chain.
  Applied to FX-005-R1, R8, R9.
- Q: Is a free "Custom" curve (pivot control) included? → A: No. Three presets plus strength cover the roadmap
  row; a pivot or point editor is a later row. Applied to FX-005-R1 and the Assumptions.
- Q: What is "neutral"? → A: Linear, or any curve at strength 0. Neutral is skipped entirely, so the picture is
  bit-identical to the output without this feature. Applied to FX-005-R4.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Where does the contrast curve run in the grade's operator order? → A: Last, after FX-004's hue. Colours
  above display white are first brought into range with FX-002's luminance-keeping step, then the curve is applied
  to the display-range values; FX-002's tone map that follows is then an exact identity. The curve therefore runs
  exactly once whether the grade is in the output pass or in FX-020's pass before Trails, and every earlier result
  is unchanged. Applied to FX-005-R6 and Edge Cases.
- Q: Does the curve act on each colour channel or on brightness only? → A: On each channel with the same curve
  (the film convention): a grey stays exactly grey, and each channel stays inside 0…1 by construction. Applied to
  FX-005-R2, R5.
- Q: Where is the S-curve's pivot, and how steep can it get? → A: Mid-grey 0.18 in linear light, a fixed point;
  the slope at the pivot is 1 + strength (up to twice the contrast at full strength). Filmic is a toe-and-shoulder
  curve blended with the identity by strength. Applied to FX-005-R5.
- Q: What strength and steps do the controls use? → A: Strength 0…1, default 0.5 (so choosing a preset has a
  visible effect), parameter step hint 0.01, one VoiceOver swipe 0.05 (20 steps), readout and spoken value in
  percent ("50%", "50 percent"). The strength slider is shown only while a curve other than Linear is chosen.
  Applied to FX-005-R7, R9.
- Q: How are the curve and strength stored in a scene? → A: In the existing `fx.grade` entry's parameters, as
  `contrast` (the preset name: `linear`, `sCurve` or `filmic`) and `contrastStrength` (a number); a missing name
  reads as Linear, an unknown name reads as Linear with a warning and is kept in the file, and the strength follows
  the other values' rules (missing → 0.5, not a number → 0.5 with a warning, out of range → clamped). No format
  version bump. Applied to FX-005-R8.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Give a visual more punch (Priority: P1)

A performer shows the Photo visual and finds it flat: they open Settings → Color, choose "S-curve" under
Contrast and raise the strength; shadows deepen and highlights brighten while mid-grey stays put. "Filmic" gives a
softer film look with a gentle toe and shoulder. The choice is kept at the next launch and saved in scenes.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: render a grey ramp through the output pass with each preset and compare with the reference;
relaunch and check the choice is kept.

**Acceptance Scenarios**:

1. **Given** S-curve at strength 1, **When** the visual shows a grey ramp, **Then** values below mid-grey become
   darker, values above it brighter, black stays black and white stays white, and the ramp still rises
   everywhere (never reverses).
2. **Given** Filmic, **When** the visual shows a grey ramp, **Then** the ramp still rises everywhere with black
   and white kept, and the result differs from S-curve.
3. **Given** a preset and strength set, **When** the app is relaunched or a scene with them is loaded, **Then**
   the same contrast is shown and applied.

---

### User Story 2 - Linear is exactly "off" (Priority: P1)

A performer who never touches Contrast, chooses Linear, sets strength 0 or taps "Reset to neutral", sees exactly
what the app showed before this feature.

**Independent Test**: render the reference image with Linear and compare bit for bit with the output without the
feature, both with the other grade controls neutral and active.

**Acceptance Scenarios**:

1. **Given** Linear (or strength 0) and the other controls neutral, **When** a frame is shown, **Then** every
   pixel is bit-identical to the ungraded output.
2. **Given** Linear and other controls active, **When** a frame is shown, **Then** it equals the grade of those
   controls bit for bit.

---

### User Story 3 - Extreme pictures stay displayable (Priority: P1)

Whatever the composite holds (very bright HDR values, negative values, NaN or infinity from a broken source), the
contrast curve gives a finite colour inside the display range, and the flash limiter judges the curved picture.

**Acceptance Scenarios**:

1. **Given** any preset and strength, **When** a channel is 1e6, −1, NaN or ±infinity, **Then** the output is
   finite and inside 0…1.
2. **Given** frames alternating above the flash threshold, **When** a contrast curve is active, **Then** the
   limiter still lowers its gain.

### Edge Cases

- Colours brighter than display white: compressed into range first (FX-002's luminance-keeping step), then curved,
  so the curve always works on display-range values.
- Premultiplied, partly transparent pixels: curved as the colour shown over black, as the rest of the grade does.
- Stored values missing, unknown curve names, NaN or out of range: Linear; strength missing → 0.5, NaN → 0.5,
  out of range → clamped to 0…1.
- Old scenes and settings without contrast: read as Linear.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged (FX-003's scope).

## Requirements *(mandatory)*

### Functional Requirements

- **FX-005-R1**: The colour grade has a contrast curve choice with three presets — Linear (neutral), S-curve and
  Filmic — and a strength from 0 to 1, applied to the same visuals and outputs as FX-003's grade.
- **FX-005-R2**: Every curve, at every strength, maps 0 to 0 and 1 to 1, never decreases (monotone), and maps
  0…1 into 0…1.
- **FX-005-R3**: Extreme inputs (very large, negative, NaN, ±infinity) give finite outputs inside 0…1.
- **FX-005-R4**: Linear or strength 0 skips the curve: with every other control neutral the output is
  bit-identical to the ungraded output; with other controls active it is bit-identical to the grade without the
  curve.
- **FX-005-R5**: The curve acts on each colour channel alike (greys stay grey). S-curve raises contrast around
  mid-grey 0.18 (linear light), which maps to itself, with slope 1 + strength there; Filmic is a toe-and-shoulder
  curve distinct from S-curve and from FX-002's tone map, blended with the identity by strength, with documented
  parameters.
- **FX-005-R6**: The curve runs last in the grade (after hue), on colours first brought into display range by
  FX-002's luminance-keeping step; the flash limiter measures the curved colour; it applies exactly once whether the
  grade runs in the output pass or before Trails.
- **FX-005-R7**: The curve and strength are registered parameters (MOD-001) with stable IDs, cases or range,
  defaults and step hints.
- **FX-005-R8**: Curve and strength are saved on the device with the other grade values, restored at launch,
  included in library backups, erased with the other settings, checked on read, and reset by "Reset to neutral".
  A scene's `fx.grade` entry saves and restores them (`contrast`, `contrastStrength`); scenes without them read as
  Linear, and an unknown curve name reads as Linear with a warning.
- **FX-005-R9**: Settings → Color has a "Contrast" picker (Linear, S-curve, Filmic) and, while a curve is chosen, a
  "Contrast strength" slider with a percent readout and spoken value, VoiceOver-adjustable in 5% steps.
- **FX-005-R10**: A plain-software reference of the curves exists, testable without a GPU (Linux), and the GPU
  output matches it within FX-003's tolerances.
- **FX-005-R11**: No new render pass, texture or per-frame allocation; every existing golden image is unchanged.

### Key Entities

- **Color grade** (FX-003) gains **contrast curve** (Linear, S-curve, Filmic; neutral Linear) and **contrast
  strength** (0…1).
- **Grey ramp**: greys from 0 to 1 plus over-range greys.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-005-S1**: Over a dense sweep (at least 4,096 values) and 1,000 random colours, Linear and strength 0 return
  every input bit for bit.
- **FX-005-S2**: For each preset at strengths 0.25, 0.5 and 1, the reference is monotone over the sweep, maps
  0 → 0 and 1 → 1 exactly, and stays inside 0…1.
- **FX-005-S3**: For each preset, inputs 1e6, −1, NaN, +∞ and −∞ give finite outputs inside 0…1.
- **FX-005-S4**: Through the real output pass, each preset matches the reference within one 8-bit step (screen)
  and 0.002 (half float); Linear is bit-identical to the output without the curve; all RenderGoldens pass
  unchanged.
- **FX-005-S5**: A scene and a backup round-trip keep curve and strength; a scene without them reads as Linear.
- **FX-005-S6**: A user can choose a preset, change strength and reset to neutral in Settings → Color; the choice
  survives a relaunch.
- **FX-005-S7**: The device frame rate with a curve active is checked in the last stage (`{device}`).

## Assumptions

- FX-003's grade, FX-004's hue, FX-002's tone map, FX-019's guard and FX-020's chain are as integrated.
- Live modulation of the strength is not wired (no compositor-backed visual has a modulator); the registry entry
  makes it possible later.
- No custom curve editor or pivot control in this row.
- ACC-012's profile does not cap the curve: it never raises the display maximum (white stays white) and the flash
  guard measures the curved picture under every profile.
