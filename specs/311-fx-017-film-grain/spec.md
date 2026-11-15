# Feature Specification: FX-017 Film grain

**Feature Branch**: `feature/fx-017` (spec directory `311-fx-017-film-grain`)

**Created**: 2026-11-15

**Status**: Draft

**Input**: User description: "Implement FX-017 (Film grain) from docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable
behavior, verbatim: "Overlay deterministic seeded grain with optional temporal variation." Acceptance, verbatim: "Fixed
seed produces stable snapshots and opacity zero is identity." P3, effort S, depends on VIS-001 (integrated). Test: Metal
render passes; snapshot + shader unit + device GPU."

Identifiers in this feature carry the roadmap ID: requirements `FX-017-R1…`, success criteria `FX-017-S1…`, tasks
`FX-017-T01…`, research decisions `FX-017-D1…`. Other features are cited by their own IDs: CMP-001 (the compositor and
its frame clock), FX-002 (tone map), FX-003 (colour grade), FX-015 (vignette, the last output pass so far; ADR-0116),
FX-016 (lens distortion; ADR-0117), FX-011 (pixel sort) and FX-018 (scanlines), built in parallel, FX-019 (flash guard),
FX-020 (effect chains; ADR-0054), ACC-001 (Reduce Motion), ACC-005 (accessible sliders), ACC-012 (sensory safety
profile), PERF-004 (texture pool), SHD-011 (shader policy; ADR-0024), FILE-005/FILE-011 (backup and erase policy),
RenderGoldens (QA-002).

## Baseline: the audit (2026-11-15, commit `fd708845`)

**No film grain exists.** Searching the packages, the app and the scripts for "grain" finds only an unrelated word in
the autonomous scheduler; no integer hash (PCG, xxHash) exists in the shaders.

**Output effects today.** The compositor-backed visuals (Camera, Photo, Video, Text) share CMP-001's output chain:
layers → composite (linear premultiplied, half float) → FX-020's reorderable effects in `OutputEffectOrder` (Trails,
Color, Chromatic split, Directional blur, Radial blur, Echo, Mosaic, Edge outline, Lens distortion, Vignette) → FX-019
flash guard → output pass (grade, FX-002 tone map). FX-015 and FX-016 set the pattern this feature follows: an own pass
writing one pooled picture while active, walked in `Compositor.encodeOutputEffects`, its shader a module constant
spliced into the reviewed compile site in `Compositor.init` and listed in `CompositorShaderSources.archived`; a
non-neutral Color listed before it is folded into FX-020's grade pass; scenes store its entry only while it is on.
Every frame already carries CMP-001's injected clock (`LayerFrameContext`: presentation time, frame index, Reduce
flashing), so time-varying grain needs no new clock.

## Clarifications

### Session 2026-11-15 (speckit-specify)

Answered by Claude under the owner's standing approval (owner rule 4: best judgement, no human interaction); each
answer is the conservative option.

- Q: Where does the grain sit in the chain? → A: An own output pass, appended last in the FX-020 chain, after Vignette
  ("Film grain", stored kind `fx.filmGrain`). Grain is a texture on top of the finished picture: placed last, no later
  blur, warp or mosaic smears or enlarges it, and the vignette does not darken it away at the edges. It can be
  reordered and switched off on the Effect order screen like its siblings. Applied to FX-017-R1, R8.
- Q: How is the grain made deterministic? → A: From an integer hash (PCG family) of the grain cell's column and row,
  the seed, the grain frame and the colour channel; only integer operations until one exact conversion to a fraction.
  No floating-point sine hash, so every GPU and the software reference produce the same noise value bit for bit.
  Applied to FX-017-R3, R13.
