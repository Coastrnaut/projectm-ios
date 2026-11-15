# Implementation Plan: VIS-020 Spectrum Waterfall

**Branch**: `feature/vis-020` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/267-vis-020-spectrum-waterfall/spec.md`

## Summary

A thirteenth native visual and the fourth mode of VIS-013's reviewed noise field generator: a spectrogram that
scrolls the last 60 s of the smoothed ANL-002 bands down the screen through a fixed ring. One new pure-Swift file in
`VisualGenerators`, `SpectrumWaterfall.swift`:

- `SpectrumWaterfallHistory`: the CPU ring (512 rows × 256 columns of `UInt8`, per-row sequence numbers), the row
  clock (117.1875 ms per row on the injected clock, 234.375 ms with Reduce Motion), the current row's running sum,
  log-band → column interpolation, and the list of rows written since the last drain. All storage allocated in `init`.
- `WaterfallFlashCells`: per ring row, the summed linear colour of its 8 column groups (palette at v × v), and the
  64 cell means of the shown picture (8 × 8; 64 rows × 32 columns each).
- `WaterfallShader.function`: the MSL that reads the history texture with the ring offset.

`NoiseFieldConfiguration` gains `waterfall` (on forces wedges 0 and tunnel pace 0). `NoiseFieldGenerator` gains a
history, a private `r8Unorm` texture (256 × 512) and a shared staging buffer of the same size, all made in `init`;
in waterfall mode each frame advances the history, copies the new rows staging → texture with a blit in the frame's
command buffer, then draws `vis_waterfall_fragment` (its own lazily built pipeline) with the texture at index 0 and
the newest row index in the `phase` slot (uniform layout unchanged). `NoiseFieldFlashAreas` takes the 64 cell
colours. The app adds Visual choice "Spectrum Waterfall" (Bars applies), the host style `.waterfall` and the
switch arms in scene capture, snapshots and batch jobs; no new setting key.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety; no new dependency.

**Storage**: None new (no UserDefaults key).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and Linux shape), RenderGoldens golden
(macOS host, iOS Simulator), app unit tests and one UI test on "VIS20 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Performance Goals**: per pixel two texture reads and a palette mix; per frame 256 additions plus, per new row
(≈ 8.5/s), 256 colour evaluations and a 256-byte copy; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets; injected clocks only; type-check budget; other modes' digests and goldens
unchanged; no new Metal compile site (ADR-0066); fixed storage.

**Scale/Scope**: 1 new package source file; 4 edited package files; about 9 app files; 3 package test files, 1 golden
test, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator receives bands, a frame context and a configuration; nothing of settings or projectM. |
| VII Real-time safety | History, staging buffer, texture, cell sums and uniforms preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | The waterfall text is a module constant appended to the reviewed `NoiseFieldGenerator.shaderSource` (already a PERF-009 archive key source); no new compile site, nothing from user text. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  SpectrumWaterfall.swift         # NEW: history ring, flash cells, MSL text
  NoiseFieldConfiguration.swift   # + waterfall, waterfall(…) preset
  NoiseFieldFlashAreas.swift      # waterfall cell colours
  NoiseFieldGenerator.swift       # history texture, staging buffer, blit, fourth entry point
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  WaterfallHistoryTests.swift, WaterfallFlashTests.swift, WaterfallRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/WaterfallGoldenTests.swift (+ GeneratorGoldens/Waterfall)
Apps/projectM-iOS/... AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, SceneAutosaveCapture,
  ShowSceneSnapshot, SnapshotBatchJob; Tests/WaterfallAppTests.swift (+ CameraVisualTests, SettingsTests);
  UITests/WaterfallUITests.swift
```

**Structure Decision**: Follow VIS-014/015: a mode of the existing generator, not a new one.
