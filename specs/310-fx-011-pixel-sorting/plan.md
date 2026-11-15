# Implementation Plan: FX-011 Pixel Sorting Approximation

**Branch**: `feature/fx-011` | **Date**: 2026-11-15 | **Spec**: [spec.md](spec.md)

## Summary

Add "Pixel sort" to the compositor's output chain as its own small pass, following FX-016 (lens distortion), FX-015
(vignette) and FX-014 (edge outline): `PixelSortPass` (new file) owns one pooled `rgba16Float` picture at composite size
and the kernel `cmp_pixel_sort`, a module constant spliced into the compositor's existing reviewed compile site and
listed in `CompositorShaderSources.archived` (research FX-011-D1). It is one **compute** dispatch per active frame: one
threadgroup of `span` threads per tile of a row (or column); each thread loads its pixel into threadgroup memory, then
runs two fixed loops of exactly `span` steps (segment bounds, then its stable rank among the qualifying pixels of its
segment) and writes its pixel at `segment start + rank` (a permutation, no new values; D2, D3). `PixelSort` (new file,
plain Swift, Linux-buildable) holds the value, ranges, the shader block, the budget plan (effective span, workload,
skip; D4) and the CPU reference. Pixel sort is a new FX-020 reorderable kind `fx.pixelSort`, inserted after Lens
distortion and before Vignette in the standard order (D5); `encodeOutputEffects` gains one case (Color folded before it
like the others). Off, a frame too small, or a frame the budget cannot admit adds no pass and holds no picture.

App: `PixelSortSetting` (four UserDefaults keys), a Settings → Pixel sort section (toggle, ACC-005 Threshold slider,
Span and Direction pickers), a row on the Effect order screen, the keys in FILE-005's backup policy, the device-test
allow-list, the UI-test reset and the backup/erase app tests, and the value pushed to the compositors. Scenes and presets
store it as an `fx.pixelSort` entry (`SceneEffectSettings.pixelSort`, a property set after `init`, read and write in
`SceneEffectChain+PixelSort.swift`). ADR-0121 (a compute pass in the output chain, the budget rule).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2); Metal Shading Language compiled at run time (ADR-0009)
**Primary Dependencies**: Metal (compute pipeline from the shared library, `TexturePool`), SceneFormat, SwiftUI
**Storage**: four UserDefaults keys (`settings.pixelSort.enabled`, `.threshold`, `.span`, `.direction`); scene `effects`
entry `fx.pixelSort` (`threshold`, `span`, `vertical`)
**Testing**: XCTest. Compositor: `PixelSortModelTests` (CPU: clamping, span rounding, plan over sizes 1 × 1 … 16384 ×
16384 and every span: workload ≤ B, largest admissible span, skip; reference sorts segments, leaves non-qualifying pixels,
permutation per tile, threshold changes the output), `PixelSortCompositeTests` (GPU = CPU reference exactly at two
thresholds and both directions, partial last tile, threshold dependence, off identical with no pass, one dispatch per
active frame, budget skip with zero dispatches via a budget override, finite output, pool and order). SceneFormat:
`PixelSortSceneEntryTests`. RenderGoldens: `PixelSortSceneGoldenTests`. App: `PixelSortSettingTests`,
`LibraryBackupAppTests`, `LibraryEraseAppTests`, `EffectChainSettingTests`, `SettingsTests`, `PixelSortUITests`
**Target Platform**: iPhone and iPad; Mac host for package tests; Linux for the model
**Project Type**: Swift packages plus the iOS app
**Performance Goals**: inactive: zero cost; active: one dispatch, workload W × H × span ≤ B = 132,710,400 steps, two
texture accesses per pixel (one read, one write), one pooled picture, no per-frame allocation
**Constraints**: inactive bit-identical; small additive edits to shared files (OUT-008, VIS-018/019 in parallel);
existing tests that list the whole standard order gain `.pixelSort`; type-check budgets; unit tests ≤ 10 s
**Scale/Scope**: ~18 edited files, ~10 new files, ADR-0121

## Constitution Check

| Principle | Status |
|-----------|--------|
| I. Public Apple APIs only | Pass: Metal compute and SwiftUI only; the kernel is a module constant at the existing reviewed compile site (SHD-011, ADR-0024) |
| II-V. Capture | Not affected |
| VI. Modular boundaries | Pass: model and pass in `Compositor`; scene entry in `SceneFormat`; app wiring in the app |
| VII. Real-time audio safety | Not affected (render thread only) |
| VIII. Upstream projectM fidelity | Pass: projectM unchanged |
| IX. Pinned dependencies | Pass: no new dependency |
| X. Evidence-based quality | Pass: GPU tests equal a CPU reference; budget model tests; device frame time left `{device}` |

Post-design re-check: unchanged (pass).

## Project Structure

```text
Packages/Compositor/Sources/Compositor/PixelSort.swift              (new: value, block, plan, CPU reference)
Packages/Compositor/Sources/Compositor/PixelSortPass.swift          (new: cmp_pixel_sort, pooled picture)
Packages/Compositor/Sources/Compositor/OutputEffectOrder.swift      (+ case pixelSort before vignette)
Packages/Compositor/Sources/Compositor/Compositor.swift             (property, compile site splice, order walk case)
Packages/Compositor/Sources/Compositor/CompositorShaders.swift      (archived sources list)
Packages/Compositor/Tests/CompositorTests/PixelSort*Tests.swift     (new)
Packages/SceneFormat/Sources/SceneFormat/SceneEffectChain(+PixelSort).swift
Packages/RenderGoldens/...                                           (apply pixelSort; golden tests)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift  (keys)
Apps/projectM-iOS/Coordinators/PixelSortSetting.swift               (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+PixelSort.swift       (new)
Apps/projectM-iOS/Views/PixelSortSection.swift                      (new)
Apps/projectM-iOS/UITests/PixelSortUITests.swift                    (new)
docs/adr/0121-pixel-sort.md                                          (new)
```

## Complexity Tracking

| Deviation | Why | Simpler alternative rejected |
|-----------|-----|------------------------------|
| A compute pipeline in the output chain (the others are fragment passes) | A sort needs the whole tile; threadgroup memory gives O(span) work per pixel and one read and write per pixel | Fragment odd-even passes: `span` passes, each re-reading the whole frame (span × the memory traffic); a fragment gather needs O(span²) per pixel |
