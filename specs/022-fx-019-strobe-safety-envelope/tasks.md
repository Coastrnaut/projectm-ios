# Tasks: FX-019 Strobe safety envelope

**Input**: Design documents in `specs/022-fx-019-strobe-safety-envelope/` (spec.md, plan.md,
research.md, data-model.md, contracts/flash-envelope.md, quickstart.md), ADR-0011.

**Tests**: test-first. Each test task comes before the code it covers; the red run (compile failure
or failing assertions) is recorded before the production change. Owner rule 7 (2026-11-13): tests
are short evidence: each about 1–2 s on the Mac host (at most 10 s), the new FlashSafety tests
together under 20 s; GPU acceptance uses two or three representative sequences per pipeline at
64 × 64 and about 2 s of frames; no speed assertions.

**Format**: `- [ ] ID [P?] [Story?] Description with file path`. `[P]` = can run in parallel
(different files). Tags: `{device}` = needs a physical device, done only in the roadmap's final
device phase; `{sim}` = needs the iOS 27.2 simulator "iPhone Air" (udid
`77E17861-E687-4274-8A84-14224F32BE3E`).

A task is ticked only when its acceptance evidence was produced, with " — Verified <date>: <how>"
appended. Inside descriptions, "T07" is short for `FX-019-T07`. Logs go to `.build/scratch/`.
Constraints quoted from data-model.md: budget "clamped to 2…6", thresholds "0.10" and "0.0625",
"window 1.0", "gateMargin 0.005", "maxFrameTime 0.1", rise "0.25" (on) / "nil" (off).

## Phase 1: Setup

- [ ] FX-019-T01 Confirm the baseline: `swift test` for `Packages/VisualGenerators` on the host and with `-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`; `python3 scripts/check_compliance.py`, `scripts/validate_docs.py`, `scripts/test_scripts.py`; record counts.
- [ ] FX-019-T02 Create `Packages/FlashSafety/Package.swift` (swift-tools 6.0, platforms iOS 26 / macOS 15, library `FlashSafety`, test target `FlashSafetyTests`, no dependencies) with a placeholder source; evidence: `swift build --package-path Packages/FlashSafety` succeeds.

## Phase 2: Foundational (the shared definition; blocks every story)

- [ ] FX-019-T03 [P] Write `Packages/FlashSafety/Tests/FlashSafetyTests/FlashAnalysisTests.swift`: hand-made series with known transitions (hysteresis 0.1: 0→0.09→0 none; 0→0.1→0 two; a slow 0→1 ramp one; window counting with frame times 0.1 s: transitions at ages 0.95 and 1.0 s — the first counts, the second does not); `maxFlashesPerWindow` = ⌈transitions / 2⌉; `FlashColor`: sRGB decode at 0, 0.04045, 0.5, 1; relative luminance of white 1, red 0.2126; redness of red 1, white 0, magenta 0; `tileLevels` of a 4 × 4 RGBA8 image with one white tile.
- [ ] FX-019-T04 [P] Write `Packages/FlashSafety/Tests/FlashSafetyTests/FlashEnvelopeTests.swift`: configurations (`.reduceFlashing` budget 4, rise 0.25; `.alwaysOn` budget 6, no rise; budget clamped to 2…6); first frame after init or `reset` → gain 1; gain always in 0…1 and finite for NaN/∞/negative inputs; rise ceiling (on): from 0 to white at dt 0.1 the shown luminance is 0.025, then 0.05; frame time clamp (5 s acts as 0.1, negative as 0); the gate: after `budget − 2` transitions a rise from black is held at low + 0.095 and then released once the oldest age reaches 1 s; falls are never held; local strobe in tile 5 only dims the whole frame; the closure API equals the linear API for linear levels within 1e-6; state survives a configuration change.
- [ ] FX-019-T05 Record the red run of T03-T04 (`swift build --build-tests` fails on missing symbols) in `.build/scratch/fx019-red-T03-T04.log`.
- [ ] FX-019-T06 Implement `Packages/FlashSafety/Sources/FlashSafety/FlashEnvelopeConfiguration.swift`, `FlashEnvelope.swift` (state preallocated for 17 areas × 2 signals × 6 ages; no allocation per call), `FlashAnalysis.swift`, `FlashColor.swift` per contracts/flash-envelope.md and data-model.md. Evidence: T03-T04 pass on the host.

