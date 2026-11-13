# Implementation Plan: FX-019 Strobe safety envelope

**Branch**: `feature/fx-019` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/022-fx-019-strobe-safety-envelope/spec.md`

## Summary

One flash-safety envelope (ADR-0011, new), defined once and applied to every picture the app shows:

1. **New package `Packages/FlashSafety`** (pure Swift, no dependencies, Linux-testable; research
   FX-019-D4): `FlashEnvelopeConfiguration` (`.reduceFlashing`, `.alwaysOn`), `FlashLevels`,
   `FlashZones` (whole frame + 4 × 4 tiles), `FlashEnvelope` (the decision rule of FX-019-D2, no
   allocation per frame), `FlashAnalysis` (independent measurement of a sequence: transitions per
   sliding window, rises, falls), `FlashColor` (WCAG relative luminance, redness, tile levels of an
   RGBA8 image for tests). Contract: [contracts/flash-envelope.md](contracts/flash-envelope.md).
2. **projectM frames** (`Packages/Rendering/Sources/CFlashLimiter`, research FX-019-D5): the GLSL
   port of the rule; measure (4 × 4), state (10 × 18 ping-pong) and output passes; new
   `PMFlashEnvelopeParameters`; `PMFlashLimiterFinish(limiter, target, &parameters)`;
   `PMFlashLimiterLastGain`; size changes keep the state. Swift glue
   `FlashEnvelopeConfiguration.limiterParameters(frameTime:)` in `Rendering`.
   - `ANGLERenderer` and `GLESRenderer`: every frame goes through the pass (always-on cap, FX-019-R7)
     with `.forReduceFlashing(reduceFlashing)`; toggling no longer resets; `flashLimitPerSecond`
     becomes the configuration's 0.25; `timedFrames(_:reduceFlashing:)` keeps T104's comparison
     (false = pass bypassed); test hooks `flashLimiterGain`, `limitedSolidFrame(r:g:b:frameTime:)`.
3. **Native visuals** (`Packages/VisualGenerators`, research FX-019-D6):
   - `FrameLuminanceTransfer.outputRedness(ofFlatColor:)` (default: the color's own redness);
     `BloomLuminanceModel` implements it.
   - `CircularSpectrumLayout.meanLevels(gain:transfer:into:)` with exact per-tile coverage (bar
     triangles clipped to tiles, computed once per layout).
   - `FlashSafetyLimiter`: owns a `FlashEnvelope`; bar slew unchanged (on only); every `gain` API
     goes through the envelope with `.forReduceFlashing(enabled)`.
   - `CircularSpectrumGenerator`: always uses the area levels (identity transfer when no glow).
4. **App**: no code change; settings, notice and keys stay (FX-019-R12). App unit tests and the
   Settings and native-visual UI suites are rerun.
5. **Shared files**: `.github/workflows/ios-ci.yml` package loops gain `FlashSafety` (one word per
   loop); `Packages/VisualGenerators/Package.swift`, `Packages/Rendering/Package.swift`,
   `Packages/ANGLERendering/Package.swift` gain the path dependency. `project.yml` and
   `AppCoordinator.swift` are not changed unless the app build needs it.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), GLSL ES 3.00 in C (CFlashLimiter), Metal
(existing native passes, unchanged)

**Primary Dependencies**: none new; system Metal, ANGLE (pinned, ADR-0004), Apple OpenGL ES (fallback)

**Storage**: none (FX-019-R12)

**Testing**: XCTest; `swift test` on the Mac host (Linux shape for VisualGenerators with
`-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`) and in CI on Linux; `xcodebuild test` on the iOS
27.2 iPhone Air simulator for Rendering, ANGLERendering and VisualGenerators

**Target Platform**: iOS/iPadOS 26.0+ (app), Linux and macOS 15 (FlashSafety tests)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: projectM post-pass ≤ 2 ms per frame on D1 (T104 target, `{device}`); native
envelope a few microseconds of CPU per frame (17 areas × 24 bisection steps × 128 bars)

**Constraints**: no allocation, lock or I/O per frame; deterministic; never brighter than the input;
tests short (owner rule 7: each ~1–2 s, new package tests together < 20 s)

**Scale/Scope**: 17 areas × 2 signals; transition budget ≤ 6

## Constitution Check

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | Metal, OpenGL ES (public, deprecated but ADR-0003 Option A), ANGLE via EGL; no dlsym | Pass |
| VI Modular boundaries | Envelope in its own package; renderers depend on it, not on each other; native visuals unaware of projectM | Pass |
| VII Real-time safety | No allocation/lock/I/O per frame (state preallocated; GPU passes reuse textures) | Pass |
| VIII Upstream fidelity | `Vendor/projectM` untouched; the pass is the app's own code | Pass |
| IX Dependencies | None added | Pass |
| X Evidence | Unit tests for the rule; GPU tests on simulator/Mac are logic evidence only; device cost `{device}` | Pass |
| Privacy | Nothing stored, logged or sent | Pass |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/022-fx-019-strobe-safety-envelope/
├── plan.md  research.md  data-model.md  quickstart.md
├── contracts/flash-envelope.md
├── checklists/requirements.md
└── tasks.md
docs/adr/0011-strobe-safety-envelope.md
```

