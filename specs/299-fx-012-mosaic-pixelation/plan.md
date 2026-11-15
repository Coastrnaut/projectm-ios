# Implementation Plan: FX-012 Mosaic Pixelation

**Branch**: `feature/fx-012` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Mosaic" to the compositor's output chain as its own small pass, following FX-006 to FX-008: `MosaicPass` (new
file) owns one pooled `rgba16Float` picture at composite size and the shader function `cmp_mosaic`, a module constant
spliced into the compositor's existing reviewed compile site and listed in `CompositorShaderSources.archived` (research
FX-012-D1). Per pixel it finds its cell (square block anchored at the top-left, or pointy-top hexagon with a cell
centred on the top-left corner) and copies the cell's centre pixel with one exact `read`, clamped to the frame
(D2-D4). `Mosaic` (new file, plain Swift, Linux-buildable) holds the value, its ranges, the cell assignment and the CPU
reference (D5). Mosaic is a new FX-020 reorderable kind `fx.mosaic`, appended after Radial blur; `encodeOutputEffects`
gains one case (Color folded before it like before the blurs). Block size 1, off, or a frame under 2 × 2 adds no pass
and holds no picture, so output is bit-identical to today.

App: `MosaicSetting` (three UserDefaults keys), a Settings → Mosaic section (toggle, ACC-005 Block size slider,
Square/Hexagon picker), a row on the Effect order screen, the keys in FILE-005's backup policy, the privacy allow-list,
the UI-test reset and the backup/erase app tests, and the value pushed to the Camera, Photo, Video and Text
compositors. Scenes and presets store it as an `fx.mosaic` entry (`SceneEffectSettings.mosaic`). ADR-0110.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: three UserDefaults keys (`settings.mosaic.enabled`, `.size`, `.shape`); scene `effects` entry `fx.mosaic`
**Testing**: XCTest. Compositor: `MosaicModelTests` (CPU: ranges, square and hex cell assignment, centres inside the
frame, reference), `MosaicCompositeTests` (GPU: off and size 1 bit-identical on random content, 8 × 8 squares uniform
and adjacent blocks different, hexagon cells uniform away from borders, GPU = reference, pool, order). SceneFormat:
chain round trip. RenderGoldens: size 1 equals no chain; a mosaic scene round-trips. App: `MosaicSettingTests`,
`SettingsTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, `EffectChainSettingTests`, `MosaicUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, one read per pixel, one pooled picture, no
per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files; FX-010 adds its own kind in parallel
(append, never reorder; names prefixed "mosaic"); type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~12 edited source files, ~8 new files, ADR-0110

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
Packages/Compositor/Sources/Compositor/Mosaic.swift                (new: value, cell assignment, CPU reference)
Packages/Compositor/Sources/Compositor/MosaicPass.swift            (new: cmp_mosaic, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift     (+ case mosaic)
Packages/Compositor/Sources/Compositor/Compositor.swift            (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift     (archived sources list)
Packages/Compositor/Tests/CompositorTests/Mosaic*Tests.swift       (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain.swift    (fx.mosaic entry)
Packages/RenderGoldens/...                                          (apply mosaic; two golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (keys)
Apps/projectM-iOS/Coordinators/MosaicSetting.swift                 (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+Mosaic.swift         (new)
Apps/projectM-iOS/Views/MosaicSection.swift                        (new)
Apps/projectM-iOS/UITests/MosaicUITests.swift                      (new)
```

## Complexity Tracking

None.
