# Implementation Plan: FX-008 Radial Blur

**Branch**: `feature/fx-008` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Radial blur" to the compositor's output chain as its own small pass, following FX-006's `ChromaticSplitPass`:
`RadialBlurPass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader function
`cmp_radial_blur`, a module constant spliced into the compositor's existing reviewed compile site and listed in
`CompositorShaderSources.archived` (research FX-008-D1, D7). Per pixel it averages 16 samples at
F + (P − F) ÷ (1 + s·k/15), k = 0…15, with the GPU's linear filter clamped to the frame (D2-D4); a pixel with zero
spread (the focus) and a non-finite pixel pass through. `RadialBlur` (new file, plain Swift, Linux-buildable) holds the
value, its ranges, the sample positions and a CPU reference of a pixel with exact bilinear weights (D5). The blur is a
new FX-020 reorderable kind `fx.radialBlur`, appended: the standard order becomes Trails, Color, Chromatic split,
Radial blur, and `Compositor.encodeOutputEffects` gains one case (Color folded before it like before the split; D6).
An inactive blur adds no pass and holds no picture, so output is bit-identical to today.

App: `RadialBlurSetting` (four UserDefaults keys), a Settings → Radial blur section (toggle, ACC-005 Strength, Focus X
and Focus Y sliders), a row on the Effect order screen, the keys in FILE-005's backup policy, the privacy allow-list and
the UI-test reset, and the value pushed to the Camera, Photo, Video and Text compositors. Scenes and presets store it as
an `fx.radialBlur` entry (`SceneEffectSettings.radialBlur`). ADR-0107.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: four UserDefaults keys (`settings.radialBlur.enabled`, `.strength`, `.focusX`, `.focusY`); scene
`effects` entry `fx.radialBlur`
**Testing**: XCTest. Compositor: `RadialBlurModelTests` (CPU: ranges, sample positions, spread linearity, bounds,
fixed tap count, reference), `RadialBlurCompositeTests` (GPU: zero identity on random content, focus stable, streak
lengths and directions on a dot pattern, reference match, pool, order). SceneFormat: chain round trip.
RenderGoldens: zero blur equals no chain; a blurred scene round-trips. App: `RadialBlurSettingTests`, `SettingsTests`,
`LibraryBackupAppTests`, `LibraryEraseAppTests`, `EffectChainSettingTests`, `RadialBlurUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass (16 filtered fetches per pixel), one pooled
picture, no per-frame allocation
**Constraints**: inactive bit-identical; small focused edits to shared files (`Compositor.swift`,
`OutputEffectOrder.swift`, `SceneEffectChain.swift`, `AppCoordinator.swift`, `SettingsView.swift`,
`EffectChainView.swift`); FX-007 adds its own kind in parallel (append, never reorder); type-check budgets; unit tests
≤ 10 s
**Scale/Scope**: ~10 edited source files, ~7 new files, ADR-0107

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
Packages/Compositor/Sources/Compositor/RadialBlur.swift            (new: value, sample positions, CPU reference)
Packages/Compositor/Sources/Compositor/RadialBlurPass.swift        (new: cmp_radial_blur, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift     (+ case radialBlur)
Packages/Compositor/Sources/Compositor/Compositor.swift            (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift     (archived sources list)
Packages/Compositor/Tests/CompositorTests/RadialBlur*Tests.swift   (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift    (fx.radialBlur entry)
Packages/RenderGoldens/...                                          (apply blur; two golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (keys)
Apps/projectM-iOS/Coordinators/RadialBlurSetting.swift             (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+RadialBlur.swift     (new)
Apps/projectM-iOS/Views/RadialBlurSection.swift                    (new)
Apps/projectM-iOS/UITests/RadialBlurUITests.swift                  (new)
```

## Complexity Tracking

None.
