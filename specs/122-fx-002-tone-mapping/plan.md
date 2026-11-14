# Implementation Plan: FX-002 Tone Mapping

**Branch**: `feature/fx-002` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Add one tone-map step to the compositor's existing output shader (`cmp_output` in
`Packages/Compositor/Sources/Compositor/CompositorShaders.swift`), which every output already uses: the
screen and external display (`Compositor.composite`), REC-003 recording (`encodeOutput`), REC-001 capture
(`encodeCapture`) and CMP-014's bus. The step (research FX-002-D1) sanitises (non-finite and negative → 0,
alpha clamped), is the identity whenever the largest channel is ≤ 1, and otherwise keeps luminance and hue
while desaturating toward white (white at luminance ≥ 1). The same Metal function (`cmp_tone_map`, one
Swift string constant spliced into both shader sources) also runs on every sample the composite flash
guard (FX-019) measures, so the limiter sees the mapped colour and its gain multiplies it (D3). The screen
pass counts non-finite composite pixels with a relaxed atomic into a small shared buffer (D4). A plain-Swift
`ToneMap` reference (Linux-testable) mirrors the shader in typed steps; tests compare the GPU with it. ADR-0047
records the output pipeline change.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time with safe math
(ADR-0009 decision 3)
**Primary Dependencies**: Metal (render pipeline, one `MTLBuffer` per compositor/bus for the counter);
FlashSafety unchanged
**Storage**: none (no UserDefaults key; no setting, research D5)
**Testing**: XCTest in `Packages/Compositor/Tests/CompositorTests`: `ToneMapReferenceTests` (CPU, Linux
shape), `ToneMapOutputTests` (GPU: output pass on special values via `OutputPassRig`, end-to-end
gradient, recording and capture match, flash-limiter order, non-finite counter, GPU timing record);
regressions: the Compositor suite, RenderGoldens, VisualGenerators, SceneFormat, ImportFuzz, app unit tests
on an own simulator
**Target Platform**: iPhone and iPad (Apple GPUs), the Mac host for tests, Linux for the reference
**Project Type**: Swift package inside the mobile app repository
**Performance Goals**: no new pass, texture or per-frame allocation; a handful of ALU ops per output pixel
**Constraints**: in-range pixels bit-identical (goldens unchanged); explicit closure types and typed steps;
`CompositeFlashGuard` edit limited to its sample read (ACC-012 edits FX-019 parameters in parallel);
`Compositor.swift` edits limited to binding the counter buffer; `makeLibrary(source:)` stays in
`CompositorShaders.swift` (SHD-011 allow-list)
**Scale/Scope**: 1 new source file (`ToneMap.swift`), 4 edited source files, 3 new test files, ADR-0047

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal render pipelines, `atomic_fetch_add_explicit`, run-time source compile already allowed | Pass |
| VI Modular boundaries | All changes inside `Packages/Compositor`; no projectM, ANGLE or app coupling | Pass |
| VII Real-time safety | GPU only; no allocation per frame; the counter read is a shared-buffer load | Pass |
| VIII Upstream fidelity | In-range pixels unchanged; projectM's own path untouched | Pass |
| X Evidence | Shader and reference unit tests on the Mac; device GPU check is a `{device}` task | Pass |
| Sensory safety (FX-019) | The limiter measures the mapped (shown) colour; flashes from over-range input still limited | Pass |
| Privacy | Nothing stored or sent | Pass |

Post-design re-check: unchanged, Pass. ADR-0047 because the output pipeline's contract changes (ADR-0013's
"composite × gain" becomes "tone map, then × gain").

## Project Structure

```text
specs/122-fx-002-tone-mapping/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/tone-map.md
└── checklists/requirements.md

Packages/Compositor/Sources/Compositor/ToneMap.swift              (new: plain-Swift reference, Linux)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift    (cmp_tone_map, cmp_output, counter)
Packages/Compositor/Sources/Compositor/CompositeFlashGuard.swift  (samples through cmp_tone_map)
Packages/Compositor/Sources/Compositor/Compositor.swift           (counter buffer bound in output passes)
Packages/Compositor/Sources/Compositor/SceneTransitionBus.swift   (same)
Packages/Compositor/Tests/CompositorTests/ToneMapReferenceTests.swift (new, CPU)
Packages/Compositor/Tests/CompositorTests/OutputPassRig.swift         (new, GPU helper)
Packages/Compositor/Tests/CompositorTests/ToneMapOutputTests.swift    (new, GPU)
docs/adr/0047-output-tone-map.md
```

**Structure Decision**: the reference sits in the `Compositor` target beside `LayerBlend` (also a CPU
reference of a shader), so it builds on Linux and the GPU tests import it directly.

## Complexity Tracking

None.
