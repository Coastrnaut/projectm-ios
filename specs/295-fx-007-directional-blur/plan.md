# Implementation Plan: FX-007 Directional Blur

**Branch**: `feature/fx-007` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Directional blur" to the compositor's output chain as its own small pass, following FX-006's
`ChromaticSplitPass` (which follows FX-020's `OutputGradePass`): `DirectionalBlurPass` (new file) owns one pooled
`rgba16Float` picture at composite size and the shader function `cmp_directional_blur`, a module constant spliced
into the compositor's existing reviewed compile site and listed in `CompositorShaderSources.archived` (research
FX-007-D1). Per pixel it reads exactly 16 linearly filtered samples along the axis, evenly spaced from −radius to
+radius, positions clamped to the frame, with fixed Gaussian weights that sum to 1 (D2-D4). `DirectionalBlur` (new
file, plain Swift, Linux-buildable) holds the value, its ranges, the kernel (offsets and weights) and a CPU reference
of a pixel (D5). The blur is a new FX-020 reorderable kind `fx.directionalBlur`, appended after FX-006's
`fx.chromatic`; the `encodeOutputEffects` walk gains one case like the split's (D6). Inactive blur adds no pass and
holds no picture, so the output is bit-identical to today.

App: `DirectionalBlurSetting` (three UserDefaults keys), a Settings → Directional blur section (toggle, ACC-005
Radius and Angle sliders), a row on the Effect order screen, the keys in FILE-005's backup policy, the privacy
allow-list and the UI-test reset, and the value pushed to the Camera, Photo, Video and Text compositors. Scenes and
presets store it as an `fx.directionalBlur` entry (`SceneEffectSettings.directionalBlur`). ADR-0106.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: three UserDefaults keys (`settings.directionalBlur.enabled`, `.radius`, `.angle`); scene `effects` entry
`fx.directionalBlur`
**Testing**: XCTest. Compositor: `DirectionalBlurModelTests` (CPU: kernel taps, weights, offsets, clamp, reference,
ranges), `DirectionalBlurCompositeTests` (GPU: zero identity on random content, horizontal and vertical spread with
energy kept, bounds at the maximum, reference match, pool, tap constant). SceneFormat: chain round trip.
RenderGoldens: zero blur exact, save/reload. App: `DirectionalBlurSettingTests`, `LibraryBackupAppTests`,
`LibraryEraseAppTests`, `EffectChainSettingTests`, `DirectionalBlurUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, 16 filtered samples per pixel at every
radius, one pooled picture, no per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files (`Compositor.swift`,
`OutputEffectOrder.swift`, `SceneEffectChain.swift`, `AppCoordinator.swift`, `SettingsView.swift`,
`EffectChainView.swift`) so a textual merge beside FX-006's cases is easy; type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~10 edited source files, ~8 new files, ADR-0106

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
Packages/Compositor/Sources/Compositor/DirectionalBlur.swift        (new: value, kernel, CPU reference)
Packages/Compositor/Sources/Compositor/DirectionalBlurPass.swift    (new: cmp_directional_blur, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift      (+ case directionalBlur, appended)
Packages/Compositor/Sources/Compositor/Compositor.swift             (property, compile site splice, walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift      (archived sources list)
Packages/Compositor/Tests/CompositorTests/DirectionalBlur*Tests.swift (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift     (fx.directionalBlur entry)
Packages/RenderGoldens/...                                           (apply blur; two tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  (keys)
Apps/projectM-iOS/Coordinators/DirectionalBlurSetting.swift         (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+DirectionalBlur.swift (new)
Apps/projectM-iOS/Views/DirectionalBlurSection.swift                (new)
Apps/projectM-iOS/UITests/DirectionalBlurUITests.swift              (new)
docs/adr/0106-directional-blur.md                                    (new)
```

## Complexity Tracking

None.
