# CMP-004 Blend Mode Library — test report

Feature: `specs/099-cmp-004-blend-mode-library` (contract `contracts/blend-modes.md`, ADR-0037).
Host: the Mac Studio (Apple M5 Max, 40-core GPU), Xcode 27.2, Swift 6.4.2, 2026-11-14.
Nothing here is device evidence.

## Baseline (CMP-004-T01, before any change)

- `swift test --package-path Packages/Compositor`: 215 tests, 0 failures.
- `swift test --package-path Packages/SceneFormat`: 86 tests, 0 failures.

## Acceptance: each mode against the reference equations (CMP-004-S1, S2)

`LayerBlendCompositeTests.testEveryModeMatchesTheReferenceOnTheGrid`: a 64 × 64 backdrop × source
grid (encoded levels 0, 0.25, 0.5, 0.75, 1 per channel, shifted per channel; alpha pairs (1, 1),
(0.5, 1), (1, 0.5), (0.5, 0.25); three broken source pixels: NaN, −1, +∞), uploaded as half floats,
composited by the Metal compositor and compared with `LayerBlend` (Double) on the same half-float
inputs. Worst error over all 4096 pixels:

| Mode | Composite (`rgba16Float`, linear), limit 1e-3 | 8-bit sRGB output vs exact encoded reference, limit 1/255 |
|---|---|---|
| normal | 2.44e-4 | 0.49/255 |
| add | 4.88e-4 | 0.50/255 |
| screen | 4.88e-4 | 0.51/255 |
| multiply | 4.88e-4 | 0.59/255 |
| overlay | 4.88e-4 | 0.59/255 |
| difference | 4.88e-4 | 0.51/255 |

The linear errors are one half-float step (2^-11) near 1: the reference is not rounded to half, the
GPU result is. The 8-bit errors are the output's rounding (≤ 0.5) plus that step. A mutated shader
(overlay's branch on Cs instead of Cb) fails this test (checked by hand, then reverted).

Hand-checked values on the GPU (`testFiftyPercentGreysGiveTheHandCheckedValues`, encoded, ±2e-3):
multiply 0.25, screen 0.75, overlay 0.5, difference 0, add 1, normal 0.5.

## Stack interactions (CMP-004-S4, R5, R6)

- A mode over transparent is bit-identical to normal (every mode).
- Opacity 0 in any mode is bit-identical to the stack without the layer; opacity 0.5 matches the
  reference within 1e-3.
- A transformed mode layer (translation 0.25) matches the reference on its placed picture within 1e-3.
- A mode change at `apply` shows the next frame; no layer created or prepared, no allocation.
- Two mode layers in a row (multiply, then screen at opacity 0.75) match the chained reference within
  2e-3 (two half roundings).
- Normal-only stacks take no second composite; a mode stack takes exactly one, once.
- A REC-001 capture equals the shown output byte for byte; a Reduce-flashing frame encodes.
- All 215 existing Compositor tests pass unchanged; RenderGoldens 39 tests pass with no golden
  re-recorded.

## Scene format (CMP-004-S5)

`SceneBlendModeTests`: the six names give no warning, reach the live stack and survive load → capture
(fixed point); "softLight" and "Screen" are kept by decode → encode and load → capture, listed by the
repair report as one "values adjusted" note, and drawn as normal; a mode set live replaces a kept
name. Format version unchanged; the QA-004 migration matrix and its meta-test pass unchanged.

## GPU time (CMP-004-S6; a measurement, not device evidence, not an assertion)

`CMP004_BENCH=1 swift test -c release -Xswiftc -DDEBUG --package-path Packages/Compositor --filter LayerBlendCompositeTests/testBenchGPUTimePerMode`
(`-DDEBUG` only because existing Compositor tests use DEBUG-only fault injection; the code is
optimized). 1920 × 1080, two solid layers, whole frame (layer clears, composite, flash guard, output
into `bgra8Unorm_srgb`), 120 frames after 10 warm-up frames, median `gpuEndTime − gpuStartTime`:

| Run | normal | add | screen | multiply | overlay | difference |
|---|---|---|---|---|---|---|
| 1 | 0.169 ms | 0.185 ms | 0.159 ms | 0.158 ms | 0.162 ms | 0.161 ms |
| 2 | 0.172 ms | 0.159 ms | 0.159 ms | 0.159 ms | 0.159 ms | 0.158 ms |
| 3 | 0.121 ms | 0.305 ms | 0.162 ms | 0.158 ms | 0.158 ms | 0.159 ms |

On this GPU the extra pass of a mode layer is below the run-to-run noise (GPU clock ramping at this
light load). The cost on D1-D3 is not measured here; a device stage would measure it.

## Repository checks and other packages

See the tasks' verification notes for the exact commands and counts (Compositor, SceneFormat,
RenderGoldens, ImportFuzz, ShowControl, SceneArchive, the Linux shape, the iOS 27.2 simulator and the
repository scripts). The app was not rebuilt: no app file changed and nothing in the app names a blend
mode (CMP-004-R9: no UI).
