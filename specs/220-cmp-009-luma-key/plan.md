# Implementation Plan: CMP-009 Luma Key

**Branch**: `feature/cmp-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/220-cmp-009-luma-key/spec.md`

## Summary

Add an optional per-layer luma key to the CMP-007/CMP-008 mask path: one plain-Swift model with a CPU
reference, one more row in the existing mask block and a keep factor in the existing coverage
multiply (no new pass or pipeline), an optional `composite.lumaKey` in scenes, and a Luma Key section
in the CMP-015 layer inspector.

In `Packages/Compositor`:

- `LayerLumaKey.swift` (target `Compositor`, plain Swift, Linux): `LayerLumaKey` (low, high,
  softness, inverted; clamped, reversed range swapped), `luma(red:green:blue:alpha:)` (Rec. 709 luma of
  the sRGB-encoded straight colour from premultiplied linear input), `keep(luma:)` and
  `keep(red:green:blue:alpha:)`: the CPU reference (research CMP-009-D1, D2).
- `LayerCompositeSettings` gains `lumaKey: LayerLumaKey?` (additive init parameter).
- `CompositorShaders.swift`: `CMPMask` gains `float4 luma` (low, high, softness, mode: 0 none, 1 key,
  2 inverted key); `cmp_luma_keep(m, c)` on the sanitised colour; `cmp_over_masked` and `cmp_blend`
  multiply it in. `MaskBlock` grows from 400 to 416 bytes (research CMP-009-D3).
- `Compositor.swift` (small): records keep `lumaKey`; the block is built when a shape, a gradient or
  a key is set and cleared when any changes at apply. Routing unchanged.

In `Packages/SceneFormat`: `SceneComposite.lumaKey: LayerLumaKey?`; decode (clamp, swap, drop unknown
keys), encode (every field, only when set), live state and capture. No unknown-kind case (the key
has no kind). Format version unchanged.

In `Packages/RenderGoldens`: `LumaKeyGoldenTests` (`GeneratorGoldens/LumaKey/<class>/`): a black key
on a black/bright/ramp picture over a coloured backdrop through the real `Compositor`.

In the app: `LayerCompositeMapping.settings` passes the key; `LayerLumaKeyEdit` (on/off defaults,
low/high push rule); five new `LayerInspectorParameter` cases (toggle, three sliders, invert) through
the existing `LayerCompositeEdit` value/text/setting functions, so history labels and coalescing keys
come from the CMP-015 machinery; `LayerLumaKeySection` view; help entries.

Docs: ADR-0028 lists `composite.lumaKey`; test report `docs/test-reports/luma-key.md`. No ADR (no
default changes).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from `CompositorShaders.swift`.

**Primary Dependencies**: Metal, SwiftUI. No new dependency.

**Storage**: the scene document (`composite.lumaKey`, optional; version 1). No UserDefaults key.

**Testing**: `Packages/Compositor`: `LayerLumaKeyReferenceTests` (CPU, Linux: luma formula, range,
softness ramp monotonic, invert, clamping and swap, premultiplied input), `LayerLumaKeyCompositeTests`
(GPU read-back: the black-key fixture, the softness ramp against the reference, invert, combined with
shape and gradient, screen blend, transformed layer, change at apply, no extra pass, unkeyed bytes
unchanged; opt-in bench). `Packages/SceneFormat`: `SceneLumaKeyTests`. `Packages/RenderGoldens`:
`LumaKeyGoldenTests` (host and iOS 27.2 simulator). App: `LayerLumaKeyEditTests` and one UI test in
`LayerInspectorUITests`.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added pass; a few ALU ops and three `pow` per keyed pixel. GPU time on the
Mac only (not device evidence); D1 is a `{device}` task.

**Constraints**: owner rule 7 budgets; no wall-clock assertions; small edits to `Compositor.swift`;
SwiftUI bodies split; typed arithmetic steps.

**Scale/Scope**: M.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal, SwiftUI; shader source in an already reviewed file | Pass |
| VI Modular boundaries | Model in `Compositor`; document in `SceneFormat`; editor in the app | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU reference + GPU read-back + goldens on the Mac and simulator; GPU time not device evidence | Pass |
| X ADR for overriding defaults | No default changes | Pass (no ADR) |
| Accessibility / flashing | A key only removes light; controls use ACC-005; flash guard unchanged | Pass |
| No networking, privacy | None added; no new stored key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/220-cmp-009-luma-key/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/luma-key.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerLumaKey.swift                    (new)
Packages/Compositor/Sources/Compositor/{LayerContract,CompositorShaders,Compositor}.swift
Packages/Compositor/Tests/CompositorTests/LayerLumaKeyReferenceTests.swift   (new)
Packages/Compositor/Tests/CompositorTests/LayerLumaKeyCompositeTests.swift   (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneLiveState}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneLumaKeyTests.swift          (new)
Packages/RenderGoldens/Tests/RenderGoldensTests/LumaKeyGoldenTests.swift     (new)
Packages/RenderGoldens/GeneratorGoldens/LumaKey/{macos,ios-simulator}/       (new goldens)
Apps/projectM-iOS/Coordinators/LayerLumaKeyEdit.swift                        (new)
Apps/projectM-iOS/Coordinators/{LayerInspectorModel,LayerInspectorCoordinator,SceneHistoryCoordinator}.swift
Apps/projectM-iOS/Views/LayerLumaKeySection.swift                            (new)
Apps/projectM-iOS/Views/{LayerDetailView,LayerInspectorControls}.swift       (one line each)
Apps/projectM-iOS/Tests/LayerLumaKeyEditTests.swift                          (new)
Apps/projectM-iOS/UITests/LayerInspectorUITests.swift                        (one test)
docs/adr/0028-scene-document-format.md, docs/test-reports/luma-key.md
```

**Structure Decision**: existing packages and app only; no new target.

## Complexity Tracking

None.
