# Implementation Plan: FX-015 Vignette

**Branch**: `feature/fx-015` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Vignette" to the compositor's output chain as its own small pass, following FX-012's mosaic (ADR-0110):
`VignettePass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader function
`cmp_vignette`, a module constant spliced into the compositor's existing reviewed compile site and listed in
`CompositorShaderSources.archived` (research FX-015-D1). Per pixel it reads its own value once and multiplies the
colour by 1 − intensity × w, w the smoothstep weight of the aspect-following elliptical distance from the centre
(D2-D4); alpha is kept. `Vignette` (new file, plain Swift, Linux-buildable) holds the value, its ranges, the weight and
the CPU reference (D5). Vignette is a new FX-020 reorderable kind `fx.vignette`, appended last (after Mosaic; FX-014's
Edge outline is appended in parallel and the merge keeps both); `encodeOutputEffects` gains one case (Color folded
before it like before the other passes). Off, intensity 0 or a frame under 2 × 2 adds no pass and holds no picture, so
output is bit-identical to today.

App: `VignetteSetting` (five UserDefaults keys), a Settings → Vignette section (toggle and four ACC-005 sliders), a row
on the Effect order screen, the keys in FILE-005's backup policy, the privacy allow-list, the UI-test reset and the
backup/erase app tests, and the value pushed to the Camera, Photo, Video and Text compositors. Scenes and presets store
it as an `fx.vignette` entry (`SceneEffectSettings.vignette`, in its own `SceneEffectChain+Vignette.swift`). ADR-0116.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: five UserDefaults keys (`settings.vignette.enabled`, `.intensity`, `.softness`, `.centerX`, `.centerY`);
scene `effects` entry `fx.vignette`
**Testing**: XCTest. Compositor: `VignetteModelTests` (CPU: ranges and clamping, zero intensity is identity, the clear
core, monotonic falloff, centre control, finite output), `VignetteCompositeTests` (GPU: off and intensity 0
bit-identical on random content at centre, corners and everywhere; centre pixel exact at any intensity; monotonic on a
uniform picture; centre moves the bright spot; GPU ≈ reference; HDR finite; pool and order). SceneFormat: entry round
trip and clamping. RenderGoldens: intensity 0 equals no chain; a vignette scene round-trips and keeps the centre. App:
`VignetteSettingTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`, the order tests, `VignetteUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, one read per pixel, one pooled picture, no
per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files (FX-014 and VIS-017 edit the same files
in parallel: append, never reorder; names prefixed "vignette"); type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~14 edited source files, ~10 new files, ADR-0116

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
Packages/Compositor/Sources/Compositor/Vignette.swift              (new: value, weight, CPU reference)
Packages/Compositor/Sources/Compositor/VignettePass.swift          (new: cmp_vignette, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift     (+ case vignette, appended)
Packages/Compositor/Sources/Compositor/Compositor.swift            (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift     (archived sources list)
Packages/Compositor/Tests/CompositorTests/Vignette*Tests.swift     (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+Vignette).swift (fx.vignette entry)
Packages/RenderGoldens/...                                          (apply vignette; golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift (keys)
Apps/projectM-iOS/Coordinators/VignetteSetting.swift               (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+Vignette.swift       (new)
Apps/projectM-iOS/Views/VignetteSection.swift                      (new)
Apps/projectM-iOS/UITests/VignetteUITests.swift                    (new)
docs/adr/0116-vignette.md                                          (new)
```

## Complexity Tracking

None.
