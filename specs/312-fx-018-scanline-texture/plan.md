# Implementation Plan: FX-018 Scanline texture

**Branch**: `feature/fx-018` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Scanlines" to the compositor's output chain as its own small pass, following FX-015's vignette (ADR-0116):
`ScanlinesPass` (new file) owns one pooled `rgba16Float` picture at composite size and the shader function
`cmp_scanlines`, a module constant spliced into the compositor's existing reviewed compile site and listed in
`CompositorShaderSources.archived` (research FX-018-D1). Per pixel it reads its own value once; when the pixel's row
(column) index c satisfies c mod p < t it multiplies the colour by one frame-wide factor f = 1 − intensity, otherwise
it returns the value read, bit for bit (D2-D4). `Scanlines` (new file, plain Swift, Linux-buildable) holds the value,
its ranges, the line rule and the CPU reference (D5). Scanlines is a new FX-020 reorderable kind `fx.scanlines`,
appended after Vignette (FX-011's Pixel sort goes before Vignette and FX-017's Film grain after Scanlines when they are
merged; D6); `encodeOutputEffects` gains one case (Color folded before it like before the other passes). Off,
intensity 0 or a frame under 2 × 2 adds no pass and holds no picture, so output is bit-identical to today.

App: `ScanlinesSetting` (five UserDefaults keys), a Settings → Scanlines section (toggle, three ACC-005 sliders and an
orientation picker), a row on the Effect order screen, the keys in FILE-005's backup policy, the privacy allow-list,
the UI-test reset and the backup/erase app tests, and the value pushed to the Camera, Photo, Video and Text
compositors. Scenes and presets store it as an `fx.scanlines` entry (`SceneEffectSettings.scanlines`, a property set
after `init`, in its own `SceneEffectChain+Scanlines.swift`). ADR-0123.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (existing pipelines, `TexturePool`), SceneFormat (FX-020 list), SwiftUI
**Storage**: five UserDefaults keys (`settings.scanlines.enabled`, `.spacing`, `.thickness`, `.intensity`,
`.vertical`); scene `effects` entry `fx.scanlines`
**Testing**: XCTest. Compositor: `ScanlinesModelTests` (CPU: ranges and clamping, thickness ≤ spacing − 1, the line
rule anchored at pixel 0, zero intensity is identity, finite output), `ScanlinesCompositeTests` (GPU: off and
intensity 0 bit-identical on random content; the shader run directly at intensity 0 bit-identical; for every spacing
2…16 at several sizes, odd, portrait, landscape and 3840 × 2160, exactly the predicted rows darkened with one factor,
others bit-identical, measured pitch = spacing; vertical columns; GPU = reference; HDR finite; pool and order).
SceneFormat: entry round trip and clamping. RenderGoldens: intensity 0 equals no chain; a scanline scene round-trips
with lines at the predicted rows. App: `ScanlinesSettingTests`, `LibraryBackupAppTests`, `LibraryEraseAppTests`,
`SettingsTests`, the order tests, `ScanlinesUITests`, `EffectChainUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one full-screen pass, one read per pixel, one pooled picture, no
per-frame allocation
**Constraints**: inactive bit-identical; small appended edits to shared files (FX-011 and FX-017 edit the same files in
parallel: append, never reorder; names prefixed "scanlines"); type-check budgets; unit tests ≤ 10 s; never assert raw
`MTLTexture.allocatedSize` (the simulator and CI's virtual GPUs misreport it)
**Scale/Scope**: ~15 edited source files, ~11 new files, ADR-0123

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal only; shader is a module constant at the existing reviewed compile site (SHD-011, ADR-0024) |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU acceptance tests, CPU reference, goldens; device frame rate and look left `{device}` |

Post-design re-check: unchanged (pass). The motion policy (`check_motion_policy.py`) is not touched: the pattern is
static, with no time input.

## Project Structure

```text
Packages/Compositor/Sources/Compositor/Scanlines.swift              (new: value, line rule, CPU reference)
Packages/Compositor/Sources/Compositor/ScanlinesPass.swift          (new: cmp_scanlines, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift      (+ case scanlines, appended)
Packages/Compositor/Sources/Compositor/Compositor.swift             (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift      (archived sources list)
Packages/Compositor/Tests/CompositorTests/Scanlines*Tests.swift     (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+Scanlines).swift (fx.scanlines entry)
Packages/RenderGoldens/...                                           (apply scanlines; golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  (keys)
Apps/projectM-iOS/Coordinators/ScanlinesSetting.swift               (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+Scanlines.swift       (new)
Apps/projectM-iOS/Views/ScanlinesSection.swift                      (new)
Apps/projectM-iOS/UITests/ScanlinesUITests.swift                    (new)
docs/adr/0123-scanline-texture.md                                   (new)
```

## Complexity Tracking

None.
