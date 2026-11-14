# Feature Specification: SHD-006 Noise Editor

**Feature Branch**: `feature/shd-006` (spec directory `245-shd-006-noise-editor`)
**Created**: 2026-11-14
**Status**: Draft
**Input**: User description: "Implement SHD-006 (Noise editor) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Configure octaves, seed, lacunarity and warp for procedural textures." Acceptance, verbatim:
"Fixed seed produces stable reference texture on same GPU class." P1, depends on SHD-001 (integrated)."

Identifiers in this feature carry the roadmap ID so they never collide with other features: requirements are
`SHD-006-R1…`, success criteria `SHD-006-S1…`, tasks `SHD-006-T01…`.

## Baseline: what exists today (audit of 2026-11-14, commit `60a69446`)

| Area | Today | Gap for this row |
|---|---|---|
| Noise Flow material (SHD-001, SHD-004) | `material.noiseFlow`: value-noise fBm with a fixed one-step domain warp; parameters scale, speed, octaves (1…5), tint, brightness, audio reactivity (6 of 8 uniform slots). Hash constants are fixed in the shader ("the seed is part of the material"); lacunarity 2.03, gain 0.5 and warp 0.8 are literals. Variants `noiseFlow` (Standard) and `noiseFlowLite` (Low cost: no warp, ≤ 3 octaves). | No seed, lacunarity, gain or warp controls; octaves stop at 5; the float hash degrades at large coordinates. |
| Parameter metadata (SHD-003) | Data-only JSON per material, strict validator (kinds float, int, bool, enum, color), slot cross-check against the reviewed shader constant, generic controls; **at most 8 parameters**. | Noise Flow plus five noise parameters needs 11. |
| Material inspector (SHD-003, SHD-004) | Generic controls for a scene's material layer, read-only: the app keeps material layers in scenes but does not draw them. | An editor there changes nothing visible. |
| Gradient editor (SHD-005) | Put in the palette editor because palettes colour what the app draws today. | No native visual uses noise. |
| Parameter registry (MOD-001) | Material parameters are descriptors; floats modulatable, ints manual. | — |
| Goldens | Per-material signature (mean, peak, 4 pixels) within 0.02 on the host GPU. | No exact (bit-level) reference for a seed. |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shape a procedural noise texture and see it at once (Priority: P1)

Someone opens the Noise editor, raises the octaves, changes the lacunarity, gain, warp amount and warp frequency,
types or steps a seed, or taps "Randomize seed". A preview drawn by the same GPU code as the material shows each
change immediately. The settings survive relaunch.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: A UI test opens the editor, steps the octaves and reads the value back, taps Randomize seed
and reads the new seed; app unit tests cover storage and clamping.

**Acceptance Scenarios**:

1. **Given** the editor at defaults, **When** Octaves is stepped up once, **Then** it reads 4 and the preview
   is redrawn.
2. **Given** a seed, **When** Randomize seed is tapped, **Then** a different seed is shown, chosen
   deterministically (the same sequence on every run), and the preview changes.
3. **Given** edited settings, **When** the app is relaunched, **Then** the editor shows the same values.

### User Story 2 - A fixed seed gives a stable reference texture (Priority: P1)

For one GPU class, the same settings and seed always produce the same pixels: twice in one run, and across
separate runs (pinned by a stored reference). A different seed gives a different texture.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: GPU readback of the noise texture twice in one process (bit-identical), compared with a
stored exact signature per GPU class and a tolerant golden signature; a second seed differs.

**Acceptance Scenarios**:

1. **Given** a fixed seed and settings, **When** the texture is rendered twice, **Then** the bytes are identical.
2. **Given** the stored reference for this GPU class, **When** the texture is rendered in a new test run,
   **Then** its exact signature equals the reference.
3. **Given** two different seeds, **When** both are rendered, **Then** the textures differ.

### User Story 3 - Each control does what it says (Priority: P2)

More octaves add finer detail; a higher lacunarity makes the added detail finer; a higher gain makes it stronger;
more warp moves the pattern further from the unwarped one; the warp frequency changes the warp's scale.

**Why this priority**: Controls that do nothing visible or behave erratically make the editor useless.

**Independent Test**: Measured high-frequency energy rises monotonically with octaves, lacunarity and gain; the
mean difference from the unwarped picture rises with warp amount; warp frequency changes the picture.

### Edge Cases

- Seed at 0 and at the maximum; octaves at 1 and 8; every parameter at its minimum and maximum: valid pixels.
- Warp amount 0: no warp is computed; the picture equals the unwarped noise.
- The Low cost variant ignores warp and draws at most 3 octaves, using the same seed, lacunarity and gain.
- Randomize seed never returns the current seed.
- Stored settings that are damaged or out of range: each bad entry falls back to its default or is clamped.
- Reduce flashing and the composite flash guard still apply wherever the material is composited.

## Requirements *(mandatory)*

### Functional Requirements

- **SHD-006-R1**: Noise Flow MUST expose, as metadata parameters, a seed (integer), octaves (1…8), lacunarity
  (1.5…3.5), gain (persistence), warp amount and warp frequency, in addition to its existing parameters.
- **SHD-006-R2**: The texture MUST be a pure function of position, phase and parameters: the seed is hashed into
  the lattice with integer arithmetic; no random number generator is used anywhere in drawing.
- **SHD-006-R3**: For one GPU class, identical settings MUST render bit-identical pixels within a run and across
  runs; distinct seeds MUST render different pixels.
- **SHD-006-R4**: Octaves, lacunarity and gain MUST change the picture monotonically in high-frequency energy;
  warp amount MUST change it monotonically in distance from the unwarped picture.
- **SHD-006-R5**: The metadata validator MUST accept the new parameters with existing kinds and keep rejecting
  invalid documents; every slot the shader reads MUST be declared.
- **SHD-006-R6**: The app MUST offer a Noise editor with one control per Noise Flow parameter (sliders with the
  ACC-005 helper), a "Randomize seed" action that picks a new seed deterministically from a counter, and a live
  preview drawn by the material's GPU code.
- **SHD-006-R7**: The editor's settings MUST persist across launches, follow the settings backup and erase rules,
  and tolerate damaged stored data.
- **SHD-006-R8**: Existing Noise Flow parameter IDs keep their meaning (IDs are permanent); scenes that store
  Noise Flow values keep loading.

### Key Entities

- **Noise settings**: seed, octaves, lacunarity, gain, warp amount, warp frequency (plus the material's scale,
  tint, brightness, speed, audio reactivity).
- **Reference signature**: an exact digest of a rendered texture for one GPU class, plus a tolerant summary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SHD-006-S1**: Two renders of one seed are byte-identical; a new run matches the stored exact reference on the
  same GPU class (macOS host GPU and the iOS simulator) — the acceptance.
- **SHD-006-S2**: Two different seeds differ in at least 25 % of pixels.
- **SHD-006-S3**: High-frequency energy strictly increases for octaves 1 → 2 → 4 → 8, lacunarity 1.5 → 2.5 → 3.5
  and gain 0.3 → 0.5 → 0.7; difference from unwarped strictly increases for warp 0 → 1 → 2 → 4.
- **SHD-006-S4**: A person can change any noise setting and see the preview update in under 30 seconds; the UI
  test runs in under 30 s.
- **SHD-006-S5**: Unit tests under 10 s each, package suites under one minute.

## Assumptions

- Material layers are kept in scenes but not drawn in this version; the GPU path is proven in the package and used
  by the editor's preview.
- A look at the preview on a physical device is a `{device}` task; correctness is proven on the Mac's GPU and the
  simulator.
