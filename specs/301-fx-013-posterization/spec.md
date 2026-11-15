# Feature Specification: FX-013 Posterization

**Feature Branch**: `feature/fx-013` (spec directory `301-fx-013-posterization`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-013 (Posterization) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Quantize RGB to selectable step counts with dithering toggle." Acceptance, verbatim: "Known
gradient contains at most configured levels without dithering." P2, size S, depends on VIS-001 (integrated).
Builds on FX-003 colour grading (ADR-0050), FX-004 hue shift, FX-005 contrast curves and FX-020 effect chains."

Identifiers in this feature carry the roadmap ID: requirements `FX-013-R1…`, success criteria `FX-013-S1…`,
tasks `FX-013-T01…`, research decisions `FX-013-D1…`. Other features are cited by their own IDs: FX-002 (tone
map; ADR-0047), FX-003 (colour grade; ADR-0050), FX-004 (hue), FX-005 (contrast curves,
`specs/292-fx-005-contrast-curves`), FX-019 (composite flash guard), FX-020 (effect chains; ADR-0054), MOD-001
(parameter registry), ACC-005 (accessible sliders), ACC-012 (sensory safety profile), FILE-005 (backup settings
policy), FILE-011 (local data erase), SCN-001 (scene format), OUT-009 (external display calibration).

## Baseline: the audit (2026-11-15, commit `9f422733`)

**No posterization exists.** Nothing in the app quantises the finished picture to a chosen number of levels. The
closest things are the output formats themselves (8-bit sRGB screen, half-float recording and capture), which
quantise to 256 or more levels per channel.

**FX-003's grade is the per-pixel operator chain on the finished composite**, and FX-005 extended it the same way
this feature will: composite → grade (temperature, lift, gamma, gain, saturation, FX-004 hue, FX-005 contrast
curve; all neutral = the pixel untouched, bit for bit) → FX-002 tone map → × FX-019's flash gain (→ OUT-009's
calibration on an external display). The guard measures through the same grade function. FX-020 can run the grade
as its own pass before Trails. The grade is one global setting (`settings.colorGrade.*`) shown in Settings → Color,
registered as MOD-001 parameters `effect.colorGrade.*`, and saved in a scene's `fx.grade` entry. The grade's
operator flags use bits 1-32 (FX-003, FX-004) and 256/512 (FX-005); 64 and 128 are free.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction);
each answer is the conservative option.

- Q: A new effect, or part of FX-003's grade? → A: Part of the grade, as FX-005 did: a "Posterize" switch, a
  "Levels" count and a "Dither" switch in Settings → Color, on the same visuals and outputs, saved, restored and
  reset with the other grade values and in the scene's `fx.grade` entry. No new effect kind, render pass or texture.
  Applied to FX-013-R1, R8, R9, R11.
- Q: What are "step counts"? → A: The number of output levels per colour channel, the same for red, green and
  blue: a whole number from 2 to 32, default 6. Applied to FX-013-R1, R2.
- Q: What does "off" mean? → A: Posterize switched off skips the step entirely, so the picture is bit-identical to
  the output without this feature. Dithering only matters while posterize is on. Applied to FX-013-R4.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Flatten a visual into poster bands (Priority: P1)

A performer wants a graphic, poster-like look: they switch on Posterize in Settings → Color and choose a level
count; every colour channel of the picture then takes only that many values, so smooth gradients turn into flat
bands.

**Why this priority**: It is the roadmap row's observable behaviour and its acceptance test.

**Independent Test**: Show a known horizontal gradient, posterize at L levels without dithering, and count the
distinct values per channel in the output.

**Acceptance Scenarios**:

1. **Given** a smooth black-to-white gradient (and coloured gradients) and Posterize on at L levels with dithering
   off, **When** the output is shown, **Then** each colour channel contains at most L distinct values.
2. **Given** Posterize on, **When** the user changes the level count, **Then** the bands change to match.

### User Story 2 - Dithered posterization (Priority: P2)

The user turns on "Dither" so bands are broken up with a fixed, fine pattern, which hides banding edges while still
using only the chosen levels.

**Independent Test**: With dithering on, each channel still takes at most L values, the same input gives the same
output every time, and the output depends on pixel position only through a fixed pattern.

**Acceptance Scenarios**:

1. **Given** dithering on, **When** a gradient is shown, **Then** each channel still uses at most L values and
   neighbouring pixels may alternate between adjacent levels.
2. **Given** the same picture shown twice, **When** dithering is on, **Then** both outputs are identical (no
   random or time-varying noise).

### User Story 3 - Off is exactly off, and extremes stay displayable (Priority: P1)

**Acceptance Scenarios**:

1. **Given** Posterize off (whatever the level count and dither), **Then** the output is bit-identical to the
   output without this feature.