### Source Code (repository root)

```text
Packages/FlashSafety/                      # new
├── Package.swift
├── Sources/FlashSafety/{FlashEnvelopeConfiguration,FlashEnvelope,FlashAnalysis,FlashColor}.swift
└── Tests/FlashSafetyTests/{FlashEnvelopeTests,FlashAnalysisTests,FlashAcceptanceTests}.swift
Packages/Rendering/Sources/CFlashLimiter/{FlashLimiter.c,include/CFlashLimiter.h}
Packages/Rendering/Sources/Rendering/{GLESRenderer,FlashEnvelopeParameters}.swift
Packages/Rendering/Tests/RenderingTests/GLESRendererTests.swift
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift
Packages/ANGLERendering/Tests/ANGLERenderingTests/FlashLimiterTests.swift
Packages/VisualGenerators/Sources/VisualGenerators/{FlashSafetyLimiter,FrameLuminanceTransfer,CircularSpectrumLayout,CircularSpectrumGenerator}.swift
Packages/VisualGenerators/Sources/VisualEffects/BloomLuminanceModel.swift
Packages/VisualGenerators/Tests/VisualGeneratorsTests/{FlashSafetyLimiterTests,GlowFlashSafetyTests,StrobeEnvelopeTests,StrobeEnvelopeRenderTests}.swift
.github/workflows/ios-ci.yml               # package loops only
```

## Test design (deterministic)

- Synthetic sequences are arrays of solid levels (or band vectors) with constant frame times; the
  envelope's clock is the sum of clamped frame times. Seeded noise uses a fixed linear congruential
  generator. Every assertion is on values, never on time.
- Each sequence is measured by `FlashAnalysis` (independent of the envelope's own state) on the
  output: worst transitions in any 1 s window ≤ budget, per-frame rise ≤ rate × dt (on), output ≤
  input. Runs are repeated to show identical results.
- GPU tests read back a 64 × 64 target per frame, compute WCAG levels per tile from the pixels with
  `FlashColor`, and analyze them the same way (tolerance one 8-bit step).
- Amended earlier tests (only where FX-019 is stricter): ANGLE `FlashLimiterTests` (no gray lift;
  0.25 per second), GLES `testTheFallbackLimitsFlashingWhenOn` (pass runs with the setting off too),
  `GlowFlashSafetyTests.testReduceFlashingOffLeavesGainOne` (the always-on cap clamps sustained
  60 Hz strobing; replaced by "off leaves non-strobing content at gain 1"),
  `FlashSafetyLimiterTests.testDisabledIsPassThrough` (still holds: 4 frames are within the cap).

## Licensing and cross-feature notes

- No third-party code or text is copied: WCAG, ITU-R BT.1702 and Ofcom are cited for their
  thresholds only. No dependency is added (Constitution IX).
- PERF-011: the projectM limiter is released on suspension (state lost, as before); the native
  host's loop restart calls `FlashSafetyLimiter.reset()`, which keeps the envelope history.
- ANL-005 (another agent) changes `Packages/AnalysisFeatures` only; this row does not touch it.
- ACC-002, ACC-012, PERF-003 consume `FlashEnvelopeConfiguration` later (ADR-0011 decision 6).

## Persistence and rollback

- Nothing is persisted. Rollback is a code revert of this branch's commits; no stored data or
  setting changes meaning. The C limiter's public header changes, so renderers and tests move
  together in one commit.

## Complexity Tracking

| Addition | Why needed | Simpler alternative rejected because |
|---|---|---|
| New package | Both renderers and Linux CI share one definition | VisualGenerators pulls audio analysis into the projectM renderers; Rendering is iOS-only |
| GLSL port of the rule | Same-frame decision without a CPU stall | CPU read-back stalls the pipeline every frame (FX-019-D4) |
| 4 × 4 areas | WCAG's area rule (~8 % of a phone screen) | Whole-frame mean dilutes local strobes (FX-019-D3) |