- Q: What does "opacity" do and how strong can grain get? → A: Opacity 0…100 % (default 30 %) scales a zero-mean noise
  value n in [−1, 1) by a fixed bounded amplitude of 0.08 in linear light; the change is added to the colour (times the
  pixel's alpha, so premultiplied colour stays valid) and never pushes a channel below zero. The largest possible
  brightness change is ±0.08 of full white at 100 %; the average brightness does not change. Applied to FX-017-R3, R5.
- Q: What does "temporal variation" mean and how fast may it change? → A: A toggle (off by default). Off: the grain is
  static (grain frame 0). On: the grain frame advances with the injected frame clock at most 24 times per second (one
  step per 1⁄24 s of presentation time), whatever the display's frame rate, so grain never strobes at 60 or 120 Hz.
  Applied to FX-017-R4.
- Q: What do Reduce Motion and Reduce flashing do? → A: Either one forces static grain (grain frame 0) while it is on,
  whatever the toggle says; the grain itself stays visible. Static grain is a still texture, which neither setting
  restricts. Applied to FX-017-R4.

### Session 2026-11-15 (speckit-clarify)

Five questions, each answered by Claude with the recommended option (owner rule 4).

- Q: Which clock time drives temporal grain: time since the effect was turned on, or the frame's presentation time? →
  A: The frame's injected presentation time (CMP-001's `LayerFrameContext`), divided by a whole-number period of
  41 666 667 ns (just over 1⁄24 s). It needs no state in the effect, so the same time always gives the same grain
  (golden and test renders inject it) and a recording sees the same grain as the screen. Applied to FX-017-R4.
- Q: How do monochrome and colour grain relate? → A: Monochrome uses hash channel 0 for red, green and blue alike;
  colour uses channels 0, 1 and 2, so colour grain's red equals the monochrome grain of the same seed. Applied to
  FX-017-R3.
- Q: How is the seed chosen in Settings? → A: A stepper, whole numbers 0…9999 (default 1), step 1, spoken "Seed 1";
  no random button (a random seed would break the "same settings, same picture" promise). Applied to FX-017-R2, R9.
- Q: Is Film grain a global setting or a per-scene value? → A: Both, like FX-006 to FX-016: a global setting the
  visuals use, which a scene or effect-chain preset with an `fx.filmGrain` entry overwrites when opened; a scene
  without one leaves it alone. Applied to FX-017-R10, R11.
- Q: Is the 0.08 amplitude adjustable, or capped by the sensory safety profile? → A: Fixed and not user-adjustable;
  opacity is the only strength control. No ACC-012 cap: the mean brightness never changes and the peak change is
  bounded; the flash guard judges the shown frame. Applied to FX-017-R3, R5 and the Assumptions.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add a film texture (Priority: P1)

A performer shows the Photo visual and turns on Settings → Film grain: a fine, even grain appears over the whole
picture without making it brighter or darker overall. Opacity sets how strong it is, Size makes the grain coarser
(1, 2 or 3 pixels), Color switches between monochrome and colour grain, and Seed picks a different grain pattern.

**Why this priority**: it is the roadmap row's subject.

**Independent Test**: show a uniform mid-grey picture with grain on: pixels differ from grey, their average stays grey
within a small tolerance, and the same settings give the same picture every time.

**Acceptance Scenarios**:

1. **Given** Film grain on at 30 %, size 1, monochrome, seed 1, static, **When** the same frame is shown twice (or on a
   later frame, or after a relaunch), **Then** both pictures are identical pixel for pixel.
2. **Given** seed 1, **When** the seed is changed to 2, **Then** the grain pattern changes.
3. **Given** a uniform mid-grey picture, **When** grain is on at any opacity, **Then** the mean brightness differs from
   the input by less than 0.5 % of full white, and in monochrome red, green and blue change by the same amount.
4. **Given** size 2, **When** a uniform picture is shown, **Then** every 2 × 2 block of pixels carries one grain value.

---

### User Story 2 - Opacity zero is the picture (Priority: P1)

A performer who leaves Film grain off, or sets its opacity to zero, sees exactly the picture the app showed before.

**Acceptance Scenarios**:

1. **Given** the effect off, or on at opacity 0 with any seed, size, colour mode and temporal setting, **When** any
   frame (random content) is shown, **Then** every output pixel is bit-identical to the output without this feature,
   and no extra picture memory is held.

