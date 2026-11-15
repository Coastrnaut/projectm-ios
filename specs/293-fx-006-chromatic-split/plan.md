# Implementation Plan: FX-006 Chromatic Split

**Branch**: `feature/fx-006` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Chromatic split" to the compositor's output chain as its own small pass, following FX-020's `OutputGradePass`
pattern: `ChromaticSplitPass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader
function `cmp_chromatic`, a module constant spliced into the compositor's existing reviewed compile site and listed
in `CompositorShaderSources.archived` (research FX-006-D1, D7). Per pixel it keeps green and alpha's own sample,
reads red at p − v and blue at p + v (bilinear, by hand from `read`, clamped to the frame), with v the split vector
faded to zero towards the border (D2-D4). `ChromaticSplit` (new file, plain Swift, Linux-buildable) holds the value,
its ranges, the vector maths and a CPU reference of a pixel (D5). The split is a new FX-020 reorderable kind
`fx.chromatic`; the standard order becomes Trails, Color, Chromatic split, and `Compositor.encodeFrame` walks the
order: Color is folded into a pass only when an active spatial effect (Trails or the split) follows it (D6). Inactive
split adds no pass and holds no picture, so output is bit-identical to today.

App: `ChromaticSplitSetting` (four UserDefaults keys), a Settings → Chromatic split section (toggle, ACC-005 Amount
and Angle sliders, Radial switch), a row on the Effect order screen, the keys in FILE-005's backup policy, the
privacy allow-list and the UI-test reset, and the value pushed to the Camera, Photo, Video and Text compositors.
Scenes and presets store it as an `fx.chromatic` entry (`SceneEffectSettings.chromatic`). ADR-0104.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: four UserDefaults keys (`settings.chromatic.enabled`, `.amount`, `.angle`, `.radial`); scene `effects`
entry `fx.chromatic`
**Testing**: XCTest. Compositor: `ChromaticSplitModelTests` (CPU: vector, fade, clamp, reference, ranges),
`ChromaticSplitCompositeTests` (GPU: zero identity on random content, bounds with unique border colours, shift on a
line pattern, reference match, pool, order). SceneFormat: chain round trip. RenderGoldens: one new golden scene
plus all existing unchanged. App: `ChromaticSplitSettingTests`, `SettingsTests`, `LibraryBackupAppTests`,
`EffectChainSettingTests`, `ChromaticSplitUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass (7 reads per pixel), one pooled picture,
no per-frame allocation
**Constraints**: inactive bit-identical; small focused edits to shared files (`Compositor.swift`,
`OutputEffectOrder.swift`, `SceneEffectChain.swift`, `AppCoordinator.swift`, `SettingsView.swift`,
`EffectChainView.swift`); FX-005 edits the grade in parallel; type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~8 edited source files, ~6 new files, ADR-0104

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal only; shader is a module constant at the existing reviewed compile site (SHD-011, ADR-0024) |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests, CPU reference, goldens; device frame rate left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/ChromaticSplit.swift        (new: value, maths, CPU reference)
Packages/Compositor/Sources/Compositor/ChromaticSplitPass.swift    (new: cmp_chromatic, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift     (+ case chromatic)
Packages/Compositor/Sources/Compositor/Compositor.swift            (property, compile site splice, order walk)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift     (archived sources list)
Packages/Compositor/Tests/CompositorTests/ChromaticSplit*Tests.swift (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift    (fx.chromatic entry)
Packages/RenderGoldens/...                                          (apply split; one golden)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (keys)
Apps/projectM-iOS/Coordinators/ChromaticSplitSetting.swift         (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+ChromaticSplit.swift (new)
Apps/projectM-iOS/Views/ChromaticSplitSection.swift                (new)
Apps/projectM-iOS/UITests/ChromaticSplitUITests.swift              (new)
```

## Complexity Tracking

None.
