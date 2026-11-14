# Implementation Plan: CMP-010 Color Key

**Branch**: `feature/cmp-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/230-cmp-010-color-key/spec.md`

## Summary

Add an optional per-layer colour key to the CMP-007 to CMP-009 mask path, exactly as CMP-009 added the
luma key: one plain-Swift model with a CPU reference, one more row in the existing mask block and a keep
factor in the existing coverage multiply (no new pass or pipeline), an optional `composite.colorKey` in
scenes, and a Color Key section in the CMP-015 layer inspector.

In `Packages/Compositor`:

- `LayerColorKey.swift` (target `Compositor`, plain Swift, Linux): `LayerColorKey` (key colour as
  displayed sRGB red, green, blue 0…1; tolerance 0…1; feather 0…0.5; clamped), `chroma(red:green:blue:alpha:)`
  (Rec. 709 Cb, Cr of the sRGB-encoded straight colour from premultiplied linear input), `distance`,
  `keep(distance:)` and `keep(red:green:blue:alpha:)`: the CPU reference (research CMP-010-D1, D2).
- `LayerCompositeSettings` gains `colorKey: LayerColorKey?` (additive init parameter).
- `CompositorShaders.swift`: `CMPMask` gains `float4 chroma` (key Cb, key Cr, tolerance, 1 + feather;
  w = 0 means no key); `cmp_color_keep(m, c)` on the sanitised colour; `cmp_over_masked` and `cmp_blend`
  multiply it in beside the luma keep. `MaskBlock` grows from 416 to 432 bytes (research CMP-010-D3).
- `Compositor.swift` (small): records keep `colorKey`; the block is built when any part is set and
  cleared when any changes at apply. Routing unchanged.

In `Packages/SceneFormat`: `SceneComposite.colorKey: LayerColorKey?`; decode (clamp, drop unknown keys,
defaults for missing fields), encode (every field, only when set), live state and capture. Format
version unchanged.

In `Packages/RenderGoldens`: `ColorKeyGoldenTests` (`GeneratorGoldens/ColorKey/<class>/`): a green key
on the acceptance fixture through the real `Compositor`.

In the app: `LayerCompositeMapping.settings` passes the key; `LayerColorKeyEdit` (on/off defaults,
colour from the picker, sliders); four new `LayerInspectorParameter` cases (`colorKey` toggle,
`colorKeyColor`, `colorTolerance`, `colorFeather`) through the existing `LayerCompositeEdit` and
history machinery; `LayerColorKeySection` view with a SwiftUI `ColorPicker` (accessible name "Key
Color"); help entries.

Docs: ADR-0028 lists `composite.colorKey`; test report `docs/test-reports/color-key.md`. No ADR (no
default changes).

## Technical Context

**Language/Version**: Swift 6.4.2 (Swift 6 mode), Xcode 27.2 (CI also Xcode 26); Metal Shading
Language compiled at run time from `CompositorShaders.swift`.

**Primary Dependencies**: Metal, SwiftUI (`ColorPicker`), UIKit (`UIColor` to read the picked colour in
extended sRGB). No new dependency.

**Storage**: the scene document (`composite.colorKey`, optional; version 1). No UserDefaults key.

**Testing**: `Packages/Compositor`: `LayerColorKeyReferenceTests` (CPU, Linux), `LayerColorKeyCompositeTests`
(GPU read-back: the green-key fixture, feather ramp against the reference, combined with shape, gradient
and luma key, opacity independence, screen blend, transformed layer, change at apply, no extra pass, a
key that keys nothing; opt-in bench). `Packages/SceneFormat`: `SceneColorKeyTests`.
`Packages/RenderGoldens`: `ColorKeyGoldenTests` (host and iOS 27.2 simulator). App:
`LayerColorKeyEditTests` and one UI test in `LayerInspectorUITests`.

**Target Platform**: iOS 26+ (app), macOS host and Linux for the plain-Swift parts.

**Performance Goals**: no added pass; three `pow` (shared encode) and a few ALU ops per keyed pixel.
GPU time on the Mac only (not device evidence); D1 is a `{device}` task.

**Constraints**: owner rule 7 budgets; no wall-clock assertions; small edits to `Compositor.swift`;
SwiftUI bodies split; typed arithmetic steps.

**Scale/Scope**: M.

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | Metal, SwiftUI `ColorPicker`, `UIColor.getRed` | Pass |
| VI Modular boundaries | Model in `Compositor`; document in `SceneFormat`; editor in the app | Pass |
| VII Real-time audio safety | No audio code touched | Pass |
| X Evidence | CPU reference + GPU read-back + goldens on the Mac and simulator; GPU time not device evidence | Pass |
| X ADR for overriding defaults | No default changes | Pass (no ADR) |
| Accessibility / flashing | A key only removes light; sliders ACC-005; the picker has an accessible name | Pass |
| No networking, privacy | None added; no new stored key | Pass |

Post-design re-check: unchanged, Pass.

## Project Structure

### Documentation (this feature)

```text
specs/230-cmp-010-color-key/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/color-key.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/Compositor/Sources/Compositor/LayerColorKey.swift                    (new)
Packages/Compositor/Sources/Compositor/{LayerContract,CompositorShaders,Compositor}.swift
Packages/Compositor/Tests/CompositorTests/LayerColorKeyReferenceTests.swift   (new)
Packages/Compositor/Tests/CompositorTests/LayerColorKeyCompositeTests.swift   (new)
Packages/SceneFormat/Sources/SceneFormat/{SceneDocument,SceneDecoding,SceneEncoding,SceneLiveState}.swift
Packages/SceneFormat/Tests/SceneFormatTests/SceneColorKeyTests.swift          (new)
Packages/RenderGoldens/Tests/RenderGoldensTests/ColorKeyGoldenTests.swift     (new)
Packages/RenderGoldens/GeneratorGoldens/ColorKey/{macos,ios-simulator}/       (new goldens)
Apps/projectM-iOS/Coordinators/LayerColorKeyEdit.swift                        (new)
Apps/projectM-iOS/Coordinators/{LayerInspectorModel,LayerInspectorCoordinator,SceneHistoryCoordinator}.swift
Apps/projectM-iOS/Views/LayerColorKeySection.swift                            (new)
Apps/projectM-iOS/Views/LayerDetailView.swift                                 (one line)
Apps/projectM-iOS/Tests/LayerColorKeyEditTests.swift                          (new)
Apps/projectM-iOS/UITests/LayerInspectorUITests.swift                         (one test)
docs/adr/0028-scene-document-format.md, docs/test-reports/color-key.md
```

**Structure Decision**: existing packages and app only; no new target.

## Complexity Tracking

None.