---

### User Story 3 - Living grain (Priority: P2)

The performer turns on "Vary over time": the grain pattern changes gently, like film running through a projector, at
no more than 24 changes per second; with Reduce Motion or Reduce flashing on it stays still.

**Acceptance Scenarios**:

1. **Given** temporal variation on, **When** two frames 1⁄24 s apart are shown, **Then** their grain differs; two frames
   in the same 1⁄24 s step, or the same frame time rendered twice, are identical.
2. **Given** temporal variation on and the display running at 120 Hz, **When** one second is shown, **Then** the grain
   changes at most 24 times.
3. **Given** temporal variation on and Reduce Motion or Reduce flashing on, **When** frames are shown, **Then** the
   grain is identical to the static grain.

---

### User Story 4 - Part of the effect chain and scenes (Priority: P2)

The performer reorders Film grain on the Effect order screen, saves a scene and an effect-chain preset, and gets the
same grain back (same seed, same pattern) when the scene or preset is opened.

**Acceptance Scenarios**:

1. **Given** a scene saved with Film grain on, **When** it is opened, **Then** its values and position are restored and
   its static grain renders identically; a scene without a Film grain entry leaves the current values (FX-020's rule).
2. **Given** a scene from before this feature, **When** it is opened and saved, **Then** it renders and encodes exactly
   as before.

### Edge Cases

- Values missing, not numbers, NaN or out of range: off, the default, or the nearest limit; a fractional seed or size is
  rounded to the nearest whole number.
- A frame smaller than 2 pixels in either direction: passes through.
- Transparent pixels (alpha 0): unchanged (the grain is scaled by alpha).
- Black and near-black pixels: never pushed below zero; values already below zero are not changed further downward.
- Non-finite picture values: passed through the addition (FX-002 handles them downstream); finite input gives finite
  output.
- Bright (HDR, above 1) values: grain added the same way, bounded by the amplitude.
- A size change (rotation, external display): the grain cells follow pixel positions from the top-left corner; the
  pattern at a given pixel does not depend on the frame size.
- A very long session: the grain frame counter wraps safely (32-bit) without a visible jump in behaviour.
- Visuals that are not compositor-backed (native spectra, projectM): unchanged; the help text names the visuals.

## Requirements *(mandatory)*

### Functional Requirements

- **FX-017-R1**: Film grain (on/off, off by default) applies to the compositor-backed visuals (Camera, Photo, Video,
  Text) on every output of a frame: screen, external display, recording and still capture.
- **FX-017-R2**: Controls: Opacity 0…100 % (default 30 %, VoiceOver step 1 %), Size 1, 2 or 3 pixels (default 1),
  Color mode monochrome or colour (default monochrome), Seed a whole number 0…9999 (default 1), and "Vary over time"
  on/off (default off).
- **FX-017-R3**: For pixel (x, y) with size s, the cell is (⌊x ÷ s⌋, ⌊y ÷ s⌋); a 32-bit integer hash of the cell, the
  seed, the grain frame and the channel (one channel in monochrome, three in colour) gives a 24-bit value u, and the
  noise is n = u × 2⁻²³ − 1 (exactly representable, in [−1, 1)). The change is d = opacity × 0.08 × n × alpha, and the
  output colour channel is max(c + d, min(c, 0)); the output alpha is the input alpha. It applies to the linear
  premultiplied picture, before the flash guard and the tone map.
- **FX-017-R4**: The grain frame is 0 when "Vary over time" is off, or Reduce Motion or Reduce flashing is on;
  otherwise it is ⌊presentation time ÷ (1⁄24 s)⌋ of the frame's injected clock, taken modulo 2³². It never advances
  more than 24 times per second of presentation time.
- **FX-017-R5**: The grain is zero-mean: over a uniform picture the mean change is within 0.5 % of full white of zero,
  and no channel changes by more than opacity × 0.08 × alpha.
- **FX-017-R6**: Film grain is active only when on, opacity is above zero and the frame is at least 2 × 2; otherwise no
  pass runs and the output is bit-identical to the output before this feature. The pass itself returns its input
  exactly when its opacity is zero.
- **FX-017-R7**: Each output pixel costs one exact read, at most three hashes and a few arithmetic steps.
- **FX-017-R8**: Film grain is an FX-020 reorderable output effect (`fx.filmGrain`), appended last in the standard order
  (after Vignette). Its position is honoured; the flash guard and the tone map always run after it.
- **FX-017-R9**: Settings has a "Film grain" section: an on/off toggle, an Opacity slider with ACC-005 spoken values
  ("30%", spoken "30 percent"), a Size picker (1, 2, 3 px), a Color mode picker, a Seed stepper, a "Vary over time"
  toggle and help text. The Effect order screen lists it with its own on/off switch.
- **FX-017-R10**: The values are saved on the device, restored at launch, included in library backups, erased with the
  other settings, checked on read, and removed by the UI-test reset.
- **FX-017-R11**: Scenes and effect-chain presets store Film grain as an `fx.filmGrain` entry (`opacity`, `size`,
  `color`, `seed`, `animated`) in FX-020's `effects` list, written only while it is on; out-of-range values are clamped
  and reported; scenes without it encode byte-identically.
- **FX-017-R12**: Active grain uses one pooled picture at output size and one full-screen pass per frame, no per-frame
  allocation; the picture returns to the pool when the grain turns inactive, the size changes or the visual is
  released.
- **FX-017-R13**: A plain-software reference of the hash, the noise and the output exists, testable without a GPU
  (Linux), and the GPU noise equals it exactly; the GPU output matches it within half-float rounding.
- **FX-017-R14**: The shader is a module constant added to the compositor's existing reviewed compile site and to the
  pipeline-archive key sources; no new compile site, no user-authored shader.

### Key Entities

- **Film grain setting**: on/off, opacity, size, colour mode, seed, vary over time.
- **Grain frame**: the integer that selects the grain pattern in time (0 when static).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **FX-017-S1**: Off, and on at opacity 0 (several seeds, sizes, colour modes, temporal on), are bit-identical to the
  output without the feature on random content; the pass run directly at opacity 0 also returns its input bit for bit;
  all existing RenderGoldens pass unchanged.
- **FX-017-S2**: With a fixed seed and static grain, two renders (and renders at different frame times) are
  bit-identical, the GPU noise equals the software reference's, and a golden image of the grain matches.
- **FX-017-S3**: Different seeds give different pictures; with temporal variation on, frames in different 1⁄24 s steps
  differ and the same (seed, step) renders identically.
- **FX-017-S4**: On a uniform mid-grey picture the mean change is under 0.5 % of full white, no pixel changes by more
  than the bound, and every output is finite for finite input.
- **FX-017-S5**: A scene and a preset with Film grain round-trip to the same values and picture; a scene from before
  the feature encodes byte-identically.
- **FX-017-S6**: A user can find Film grain, turn it on and change its controls (UI test under 30 s); the values
  survive a relaunch (setting test with a reloaded store).
- **FX-017-S7**: The device frame rate with Film grain on is checked in the last stage (`{device}`).

## Assumptions

- The compositor, FX-002, FX-003, FX-006 to FX-016, FX-019 and FX-020 are as integrated; FX-011 (inserted before
  Vignette) and FX-018 (which may follow this feature) are built in parallel and add their own kinds; the merge
  reconciles the order by keeping both.
- Grain changes average brightness by nothing and peak brightness by at most 0.08 of full white; the flash guard still
  judges the shown frame, so no ACC-012 cap is added; Reduce Motion and Reduce flashing only freeze the pattern.
- The roadmap's "CIColorKernel where appropriate" is not used: the compositor's Metal output-pass pattern covers this
  per-pixel effect.
- Live audio-reactive modulation of the grain is not wired.
