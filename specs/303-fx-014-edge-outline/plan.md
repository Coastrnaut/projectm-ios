# Implementation Plan: FX-014 Edge Outline

**Branch**: `feature/fx-014` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Edge outline" to the compositor's output chain as its own small pass, following FX-012 (mosaic, the newest
instance of the FX-006 pattern): `EdgeOutlinePass` (new file) owns one pooled `rgba16Float` picture at composite size
and the shader function `cmp_edge_outline`, a module constant spliced into the compositor's existing reviewed compile
site and listed in `CompositorShaderSources.archived` (research FX-014-D1). Per pixel it reads the 3 × 3 neighbourhood
at offsets of ±width (clamped to the frame), takes Rec. 709 linear luminance, computes the Sobel strength and the
smoothstep mask, and either keeps the input pixel exactly (mask 0, overlay) or mixes toward the outline colour
(D2-D5). `EdgeOutline` (new file, plain Swift, Linux-buildable) holds the value, ranges, the sRGB → linear colour, the
ACC-012 limit and the CPU reference of strength, mask and output (D6). Edge outline is a new FX-020 reorderable kind
`fx.edgeOutline`, appended after Mosaic; `encodeOutputEffects` gains one case (Color folded before it like before the
mosaic). Off, or a frame under 2 × 2, adds no pass and holds no picture, so output is bit-identical to today.

App: `EdgeOutlineSetting` (five UserDefaults keys), a Settings → Edge outline section (toggle, ACC-005 Threshold
slider, Width and Mode pickers, ColorPicker), a row on the Effect order screen, the keys in FILE-005's backup policy,
the privacy allow-list, the UI-test reset and the backup/erase app tests, and the effective value (ACC-012 colour cap)
pushed to the Camera, Photo, Video and Text compositors, re-applied when the safety clamp changes. Scenes and presets
store it as an `fx.edgeOutline` entry (`SceneEffectSettings.edgeOutline`, read and write in a new
`SceneEffectChain+EdgeOutline.swift`). ADR-0114.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), FlashSafety (`SafetyClamp`), SceneFormat, SwiftUI
**Storage**: five UserDefaults keys (`settings.edgeOutline.enabled`, `.threshold`, `.width`, `.color`, `.mode`); scene
`effects` entry `fx.edgeOutline` (`threshold`, `width`, `red`, `green`, `blue`, `mode`)
**Testing**: XCTest. Compositor: `EdgeOutlineModelTests` (CPU: ranges, sRGB → linear, Sobel on flat and step pictures,
mask threshold, border clamping, ACC-012 limit), `EdgeOutlineCompositeTests` (GPU: flat pictures bit-identical in
overlay and black in outline-only, 8-pixel checkerboard mask = reference, threshold above contrast draws nothing, off
bit-identical, pool, order). SceneFormat: `EdgeOutlineSceneEntryTests`. RenderGoldens: a disabled entry equals no
chain; an outline scene round-trips. App: `EdgeOutlineSettingTests`, `SettingsTests`, `LibraryBackupAppTests`,
`LibraryEraseAppTests`, `EffectChainSettingTests`, `EdgeOutlineUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, 9 reads per pixel, one pooled picture, no
per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files; FX-013 changes the grade in parallel;
existing tests that list the whole standard order gain `.edgeOutline`, new assertions are position-based; type-check
budgets; unit tests ≤ 10 s
**Scale/Scope**: ~15 edited source files, ~10 new files, ADR-0114

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal and SwiftUI `ColorPicker` only; shader is a module constant at the existing reviewed compile site (SHD-011, ADR-0024); no user-authored shader |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests against a CPU reference, goldens; device frame rate left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/EdgeOutline.swift            (new: value, colour, CPU reference)
Packages/Compositor/Sources/Compositor/EdgeOutlinePass.swift        (new: cmp_edge_outline, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift      (+ case edgeOutline)
Packages/Compositor/Sources/Compositor/Compositor.swift             (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift      (archived sources list)
Packages/Compositor/Tests/CompositorTests/EdgeOutline*Tests.swift   (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+EdgeOutline).swift
Packages/RenderGoldens/...                                           (apply edgeOutline; golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  (keys)
Apps/projectM-iOS/Coordinators/EdgeOutlineSetting.swift             (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+EdgeOutline.swift     (new)
Apps/projectM-iOS/Views/EdgeOutlineSection.swift                    (new)
Apps/projectM-iOS/UITests/EdgeOutlineUITests.swift                  (new)
```

## Complexity Tracking

None.