## Phase 3: User Story 1 - strobing content is held within the limits (P1)

**Goal**: the roadmap acceptance on all three paths. **Independent test**: the acceptance matrix.

- [ ] FX-019-T07 [US1] Write `Packages/FlashSafety/Tests/FlashSafetyTests/FlashAcceptanceTests.swift` (pure envelope, both configurations, all 17 areas): white/black alternation at 60, 30, 15 and 10 Hz; red/black at 10 Hz; 50 % gray steps (encoded 0.5 ↔ 0 every 0.1 s); slow fade 0→1→0 at 0.2 per second; a single white frame on black; seeded noise (LCG, per-frame random gray); a strobe in one tile. For each, measure the output with `FlashAnalysis` per area and signal: transitions per window ≤ budget, per-frame rise ≤ 0.25 × dt + 1e-9 (on), output ≤ input; run twice and compare exactly; print one matrix line per case.
- [ ] FX-019-T08 [US1] Record T07's red run if any case fails, fix the cause in `FlashEnvelope.swift`, and record the passing matrix. Evidence: `swift test --package-path Packages/FlashSafety` passes; the printed matrix is copied into the report.
- [ ] FX-019-T09 [P] [US1] Write the projectM GPU tests in `Packages/ANGLERendering/Tests/ANGLERenderingTests/FlashLimiterTests.swift` {sim}: solid frames (64 × 64 surface) through the renderer's limiter: white/black 60 Hz with Reduce flashing on (≤ 4 transitions per window, rise ≤ 0.25·dt + 1/255), white/black 10 Hz off (≤ 6), red/black 15 Hz on (redness ≤ 4); measured from read-back pixels with `FlashColor.tileLevels`; the GPU gain equals `FlashEnvelope`'s linear gain for the same levels within 0.01; output ≤ input. Amend the T104 tests that are intentionally changed: no gray lift on a cut to black (the black frame stays black), rate 0.25.
- [ ] FX-019-T10 [P] [US1] Amend `Packages/Rendering/Tests/RenderingTests/GLESRendererTests.swift` {sim}: the fallback creates and uses the pass with the setting off and on (`flashLimiterGain` in 0…1); white/black 60 Hz on through the fallback's limiter obeys ≤ 4 transitions per window (read-back).
- [ ] FX-019-T11 [US1] Record the red run of T09-T10 (compile failure on the new C API) in `.build/scratch/fx019-red-T09-T10.log`.
- [ ] FX-019-T12 [US1] Implement the GLSL port in `Packages/Rendering/Sources/CFlashLimiter/FlashLimiter.c` and `include/CFlashLimiter.h` (measure 4 × 4, state 10 × 18 ping-pong, output by gain in exact sRGB; size changes keep state; `PMFlashLimiterLastGain`), `Packages/Rendering/Sources/Rendering/FlashEnvelopeParameters.swift`, the `FlashSafety` dependency in `Packages/Rendering/Package.swift` and `Packages/ANGLERendering/Package.swift`, and the renderers (`ANGLERenderer.swift`, `GLESRenderer.swift`: always through the pass, `.forReduceFlashing(reduceFlashing)`, no reset on toggle, `flashLimitPerSecond` = 0.25, `timedFrames` keeps T104's bypass baseline). Evidence: ANGLERendering and Rendering-Package tests pass on the simulator; the measured matrix printed.
- [ ] FX-019-T13 [P] [US1] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/StrobeEnvelopeTests.swift` (CPU, every host): `meanLevels` tile coverage sums to the bars' exact area (1e-6 relative) and the whole-frame value equals `meanLuminance(gain:transfer:)`; identity redness of the spectrum palette is positive in the top tiles; bands alternating 0/1 at 60 Hz, mono and spectrum palettes, with and without the strongest glow, Reduce flashing on and off: per area and signal ≤ budget transitions per window (measured with `FlashAnalysis` on `meanLevels` at the applied gain).
- [ ] FX-019-T14 [P] [US1] Write `Packages/VisualGenerators/Tests/VisualGeneratorsTests/StrobeEnvelopeRenderTests.swift` (Metal, skips without a device): generator → bloom at 64 × 64, 120 frames: mono bars alternating at 60 Hz with the setting off (≤ 6 per window measured from pixels) and spectrum at 10 Hz on (≤ 4, rises ≤ bound + 0.01).
- [ ] FX-019-T15 [US1] Record the red run of T13-T14 in `.build/scratch/fx019-red-T13-T14.log`.
- [ ] FX-019-T16 [US1] Implement native integration: `FrameLuminanceTransfer.outputRedness`, `BloomLuminanceModel.outputRedness`, `CircularSpectrumLayout.meanLevels(gain:transfer:into:)` (exact tile coverage of the tessellated triangles, computed once per layout), `FlashSafetyLimiter` on `FlashEnvelope`, `CircularSpectrumGenerator` always using area levels; `FlashSafety` dependency in `Packages/VisualGenerators/Package.swift`. Amend `GlowFlashSafetyTests.testReduceFlashingOffLeavesGainOne` (stricter always-on cap). Evidence: VisualGenerators tests pass on the host (Metal) and in the Linux shape; VIS-001 and FX-001 tests otherwise unchanged.

## Phase 4: User Story 2 - extreme strobing is capped with Reduce flashing off (P1)

- [ ] FX-019-T17 [US2] Evidence only: in T07, T09, T13 and T14 the off cases yield ≤ 6 transitions per window, the single flash and steady content pass with gain 1, and a 4-frame alternation (VIS-001's `testDisabledIsPassThrough`) is unchanged.

## Phase 5: User Story 3 - slow and steady content untouched (P2)

- [ ] FX-019-T18 [US3] Add to `FlashAcceptanceTests.swift`: a 0.2-per-second fade is bit-for-bit unchanged under both configurations; after a clamped 60 Hz strobe, a constant input yields a monotone nondecreasing output that reaches the input (report the frames to recovery: the pumping measure).

## Phase 6: Polish & cross-cutting

- [ ] FX-019-T19 Add `FlashSafety` to the package loops of `.github/workflows/ios-ci.yml` (Linux and macOS); add `FlashSafety` to `project.yml` only if the app build cannot resolve the transitive package. Evidence: workflow YAML parses; `python3 scripts/test_scripts.py` passes.
- [ ] FX-019-T20 {sim} App checks: `xcodegen generate`; build `projectM-iOS` for the simulator; run the app unit tests, `SettingsUITests` and `NativeVisualUITests` (owner rule 7). Known environmental failure: `PresetTests.testBundledIncludedScopeMatchesRelease1_0`. Count new PosterBoard reports.
- [ ] FX-019-T21 Docs: `docs/test-reports/performance.md` T104 section notes the FX-019 pass (cost unmeasured on devices); `docs/FEATURE_ROADMAP_AUTONOMOUS.md` FX-019 row unchanged (status is the integrator's); `python3 scripts/validate_docs.py` and `check_compliance.py` pass.
- [ ] FX-019-T22 {device} Measure the pass cost on D1 with RendererLab `RL_MODE=flashcost` (T104 method; target ≤ 2 ms per frame, FX-019-S6) and watch a strobing preset with Reduce flashing off and on.
- [ ] FX-019-T23 {device} On D1 and D3, confirm visually that a strobing preset is clamped with the setting off and that ordinary presets look unchanged.

## Dependencies

T01 → T02 → T03/T04 → T05 → T06 → (T07 → T08) ∥ (T09/T10 → T11 → T12) ∥ (T13/T14 → T15 → T16) →
T17, T18 → T19 → T20 → T21. T22-T23 wait for the roadmap's device phase.

## Parallel examples

- T03 and T04 (different test files). T09, T10, T13, T14 (different packages).

## Implementation strategy

MVP = Phase 2 + T07/T08 (the definition, proven on synthetic sequences); then the projectM path
(the most strobing content), then native visuals, then CI and app checks.
