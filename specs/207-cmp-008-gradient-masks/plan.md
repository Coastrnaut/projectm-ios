# Implementation Plan: CMP-008 Gradient Masks

**Branch**: `feature/cmp-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/207-cmp-008-gradient-masks/spec.md`

## Summary

Extend CMP-007's mask path with an optional gradient beside the shape: one plain-Swift model with a
CPU reference, the same mask block and coverage term in the shaders (alpha = shape coverage ×
gradient alpha), an optional `composite.gradientMask` in scenes, and a Gradient section in the
CMP-015 layer inspector.

In `Packages/Compositor`:

- `LayerGradientMask.swift` (target `Compositor`, plain Swift, Linux): `LayerGradientStop`
  (position, alpha; clamped), `LayerGradientKind` (`linear(start:end:)`, `radial(center:radius:)`),
  `LayerGradientMask` (kind + 2…8 stops sorted stably; typed refusal `LayerGradientMaskError`), the
  piecewise-linear `alpha(at t:)`, and `LayerGradientGeometry` (resolved in pixels for one picture
  size; `parameter(x:y:)` and `alpha(x:y:)` at pixel centres): the CPU reference and the source of the
  shader numbers (research CMP-008-D1, D2).
- `LayerCompositeSettings` gains `gradientMask: LayerGradientMask?` (additive init parameter).
- `CompositorShaders.swift`: `CMPMask` gains `float4 grad` (kind, stop count, 0, 0), `float4 axis`
  (linear: start, end in pixels; radial: centre, radius) and `float2 stops[8]`; `cmp_mask_coverage`
  becomes shape coverage (1 when the shape kind is 0) × `cmp_gradient_alpha` (1 when the gradient
  kind is 0). `MaskBlock` grows from 304 to 400 bytes (`setFragmentBytes`, under 4 KB) and is built
  from an optional shape geometry and an optional gradient geometry (research CMP-008-D3).
- `Compositor.swift` (small): each record keeps `gradientMask` beside `mask`; the cached block is
  built when either is set and cleared when either changes at apply; routing unchanged (a layer with
  any mask uses `cmp_over_masked` or `cmp_blend` with the block). Unmasked layers keep their bytes.

In `Packages/SceneFormat`:

- `SceneGradientMask` (`known(LayerGradientMask)` / `unknown(kind:object:)`, equality through the
  encoder) and `SceneComposite.gradientMask`; decode/encode/validation/live state/capture as
  CMP-007's mask (contracts/gradient-masks.md), reusing `unsupportedMaskShape` for unknown kinds and
  `SceneLiveState.preservedGradientMasks` for capture. Format version unchanged.

In `Packages/RenderGoldens`: `GradientMaskGoldenTests` (generator-level golden pattern,
`GeneratorGoldens/GradientMask/<class>/`): one linear and one radial gradient on a solid layer through
the real `Compositor`, captured with REC-001's capture and conversion.

In the app (`Apps/projectM-iOS`): `LayerCompositeMapping.settings` passes the gradient;
`LayerGradientEdit` (plain rules: kind defaults, angle and radius, add/remove/move stops);
`LayerGradientSection` view (picker, angle/radius slider, stop rows with ACC-005 sliders, Add/Remove);
help entries; history labels and coalescing keys per stop.

Docs: ADR-0028 lists `composite.gradientMask`; test report `docs/test-reports/gradient-masks.md`. No ADR
(no default changes: no gradient = today's drawing; the separation from `composite.mask` is a
Clarification of a new field, not an override of a default).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/gradient-masks.md](contracts/gradient-masks.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from `CompositorShaders.swift` (already reviewed by the compliance check).

**Primary Dependencies**: Metal, SwiftUI. No new dependency.

**Storage**: the scene document (`composite.gradientMask`, optional; version 1). No UserDefaults key.

**Testing**: `Packages/Compositor`: `LayerGradientReferenceTests` (CPU, Linux: stops at their
positions, clamping outside, monotonic sweeps, equal positions, sorting, refusal, linear and radial
geometry, aspect), `LayerGradientCompositeTests` (GPU read-back: dense samples along the axis are
monotonic per segment within 1/255 and match the reference; radial ray; with a shape mask; screen
blend; change at apply; unmasked bytes unchanged; opt-in GPU bench). `Packages/SceneFormat`:
`SceneGradientMaskTests`. `Packages/RenderGoldens`: `GradientMaskGoldenTests` (host and iOS 27.2
simulator). App: `LayerGradientEditTests` (unit) and one UI test in `LayerInspectorUITests`.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added pass; the shader adds at most 8 iterations per masked pixel. GPU time
measured on the Mac (CMP-008-S5), not device evidence; D1 is a `{device}` task.

**Constraints**: owner rule 7 budgets; no wall-clock assertions; small edits to `Compositor.swift`
(other agents edit it); SwiftUI bodies split into properties; typed arithmetic steps (Xcode 26 and
Linux type checker).

**Scale/Scope**: M.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal, SwiftUI; shader source in an already reviewed file | Pass |
| VI Modular boundaries | Model in `Compositor`; document in `SceneFormat`; editor in the app | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU reference + GPU read-back + goldens on the Mac and simulator; GPU time not device evidence | Pass |
| X ADR for overriding defaults | No default changes | Pass (no ADR) |
| Accessibility / flashing | Gradients only reduce light; inspector controls use ACC-005; flash guard unchanged | Pass |
| No networking, privacy | None added; no new stored key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/207-cmp-008-gradient-masks/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/gradient-masks.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerGradientMask.swift               (new)
Packages/Compositor/Sources/Compositor/LayerContract.swift                   (settings.gradientMask)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift               (CMPMask gradient, MaskBlock)
Packages/Compositor/Sources/Compositor/Compositor.swift                      (records keep gradients)
Packages/Compositor/Tests/CompositorTests/LayerGradientReferenceTests.swift  (new)
Packages/Compositor/Tests/CompositorTests/LayerGradientCompositeTests.swift  (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneValidation,SceneLiveState}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneGradientMaskTests.swift     (new)
Packages/RenderGoldens/Tests/RenderGoldensTests/GradientMaskGoldenTests.swift (new)
Packages/RenderGoldens/GeneratorGoldens/GradientMask/{macos,ios-simulator}/  (new goldens)
Apps/projectM-iOS/Coordinators/LayerGradientEdit.swift                       (new)
Apps/projectM-iOS/Coordinators/{LayerInspectorModel,LayerInspectorCoordinator,SceneHistoryCoordinator}.swift
Apps/projectM-iOS/Views/LayerGradientSection.swift                           (new)
Apps/projectM-iOS/Views/LayerDetailView.swift                                (one section line)
Apps/projectM-iOS/Tests/LayerGradientEditTests.swift                         (new)
Apps/projectM-iOS/UITests/LayerInspectorUITests.swift                        (one test)
docs/adr/0028-scene-document-format.md, docs/test-reports/gradient-masks.md
```

**Structure Decision**: existing packages and app only; no new target.

## Complexity Tracking

None.
