# Implementation Plan: VIS-010 Particle Trails

**Branch**: `feature/vis-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/272-vis-010-particle-trails/spec.md`

## Summary

Decaying streaks behind the VIS-008 fountain's and VIS-009 orbit's particles from a fixed-size feedback pair. New
package files in `VisualGenerators`:

- `ParticleTrails.swift` (pure Swift, every platform): `ParticleTrailLength` (off/short/long), the half-life and
  per-frame decay (`0.5^(Δt/h)`, ≤ 0.99; Reduce Motion halves h, Reduce flashing caps it at 0.25 s), the 0.8 cap and
  1/512 cut, the CPU reference of one pixel (`ParticleTrails.accumulate`), the 17-area trail light bound
  (`ParticleTrailFlashBound`) and a small CPU accumulation model (`ParticleTrailModel`, fixed storage) used by the
  10-minute fixture and the frame-rate and cap tests.
- `ParticleTrailPass.swift` (Metal): two private `rgba16Float` 512 × 512 textures made once, three pipelines built from
  the `FlatShapePass` library (decay, particles with max blending, present), the reset rule, and `encode`: decay +
  particles into the next texture, then the target pass (background, decayed previous trail × gain, crisp particles).
- `ParticleTrailShader` (MSL text) appended to `FlatShapePass.shaderSource`.

Small hooks: `FlatShapePass` keeps its `library`, exposes a slot's buffer and takes an optional underlay closure
(drawn after the clear, before the particles); `ParticleFountainGenerator` and `ParticleOrbitGenerator` gain
`trails` and a branch in `encode` that hands the frame to the trail pass when trails are active. Emitter and
configuration types are not touched (SHD-007 runs in parallel).

App: `settings.particleTrails` (`ParticleTrailSetting`), a "Trails" picker in both particle visuals' options,
`NativeSpectrumHost.particleTrails` applied like `reduceMotion`, accessibility value suffix, key lists
(run_device_tests, LibrarySettingsPolicy, UI-test reset via `AppSettings.allKeys`, SettingsTests).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety; no new dependency.

**Storage**: One UserDefaults key `settings.particleTrails` (allow-listed, backed up, erased with Settings).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host; Linux shape with
`-Xswiftc -DVISUAL_NO_METAL` build), RenderGoldens golden (macOS host, iOS Simulator), app unit tests and one UI test on
"VIS10 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the CPU parts.

**Performance Goals**: trails on: two extra full-screen passes over 512² and one full-screen textured triangle on the
target; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets (the 10-minute fixture runs in seconds on an injected clock); type-check budget;
existing fountain and orbit goldens unchanged; no new Metal compile site; no emitter changes.

**Scale/Scope**: 2 new package source files, 3 edited package files (small); about 6 app files; 3 package test files, 1
golden test, 1 app test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The trail pass lives in `VisualGenerators`; the generators get a value setting; nothing of the app or projectM. |
| VII Real-time safety | Textures created once, uniforms by `setFragmentBytes` from stack values, bound storage preallocated; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | Trail MSL is a module constant appended to the reviewed `FlatShapePass.shaderSource` (already a PERF-009 archive key source); no new compile site. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  ParticleTrails.swift            # NEW: length, decay, cap, CPU reference, flash bound, CPU model
  ParticleTrailPass.swift         # NEW: fixed texture pair, pipelines, encode; ParticleTrailShader text
  FlatShapePass.swift             # keeps library, buffer(slot), underlay hook, source + trail functions
  ParticleFountainGenerator.swift # + trails, trail branch in encode
  ParticleOrbitGenerator.swift    # + trails, trail branch in encode
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  ParticleTrailModelTests.swift, ParticleTrailRenderTests.swift, ParticleTrailFlashTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/ParticleTrailGoldenTests.swift (+ GeneratorGoldens/ParticleTrails)
Apps/projectM-iOS/ AppSettings, AppCoordinator, NativeSpectrumHost, SettingsView, VisualizerView;
  Tests/ParticleTrailAppTests.swift (+ SettingsTests); UITests/ParticleTrailUITests.swift
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift (key lists)
```

**Structure Decision**: one shared trail pass used by both particle generators through a small branch, so the
generators' files change by a few lines.
