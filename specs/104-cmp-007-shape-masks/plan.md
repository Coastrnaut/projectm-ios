# Implementation Plan: CMP-007 Shape Masks

**Branch**: `feature/cmp-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/104-cmp-007-shape-masks/spec.md`

## Summary

One plain-Swift mask model with a CPU reference in the `Compositor` target, evaluated by the
compositor's fragment shaders as a signed distance in layer pixels, chosen per stack entry and
saved in scenes.

In `Packages/Compositor`:

- `LayerMask.swift` (target `Compositor`, plain Swift, builds on Linux): `LayerMaskShape`
  (`ellipse`, `rectangle(cornerRadius:)`, `polygon([LayerPoint])`), `LayerMaskTransform` (centre,
  scale, rotation; clamped), `LayerMask` (shape, transform, feather, inverted; typed refusal of
  unusable polygons, `LayerMaskError`), and `LayerMaskGeometry`: the mask resolved for one picture
  size in pixels, with `signedDistance(x:y:)` and `coverage(x:y:)` at pixel centres. This is the CPU
  reference (CMP-007-R5) and also the source of the shader's parameter block, so CPU and GPU use the
  same numbers. Typed `Double` steps throughout (research CMP-007-D6).
- `LayerCompositeSettings` gains `mask: LayerMask?` (nil: unmasked; additive init parameter).
- `CompositorShaders.swift` (additive): `CMPMask` (inverse placement rows, shape block, band, up to
  32 points) and `cmp_mask_coverage`; a new fragment `cmp_over_masked` (identity read or transformed
  sample, then × opacity × coverage; fixed-function "over", same pass); `cmp_blend` takes the mask at
  `buffer(1)` and multiplies the source by coverage only when a mask is set (research CMP-007-D2).
- `Compositor.swift` (small): each record keeps its mask (set at init and every apply, shown from
  the next frame) and a cached parameter block per picture size; normal masked layers draw with
  `cmp_over_masked` in the open "over" pass (no extra pass); blend-mode layers bind the block to
  `cmp_blend`; unmasked layers keep their exact pipelines and bytes. `maskedDraws` counts masked
  draws in the last frame (tests).

In `Packages/SceneFormat`:

- `SceneMask` (`known(LayerMask)` or `unknown(shape:object:)`, equality through the encoder) and
  `SceneComposite.mask: SceneMask?`; decode (closed object for known shapes, unknown keys
  `droppedField`, values clamped with `valueClamped`, unusable polygons drop the mask with
  `droppedField`; unknown shape kept verbatim), encode only when set, every field in full;
  validation warning `unsupportedMaskShape` (SCN-012 note); `liveState` maps known masks to
  `LayerCompositeSettings.mask` and keeps unknown ones in `SceneLiveState.preservedMasks`;
  `init(capturing:)` writes the live mask or the preserved one while the live mask is nil. Format
  version unchanged (QA-004 matrix unchanged).

Docs: SCN-001 contract and ADR-0028 list `composite.mask`. No ADR (no default changes: no mask =
today's drawing). No UI (spec Clarifications).

Research: [research.md](research.md); entities: [data-model.md](data-model.md); contract:
[contracts/shape-masks.md](contracts/shape-masks.md); checks: [quickstart.md](quickstart.md).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from the module's Swift constant (ADR-0009 decision 3;
`CompositorShaders.swift` is already in the compliance check's reviewed list).

**Primary Dependencies**: Metal. No new dependency.

**Storage**: the scene document (`composite.mask`, optional; version 1).

**Testing**: `Packages/Compositor`: `LayerMaskReferenceTests` (CPU, Linux: each shape's distance
and coverage, invert, feather, transform, clamping, polygon refusal, even-odd, the exact-zero rule),
`LayerMaskCompositeTests` (GPU read-back of a solid layer per shape: outside alpha exactly 0, inside
equal to the unmasked layer, edge vs reference ≤ 0.01; with a transform, with a fit photo, with the
screen blend mode; a mask change at apply; no extra pass; opt-in GPU time bench).
`Packages/SceneFormat`: `SceneMaskTests` (byte-identical round trips, load/capture, unknown shape,
clamping, unusable polygon). Regression: SceneFormat (incl. QA-004 meta-test), RenderGoldens,
ImportFuzz, ShowControl, SceneArchive, app unit tests.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added render pass for normal masked layers; the shader adds one SDF per
pixel (a polygon: one loop over at most 32 edges). GPU time measured on the Mac (CMP-007-S5), not
device evidence.

**Constraints**: owner rule 7 (unit tests ~1-2 s, suite < 1 min); no wall-clock assertions; small,
additive edits to shared Compositor files (CAM-013 and UIX-002 run in parallel); no CameraLayer
edits; typed steps for SDF arithmetic (type-checker limits on Linux and Xcode 26).

**Scale/Scope**: M. One model file, shader additions, compositor routing, scene optional field.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal and run-time shader source from an already reviewed file | Pass |
| VI Modular boundaries | Model in `Compositor`; document in `SceneFormat`; no layer source changes | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU reference + GPU read-back on the Mac; GPU time labelled not device evidence | Pass |
| X ADR for overriding defaults | No default changes (no mask = today's drawing) | Pass (no ADR) |
| Accessibility / flashing | Masks only remove light; the flash guard still runs on the finished composite | Pass |
| No networking, privacy | None added | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/104-cmp-007-shape-masks/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/shape-masks.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerMask.swift                   (new)
Packages/Compositor/Sources/Compositor/LayerContract.swift               (settings.mask)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift           (CMPMask, cmp_over_masked, cmp_blend mask)
Packages/Compositor/Sources/Compositor/Compositor.swift                  (records keep masks; routing)
Packages/Compositor/Tests/CompositorTests/LayerMaskReferenceTests.swift  (new)
Packages/Compositor/Tests/CompositorTests/LayerMaskCompositeTests.swift  (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneValidation,SceneIssue,SceneLiveState,SceneRepair}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneMaskTests.swift         (new)
docs/test-reports/shape-masks.md                                         (new)
```

**Structure Decision**: existing packages only; no new target.

## Complexity Tracking

None.
