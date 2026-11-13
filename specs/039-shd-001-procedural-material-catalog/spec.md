# Feature Specification: SHD-001 Procedural Material Catalog

**Feature Branch**: `feature/shd-001` (spec directory `039-shd-001-procedural-material-catalog`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement SHD-001 (Procedural material catalog) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose curated parameterized
visual materials built into app." Acceptance, verbatim: "Every material loads with documented
default parameters and no external code." Depends on MOD-001 (integrated: Packages/ParameterGraph,
ADR-0012, the typed parameter registry)."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `SHD-001-R1…`, success criteria `SHD-001-S1…`, tasks `SHD-001-T01…`.

## Baseline: what exists today (audit of 2026-11-13, commit `94f0192`)

The row's gap status is "Gap candidate". The audit confirms it.

| Area | Today | Gap for this row |
|---|---|---|
| Native visuals | Two spectra (VIS-001, VIS-002) and the glow (FX-001), drawn by shaders that are Swift string constants compiled when a generator is created (ADR-0009 decision 3). | No picture that is not a spectrum: no "material" (a full-frame procedural picture such as a plasma or a gradient). |
| Layers | CMP-001 (ADR-0013) defines the layer contract and the compositor with its composite flash guard; spectra and the rear camera (CAM-001) are layers. | No material layers. |
| Parameters | MOD-001 (ADR-0012) defines stable IDs, bounds, defaults, units and modulation policies; the spectra and the glow are registered. | No material parameters. |
| Shader safety | Every shader in the app is a constant in the app's own code; nothing is compiled from user text or downloaded. | Nothing states or tests this rule for a catalog of authored visuals that later rows (SHD-002 graphs, SHD-004 variants, SHD-011 policy) will extend. |

## Clarifications

### Session 2026-11-13

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human
interaction); each answer is the conservative, local-first option.

