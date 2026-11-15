# Implementation Plan: FX-016 Lens Distortion

**Branch**: `feature/fx-016` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Lens distortion" to the compositor's output chain as its own small pass, following FX-014 (edge outline) and
FX-012 (mosaic): `LensDistortionPass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader
function `cmp_lens_distortion`, a module constant spliced into the compositor's existing reviewed compile site and
listed in `CompositorShaderSources.archived` (research FX-016-D1). Per output pixel it takes the offset d from the frame
middle, r² = |d|² ÷ (half diagonal)², the factor f = (1 + k r²) ÷ z, and samples the input at middle + d × f by a
bilinear interpolation whose four taps are clamped to the frame, with an exact read when the sample is on a pixel centre
and transparent black when it lies outside the picture (D2-D5). `LensDistortion` (new file, plain Swift,
Linux-buildable) holds the value, ranges, the shader block and the CPU reference of the mapping, the taps and the output
(D6). Lens distortion is a new FX-020 reorderable kind `fx.lensDistortion`, appended after Edge outline;
`encodeOutputEffects` gains one case (Color folded before it like before the outline). Off, strength 0, or a frame under
2 × 2 adds no pass and holds no picture, so output is bit-identical to today.

App: `LensDistortionSetting` (three UserDefaults keys), a Settings → Lens distortion section (toggle, ACC-005 Strength
slider, Zoom to fill toggle), a row on the Effect order screen, the keys in FILE-005's backup policy, the privacy
allow-list, the UI-test reset and the backup/erase app tests, and the value pushed to the Camera, Photo, Video and Text
compositors. Scenes and presets store it as an `fx.lensDistortion` entry (`SceneEffectSettings.lensDistortion`, a
property set after `init` like FX-015's vignette, read and write in a new `SceneEffectChain+LensDistortion.swift`).
ADR-0117.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat, SwiftUI
**Storage**: three UserDefaults keys (`settings.lensDistortion.enabled`, `.strength`, `.zoomToFill`); scene `effects`
entry `fx.lensDistortion` (`strength`, `zoomToFill`)
**Testing**: XCTest. Compositor: `LensDistortionModelTests` (CPU: ranges and clamping, k bound, zero strength maps every
pixel centre to itself, dense-grid safety at ±1 with zoom on and off at aspect ratios 1:1, 16:9, 9:16, 1:64, 64:1 and
2 × 2, strictly increasing radial mapping, finite output), `LensDistortionCompositeTests` (GPU: off and strength 0
bit-identical with no pass; the pass run directly at strength 0 bit-identical; ±1 GPU = reference and finite; middle
pixel exact; corners transparent black with zoom off; pool and order). SceneFormat: `LensDistortionSceneEntryTests`.
RenderGoldens: `LensDistortionSceneGoldenTests` (zero/off equals no chain; a lens scene round-trips). App:
`LensDistortionSettingTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, `EffectChainSettingTests`,
`LensDistortionUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, at most 4 reads per pixel, one pooled picture,
no per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files; FX-015 (vignette) and VIS-017 merge in
parallel; existing tests that list the whole standard order gain `.lensDistortion`, new assertions are position-based;
type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~15 edited source files, ~10 new files, ADR-0117

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal and SwiftUI only; shader is a module constant at the existing reviewed compile site (SHD-011, ADR-0024); no user-authored shader |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests against a CPU reference, goldens; device frame rate left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/LensDistortion.swift            (new: value, block, CPU reference)
Packages/Compositor/Sources/Compositor/LensDistortionPass.swift        (new: cmp_lens_distortion, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift         (+ case lensDistortion)
Packages/Compositor/Sources/Compositor/Compositor.swift                (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift         (archived sources list)
Packages/Compositor/Tests/CompositorTests/LensDistortion*Tests.swift   (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+LensDistortion).swift
Packages/RenderGoldens/...                                              (apply lensDistortion; golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift     (keys)
Apps/projectM-iOS/Coordinators/LensDistortionSetting.swift             (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+LensDistortion.swift     (new)
Apps/projectM-iOS/Views/LensDistortionSection.swift                    (new)
Apps/projectM-iOS/UITests/LensDistortionUITests.swift                  (new)
```

## Complexity Tracking

None.
