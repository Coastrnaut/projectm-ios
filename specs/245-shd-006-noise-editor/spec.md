# Feature Specification: SHD-006 Noise Editor

**Feature Branch**: `feature/shd-006` (spec directory `245-shd-006-noise-editor`)
**Created**: 2026-11-14
**Status**: Implemented 2026-11-14 (SHD-006-T01-T13 verified on the Mac: host GPU, iOS 27.2 simulator, Linux shape; device task T14 `{device}` open)
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

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4); each answer is the conservative,
local-first option.

- Q: Where do the noise parameters live? → A: On the existing Noise Flow material, as SHD-003 metadata
  parameters (no new material, no second parameter mechanism). Five are added after the existing six: `seed`
  (int 0…65535, default 0), `lacunarity` (float 1.5…3.5, step 0.01, default 2.03, the old literal), `gain`
  (float 0.2…0.8, step 0.01, default 0.5), `warpAmount` (float 0…4 cells, step 0.05, default 0.8, the old
  literal) and `warpFrequency` (float 0.25…4 × the base scale, step 0.05, default 1). The existing `octaves`
  range widens from 1…5 to 1…8 (same ID, kind and default; old values stay valid). Seed and octaves are integers
  (manual, steppers); the floats are modulatable (MOD-001 rule).
- Q: Noise Flow then needs 11 parameters but SHD-003 allows 8. What gives? → A: The cap rises from 8 to 16 for
  every material (validator, `MaterialDefinition`, the shader's uniform block: 16 `float4` slots, 272 bytes).
  Recorded as an ADR because it overrides SHD-001/SHD-003's documented limit. Alternatives rejected: a separate
  noise material with exactly 8 parameters (would drop scale, tint and brightness), packing several values into
  one slot (breaks "parameter i is slot i" everywhere), a second uniform block outside the metadata (the brief
  wants everything through metadata).
- Q: How is the seed made deterministic? → A: The lattice hash becomes integer arithmetic: the cell coordinates
  (wrapped to 4096 per axis) are combined with a key = seed | octave << 16 | field << 19 multiplied by an odd
  constant, then mixed with a fixed 32-bit integer finalizer. No `random()`, no time, no device state. Distinct
  keys give distinct masks, so distinct seeds give different textures. A CPU reference in Swift implements the
  same function (Linux-testable) and the GPU result is compared with it.
- Q: Does the Noise Flow picture change? → A: Yes, once: the old float hash (`fract(p·const)`) loses precision at
  the coordinates 8 octaves reach, so both variants switch to the integer hash; the warp becomes two-dimensional
  (two decorrelated warp fields). The Noise Flow golden signature is re-recorded; other materials' goldens are
  unchanged. Scenes keep their values (IDs unchanged); the app does not draw material layers yet, so nothing a
  user has seen changes.
- Q: What is "the same GPU class" and how is the reference stored? → A: The Metal device name (`MTLDevice.name`,
  e.g. the Mac's Apple GPU, the iOS simulator's GPU). The test keeps a table of exact FNV-1a 64-bit digests of the
  raw half-float readback per device name for three representative settings; on a device name without an entry
  it reports the digest and skips the exact comparison (honest: no reference for that class), while the tolerant
  golden signature (mean, peak, four pixels, ±0.02) applies everywhere.
- Q: Where does the editor live so it is usable today? → A: Settings › Noise editor, a dedicated screen (next to
  the palette link) with a live preview at the top and one generic control per Noise Flow parameter below,
  built from the metadata exactly like the material inspector (ACC-005 sliders, steppers, colour well), plus a
  "Randomize seed" button. The material inspector of a scene's layer stays read-only (layers are not drawn). The
  preview is drawn by the material layer's own GPU code at phase 0 (a still: no motion, so no flashing concern)
  at 256 × 256 points of pixels and redrawn on every change.
- Q: Where are the editor's settings stored? → A: One UserDefaults key, `settings.noiseEditor.values`, holding a
  small JSON object of parameter name → MOD-001 value; it is included in settings backups and the Settings
  erase (a user's creative setting, like palettes). Reading is lenient: unknown names are ignored, values are
  clamped by the material's rules, refused values fall back to defaults, damaged data reads as all defaults.
- Q: How does "Randomize seed" pick without a system RNG? → A: A counter (starting at 1 each launch) is
  hashed with the same 32-bit finalizer and reduced to 0…65535; if the result equals the current seed, the
  counter advances again. The sequence is therefore the same on every run (tests can predict it).
- Q: What about the Low cost variant? → A: It reads seed, lacunarity and gain too (one pass, at most 3 octaves,
  no warp); its metadata is the same document, so the slot check covers it.
- Q: Undo? → A: Editor changes are settings edits saved at once, not scene edits, so they are not in scene undo
  (like palette edits).

### Session 2026-11-18 (QA-011 device run)

- Q: SHD-006-T14 read the same Laplacian variance (0.0167-0.0170) for 3 and 6 octaves on D1-D3; does Detail not add detail? → A: It does: inside the preview image 6 octaves raise it 2.5× (D2 screenshots). The accessibility element is the full-width row, so the grid included the light background and measured the image's edges; the device test samples the centred square inset by 4 pt.

### Session 2026-11-19 (QA-011 device run)

- Q: SHD-006-T14 pass 3 read 0.02273 for 6 octaves against 0.02275 for 3, the same on D2 and D3; does the metric resolve octaves? → A: Not in that grid: the inset square still crossed the image's edge, which dominates the Laplacian (Randomize seed steps through a fixed sequence, so both iPads drew the same picture). Inside the image, D3's own screenshots give 0.000018 for 3 octaves and 0.000045 for 6 (2 pt grid, 2.5×). The grid is now the central half of the square.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Shape a procedural noise texture and see it at once (Priority: P1)

Someone opens the Noise editor, raises the octaves, changes the lacunarity, gain, warp amount and warp frequency,
types or steps a seed, or taps "Randomize seed". A preview drawn by the same GPU code as the material shows each
change immediately. The settings survive relaunch.

**Why this priority**: It is the roadmap row's observable behaviour.

**Independent Test**: A UI test opens the editor, taps Randomize seed and reads the new seed, drags the lacunarity
slider and reads the value back; app unit tests cover storage and clamping.

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
  and gain 0.3 → 0.5 → 0.7; difference from unwarped is positive and strictly increases for warp 0.5 → 1 → 2 (cells).
- **SHD-006-S4**: A person can change any noise setting and see the preview update in under 30 seconds; the UI
  test runs in under 30 s.
- **SHD-006-S5**: Unit tests under 10 s each, package suites under one minute.

## Assumptions

- Material layers are kept in scenes but not drawn in this version; the GPU path is proven in the package and used
  by the editor's preview.
- A look at the preview on a physical device is a `{device}` task; correctness is proven on the Mac's GPU and the
  simulator.