2. **Given** a pixel whose channel is 1e6, −1, NaN or ±infinity, **When** Posterize is on, **Then** the output is
   finite and one of the L levels.
3. **Given** frames alternating above the flash threshold, **When** Posterize is on, **Then** the flash limiter
   still lowers its gain.

### Edge Cases

- Colours brighter than display white: brought into range first by FX-002's luminance-keeping step, then
  quantised.
- Premultiplied, partly transparent pixels: quantised as the colour shown over black, as the rest of the grade.
- Level count missing, not a number or out of range: default 6, clamped to 2…32, rounded to a whole number.
- The flash guard's gain, OUT-009's calibration and FX-020's Color-before-Trails order act after or around the
  grade: a flash gain below 1 or a calibration maps each level to one other value (still at most L per channel);
  Trails blending posterized frames can show in-between values (documented, not a defect).
- Old scenes and settings without posterize: read as off.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged (FX-003's scope).

## Requirements *(mandatory)*

### Functional Requirements

- **FX-013-R1**: The colour grade has a Posterize switch (off by default), a level count per channel (whole number
  2…32, default 6) and a Dither switch (off by default), applied to the same visuals and outputs as FX-003's grade.
- **FX-013-R2**: With Posterize on and dithering off, every colour channel of the shown picture takes at most L
  distinct values, evenly spaced on the display's brightness scale from black to full, including black and full.
- **FX-013-R3**: Extreme inputs (very large, negative, NaN, ±infinity) give finite outputs that are one of the L
  levels.
- **FX-013-R4**: Posterize off skips the step: with every other control neutral the output is bit-identical to the
  ungraded output; with other controls active it is bit-identical to the grade without posterization.
- **FX-013-R5**: Dithering on adds a fixed ordered pattern depending only on pixel position before quantising: the
  output is deterministic and still uses at most L values per channel.
- **FX-013-R6**: Posterization runs last in the grade (after FX-005's curve), on colours first brought into
  display range; every later step of the output is an exact identity for its results except the flash gain and
  external-display calibration; the flash limiter measures the posterized colour.
- **FX-013-R7**: Posterize, level count and dither are registered parameters (MOD-001) with stable IDs, ranges,
  defaults and step hints; they are chosen by hand (not modulated).
- **FX-013-R8**: The three values are saved on the device with the other grade values, restored at launch,
  included in library backups, erased with the other settings, checked on read, and reset by "Reset to neutral". A
  scene's `fx.grade` entry saves and restores them; scenes without them read as off, and a malformed value reads as
  its default with a warning.
- **FX-013-R9**: Settings → Color has a "Posterize" switch and, while it is on, a "Levels" slider (whole steps,
  readout "6 levels", spoken value) and a "Dither" switch, VoiceOver-adjustable.
- **FX-013-R10**: A plain-software reference of the step exists, testable without a GPU (Linux), and the GPU output
  matches it.
- **FX-013-R11**: No new render pass, texture or per-frame allocation; every existing golden image is unchanged.

### Key Entities

- **Color grade** (FX-003) gains **posterize** (on/off), **posterize levels** (2…32) and **posterize dither**
  (on/off).
- **Known gradient**: a horizontal ramp from black to white (and per-channel ramps) used by the acceptance tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-013-S1**: On a dense 0…1 gradient (at least 4,096 values) for L in {2, 3, 6, 16, 32}, dithering off, the
  reference output of each channel takes at most L distinct values (and exactly L over the full ramp).
- **FX-013-S2**: Posterize off returns every input bit for bit (dense sweep and 1,000 random colours, including with
  other grade controls active).
- **FX-013-S3**: Inputs 1e6, −1, NaN, +∞ and −∞ give finite outputs that are one of the L levels.
- **FX-013-S4**: With dithering on, each channel still takes at most L values, two runs give identical output, and
  a flat mid-grey between two levels shows both levels.
- **FX-013-S5**: Through the real output pass on a horizontal gradient, each channel holds at most L distinct values
  in both output formats (8-bit screen, half float) with dithering off; GPU and reference agree on at least 99% of
  pixels, and every disagreement is one adjacent level.
- **FX-013-S6**: A scene and a backup round-trip keep the three values; a scene without them reads as off.
- **FX-013-S7**: A user can turn on Posterize, change Levels and reset to neutral in Settings → Color; the choice
  survives a relaunch.
- **FX-013-S8**: The device frame rate with posterize and dither on is checked in the last stage (`{device}`).

## Assumptions

- FX-003's grade, FX-004's hue, FX-005's curve, FX-002's tone map, FX-019's guard and FX-020's chain are as
  integrated.
- Per-channel level counts (different for red, green and blue) and other dither kinds (error diffusion, blue
  noise) are out of scope.
- ACC-012's profile does not cap posterization: it never raises the display maximum, and the flash guard measures
  the posterized picture (so band jumps that would flash are limited) under every profile.