- Q: Which five materials make up the curated catalog? → A: Gradient Field (`material.gradient`, two colors turning slowly), Plasma (`material.plasma`, soft interfering waves), Noise Flow (`material.noiseFlow`, drifting layered value noise in one tint), Ring Tunnel (`material.tunnel`, soft concentric rings moving outward) and Starfield (`material.starfield`, small stars drifting from the center). Rejected: a kaleidoscope or feedback material (feedback can build up brightness over frames and is harder to bound) and any material that blinks by design (SHD-001-R1).
- Q: Does this row add anything a viewer can see in the app (a picker or a debug view)? → A: No. The catalog is exposed to code only; choosing and stacking materials belongs to CMP-002 (layer stack), their inspector controls to SHD-003 (shader parameter metadata) and variant switching to SHD-004. Rejected: a Debug-only viewer (it would add app code and tests for a screen no user sees; the package's GPU tests already render every material).
- Q: How does music drive a material? → A: Through one level per frame: the mean of the audio context's bands (clamped to 0…1, NaN ignored, silence when there are none), smoothed so it rises by at most 4 per second and falls by at most 1 per second, then multiplied by the material's "Audio reactivity" (0…1, default 0.25); the material's speed is multiplied by 1 + that product, so music can at most double the speed and never changes brightness (SHD-001-R10).
- Q: Which parameters may be modulated or controlled externally? → A: Continuous parameters (speeds, scales, brightness, contrast, audio reactivity) use the MOD-001 continuous default (modulatable by replace, add, multiply; MIDI/OSC allowed). Colors and the integer octave count are manual only with external control allowed (MOD-001's discrete policy), because modulating them per frame gives abrupt color or detail jumps (SHD-001-R2).
- Q: What does a golden snapshot store, and with what tolerance? → A: For each material at 64 × 64, after 30 frames at 60 frames per second (0.5 s) with no music: the picture's mean and peak linear RGB and four sampled pixels (the centre and three fixed points; the peak catches a blank sparse material such as the starfield), stored as numbers in the test source; a channel may differ by at most 0.02 (half-float rounding and GPU-class differences). No images are stored (SHD-001-R14).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Built-in materials ready to use (Priority: P1)

A later feature (a scene, a layer stack, an inspector) asks the app which visual materials it ships.
It receives a fixed list: each material has a stable identifier, a name for people, a one-line
description and its documented parameters with their ranges, units and default values. It picks one
and gets a ready layer that draws that material at its defaults.

**Why this priority**: It is the row's observable behavior and its acceptance: every material loads
with documented defaults.

**Independent Test**: Enumerate the catalog; for every material, create its layer, prepare it and
draw one frame at the default parameters; the frame is a valid, non-empty picture.

**Acceptance Scenarios**:

1. **Given** the app's catalog, **When** a caller lists it, **Then** it receives every material in a
   fixed order with ID, name, description and parameter descriptions, and every parameter has a
   documented default inside its range.
2. **Given** any material, **When** its layer is created and prepared, **Then** preparation succeeds
   and the first frame at default parameters is a full, finite, opaque picture that is not blank.
3. **Given** the same material, parameters and frame sequence, **When** it is drawn twice, **Then**
   the two pictures are identical.

---

### User Story 2 - Materials are adjustable within safe bounds (Priority: P1)

A caller (later: an inspector, a modulation binding, MIDI or OSC) changes a material's parameters.
Each value is clamped to its documented range, a value of the wrong kind or not finite is refused,
and the picture follows the new values from the next frame. No value in range can make the material
produce broken pixels.

**Why this priority**: "Parameterized" in the observable behavior; safe bounds are what lets later
rows hand the parameters to external control and modulation.

**Independent Test**: Set every parameter to its minimum and then its maximum; draw frames; every
pixel stays finite and valid. Set an out-of-range value; the stored value is the bound.

**Acceptance Scenarios**:

1. **Given** a material, **When** a parameter is set above its maximum, **Then** the stored value is
   the maximum (below the minimum: the minimum).
2. **Given** a material, **When** a non-finite number, an unknown parameter or a value of another
   kind is set, **Then** it is refused with an error and the previous value stays.
3. **Given** every parameter at its minimum or at its maximum, **When** frames are drawn, **Then**
   every pixel is finite and valid.

---

### User Story 3 - Materials never flash on their own (Priority: P1)

A viewer sensitive to flashing light watches a material. At default parameters the material moves
slowly and does not flash at all, with or without music. Under every setting the material is drawn
as a layer below the app's composite flash guard (FX-019), and music can only change how fast it
moves, never how bright it is.

**Why this priority**: Flash safety is a constitution-level product rule (ADR-0011); a catalog that
could strobe by default would be a defect.

**Independent Test**: Draw two seconds at 60 frames per second at default parameters and measure the
picture's 17 flash areas: no area changes luminance often enough to count as a flash under the
Reduce flashing limits, and the composite flash guard never has to dim the picture.

**Acceptance Scenarios**:

1. **Given** any material at default parameters, **When** two seconds are drawn at 60 frames per
   second with no music, **Then** no flash area shows more than two transitions in any one-second
   window under the Reduce flashing thresholds, and the composite guard's gain stays 1.
2. **Given** any material at its fastest settings with music at full level, **When** two seconds are
   drawn, **Then** no flash area exceeds the always-on budget (six transitions per second) even
   before the composite guard.
3. **Given** any material, **When** music plays, **Then** the music changes only the material's
   motion, through a smoothed level whose effect is bounded.

---

### User Story 4 - No external code (Priority: P1)

The app's owner and reviewers can see that every material is authored in the app's own source and
built into the app: nothing is read from a file, a document, the network or user input to make a
shader, and a check fails the build if that changes.

**Why this priority**: "no external code" is half of the acceptance; later rows (SHD-002 graphs,
SHD-011 policy) rely on it.

**Independent Test**: A source scan of the materials module finds shader compilation only from
constants defined in the module and no file, bundle or network reads.

**Acceptance Scenarios**:

1. **Given** the materials module, **When** its sources are scanned, **Then** every shader
   compilation call takes the module's own constant source and nothing reads files, bundles, URLs
   or the network.
2. **Given** a material ID that is not in the catalog, **When** a caller asks for it, **Then** the
   catalog returns nothing; no material can be created from caller-supplied text.

### Edge Cases

- A material's layer is prepared at a size of 1 × 1 or a very wide size: it draws without error.
- A frame arrives with no analysis yet (no bands): the material draws as with silence.
- Bands contain NaN or values outside 0…1: they are ignored or clamped; the picture stays valid.
- A frame duration of 0 (frame 0) or a long stall: motion uses the compositor's clamped duration, so
  a stall never jumps the picture.
- Shader preparation fails (no GPU resources): preparation reports the error and the compositor
  shows the layer's transparent fallback.
- The app runs for hours: motion stays smooth (time is kept with enough precision).
- A material's parameter set changes in a later version: IDs are permanent; removed IDs are retired,
  never reused (MOD-001 rule).

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-001-R1**: The app MUST ship a fixed, curated catalog of five procedural materials, in this
  order: Gradient Field, Plasma, Noise Flow, Ring Tunnel, Starfield; each has a stable ID of the
  form `material.<name>`, a display name and a one-line description. None blinks by design.
- **SHD-001-R2**: Every material parameter MUST be registered in the MOD-001 typed parameter registry
  with a stable ID `material.<name>.<parameter>`, a display name, a group per material, a unit, a
  kind with bounds and a default inside them, and a modulation policy (continuous parameters:
  modulatable, external control allowed; colors and counts: manual, external control allowed); the
  catalog's registry MUST pass MOD-001 validation.
- **SHD-001-R3**: The catalog MUST let a caller list materials, their parameter descriptions and
  their default values, and create a material's layer by ID; an unknown ID MUST yield nothing.
- **SHD-001-R4**: A material's layer MUST implement the CMP-001 layer contract: it draws the whole
  picture each frame as linear, premultiplied, opaque color from the frame and audio contexts it is
  given; its fallback is transparent.
- **SHD-001-R5**: A material's output MUST be determined only by its parameters, the sequence of frame
  contexts and the audio contexts: no wall clock, no randomness that is not seeded by the material
  itself; drawing the same sequence twice MUST give identical pictures.
- **SHD-001-R6**: Setting a parameter MUST clamp numbers to the documented range (integers to their
  step), refuse non-finite numbers, unknown IDs and values of the wrong kind without changing the
  stored value, and take effect from the next frame.
- **SHD-001-R7**: Every material's shader code MUST be authored in the app's source and built into
  the app; it MUST NOT be compiled from user text, documents, files or anything downloaded, and the
  app MUST NOT load shader code at run time from any other source.
- **SHD-001-R8**: The materials module MUST be checked automatically for SHD-001-R7: a test fails if
  its sources compile shaders from anything other than the module's own constants or read files,
  bundles, URLs or the network.
- **SHD-001-R9**: Every material's speed and color parameters MUST be bounded so that its brightness
  cannot exceed full white and its motion cannot oscillate faster than one cycle per second without
  music (two with music).
- **SHD-001-R10**: Music MUST change only a material's motion (its speed), through a level that is
  smoothed with a bounded rate of change (rise at most 4 per second, fall at most 1 per second) and
  scaled by a bounded "audio reactivity" parameter (0…1), so music at most doubles the speed; music
  MUST NOT change brightness directly.
- **SHD-001-R11**: At default parameters, with or without music, no material may produce more than
  two luminance or redness transitions (FX-019 thresholds) in any one-second window in any of the 17
  flash areas, and the composite flash guard MUST NOT need to dim it.
- **SHD-001-R12**: At any parameter values in range and any music level, no material may exceed the
  always-on envelope (six transitions in any one-second window) in any flash area before the
  composite flash guard; the guard still applies on top.
- **SHD-001-R13**: Every pixel a material draws MUST be finite, with color between 0 and alpha and
  alpha exactly 1, for every parameter value in range.
- **SHD-001-R14**: Each material MUST have a recorded reference ("golden") signature at 64 × 64 after
  30 frames at 60 frames per second (mean and peak linear RGB and four sampled pixels, stored as numbers,
  no images), and a test MUST fail when a channel drifts by more than 0.02.
- **SHD-001-R15**: The catalog, IDs, descriptors, parameter values and motion bookkeeping MUST build
  and be tested on Linux; only the drawing compiles out there.
- **SHD-001-R16**: The cost of drawing each material per frame on the three test devices MUST be
  measured and recorded (device stage, last).

### Key Entities

- **Material**: one curated procedural picture: ID, display name, description, parameter list,
  shader entry point.
- **Material parameter**: one adjustable value of a material, described by a MOD-001 descriptor
  (ID, name, group, unit, kind with bounds and default, modulation policy).
- **Material parameter values**: the current, clamped values of one material's parameters.
- **Material motion**: the material's accumulated animation phase and smoothed music level, advanced
  once per frame from the frame duration.
- **Material layer**: a CMP-001 layer that draws one material.
- **Catalog**: the ordered list of materials, their registry and the factory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-001-S1**: 5 of 5 materials load at their documented defaults and draw a non-blank, valid
  picture on the first frame (the acceptance's "loads with documented default parameters").
- **SHD-001-S2**: 100% of material parameters (every one in the catalog) pass registry validation
  and have a default inside their bounds.
- **SHD-001-S3**: The source check finds 0 shader compilations from non-constant input and 0 file,
  bundle or network reads in the materials module (the acceptance's "no external code").
- **SHD-001-S4**: Two draws of the same 120-frame sequence are identical for 5 of 5 materials.
- **SHD-001-S5**: At defaults over 2 seconds at 60 frames per second, 0 flash areas exceed 2
  transitions per window for 5 of 5 materials, and the composite guard's gain stays 1.
- **SHD-001-S6**: At extreme parameters with full music, 0 flash areas exceed 6 transitions per window
  and 0 pixels are non-finite or invalid.
- **SHD-001-S7**: Each material's reference signature matches within the documented tolerance.
- **SHD-001-S8**: The per-material frame cost is recorded for D1, D2 and D3 (device stage).

## Assumptions

- A user-facing material picker, scene placement and layer stacking belong to later rows (CMP-002
  layer stack, SHD-003 shader parameter metadata for inspectors, SHD-004 variant switching); this row
  exposes the catalog to code only and adds no app screen, not even a Debug viewer.
- The build Mac has no Metal Toolchain (ADR-0009 decision 3), so "built into the app" means shader
  source compiled into the app binary as constants and turned into a GPU library on the device when a
  material is prepared, exactly like every other shader in the app.
- Colors are linear-light RGB with straight alpha 1 (MOD-001's color kind); materials are opaque.
- Golden signatures are compared on the same GPU class (Mac host or simulator); device GPUs may
  differ within the tolerance.
- Five materials are a small, conservative curated set; more can be added later without changing
  IDs.
