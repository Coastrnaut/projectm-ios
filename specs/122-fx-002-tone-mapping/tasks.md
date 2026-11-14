# Tasks: FX-002 Tone Mapping

**Input**: design documents in `specs/122-fx-002-tone-mapping/` (spec, plan, research, data-model,
contracts/tone-map.md, quickstart)

**Tests**: requested by the roadmap row (snapshot and shader unit tests) and the spec (FX-002-S1-S5, S7).
Budgets (owner rule 7): unit test about 1-2 s, at most 10 s; package suite under 1 minute.

Format: `- [ ] FX-002-Txx [P?] [Story?] Description with file path`. `{device}` marks a task the Mac
cannot finish.

## Phase 1: Setup

- [ ] FX-002-T01 Audit the output pass: run the current `cmp_output` on NaN, ±Inf, negative, over-range and
  alpha edge values in `bgra8Unorm_srgb`, `rgba16Float` and `bgra8Unorm` with
  `Packages/Compositor/Tests/CompositorTests/OutputPassRig.swift`; record the table in spec.md's audit (log
  `.autonomous/logs-fx-002/audit.log`).

## Phase 2: Foundational

- [ ] FX-002-T02 Create `Packages/Compositor/Sources/Compositor/ToneMap.swift`: `ToneMap.Pixel`
  (`SIMD4<Double>`), `luminanceWeights` (0.2126, 0.7152, 0.0722), `sanitize` ("non-finite or negative colour
  channels → 0; alpha non-finite → 0, then clamped to 0…1"), `map` (contract C1 steps 1-4, typed steps),
  `isNonFinite`; plain Swift, builds on Linux.
- [ ] FX-002-T03 Write `Packages/Compositor/Tests/CompositorTests/ToneMapReferenceTests.swift` (CPU): hand-checked
  values, identity for in-range pixels, special values, output luminance = min(Y, 1), ray monotonicity over a
  grid of hues and 0…64, 10,000 random colours in range and NaN-free (FX-002-S5, under 2 s).
- [ ] FX-002-T04 Add `cmp_tone_map` to `Packages/Compositor/Sources/Compositor/CompositorShaders.swift` as a
  Swift string constant (`toneMapSource`) spliced into `source`; `cmp_output` applies it before the gain and
  counts non-finite pixels into `device atomic_uint *` at buffer index 1 (research D4).

## Phase 3: User Story 1 - Bright layers look right, never broken (P1)

**Goal**: over-range, NaN and infinite values reach the screen in range, ordered and hue-kept. **Independent
test**: the reference gradient through the real output pass.

- [ ] FX-002-T05 [US1] Bind a counter buffer (screen pass) and a sink buffer (recording, capture) at fragment
  buffer index 1 in `Packages/Compositor/Sources/Compositor/Compositor.swift` and
  `Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift`; add `nonFiniteOutputPixels` to both.
- [ ] FX-002-T06 [US1] `Packages/Compositor/Tests/CompositorTests/ToneMapOutputTests.swift`: special values
  through the real `cmp_output` (OutputPassRig) in `bgra8Unorm_srgb` and `rgba16Float` equal the reference.
- [ ] FX-002-T07 [US1] Same file: a `GradientLayer` (0…16, four hue rows, alpha 1, blitted from a shared buffer)
  through `Compositor.composite` into both formats: monotonic per channel along each row, no NaN, 0…1, matches
  the reference within one 8-bit step / 0.002 (FX-002-S1).
- [ ] FX-002-T08 [US1] Same file: the non-finite counter counts the NaN/Inf pixels of a frame once (screen pass
  only) and stays 0 for the gradient.
- [ ] FX-002-T09 [US1] Run the RenderGoldens suite: zero golden changes (FX-002-S2), and the Compositor suite.

## Phase 4: User Story 2 - Recordings and captures match the screen (P1)

- [ ] FX-002-T10 [US2] Same file: one gradient frame shown into `bgra8Unorm_srgb`, `encodeOutput` into a
  `bgra8Unorm_srgb` recording target and `requestFrameCapture`; capture (sRGB-encoded) and recording equal the
  screen within one 8-bit step (FX-002-S4).

## Phase 5: User Story 3 - The flash limiter judges what the viewer sees (P1)

- [ ] FX-002-T11 [US3] Make `CompositeFlashGuard`'s sample read go through `cmp_tone_map` (spliced
  `CompositorShaders.toneMapSource`) in `Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift`;
  nothing else in the guard changes (ACC-012 coordination).
- [ ] FX-002-T12 [US3] Same test file: 1↔16 grey frames at 60 fps for 1 s keep `lastFlashGain` at 1 and the
  output white; 0↔16 lowers the gain below 1 and the output is gain × mapped value (FX-002-S3).

## Phase 6: Polish

- [ ] FX-002-T13 GPU timing (FX-002-S7): the output pass at 1920 × 1080 with the previous and the new
  `cmp_output`, 50 frames each, median GPU time printed and recorded in research.md (no threshold).
- [ ] FX-002-T14 Linux shape: the reference tests with `-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
  -DANALYSIS_NO_ACCELERATE`; regressions VisualGenerators, SceneFormat, ImportFuzz.
- [ ] FX-002-T15 App unit tests on an own simulator ("FX2 iPhone 17", iOS 27.2, `-only-testing:projectM-iOSTests`,
  derived data `.autonomous/derived-data-fx-002`); PosterBoard count before and after; delete the simulator.
- [ ] FX-002-T16 `docs/adr/0047-output-tone-map.md` (next free number above the integration branch's highest and
  above 0045/0046 reserved for FILE-011 and ACC-012) and the compositor header notes in `Compositor.swift`.
- [ ] FX-002-T17 Checks: `check_compliance.py`, `validate_docs.py`, `check_motion_policy.py`,
  `check_permission_catalog.py`, `check_status_events.py`, `test_scripts.py`; remove the audit scratch test.
- [ ] FX-002-T18 {device} On D1, a scene with a glowing spectrum layer over a bright photo: no hue-shifted
  clipping or broken pixels; frame rate as before (FX-002-S6, last stage).

## Dependencies

T01 → T02 → T03; T04 → T05 → T06-T08, T10; T04 → T11 → T12; T09 after T05 and T11; T13-T17 after the stories.
US1, US2 and US3 share T04 and are otherwise independent.

## Parallel examples

T02/T03 (CPU) can run beside T04 (shader). T06, T07, T08, T10, T12 are in one file: sequential.

## Implementation strategy

MVP = Phase 2 + US1 (the acceptance). Then US3 (safety), US2, polish.
