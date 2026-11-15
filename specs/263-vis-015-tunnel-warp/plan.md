# Implementation Plan: VIS-015 Tunnel Warp

**Branch**: `feature/vis-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/263-vis-015-tunnel-warp/spec.md`

## Summary

A twelfth native visual and the third mode of VIS-013's reviewed noise field generator: a polar "tunnel" whose rings
come towards the viewer at the music's tempo. One new pure-Swift module in `VisualGenerators`, `TunnelWarp.swift`:

- `TunnelPace` (½, 1, 2 rings per beat), `TunnelTempo` (BPM + confidence, validity rule), `TunnelMapping` (CPU mirror
  of the polar mapping, ring profile, seamless two-octave seeded-noise texture and depth fog) and
  `TunnelShader.function` (the same operations in MSL);
- `TunnelDrive`: smoothed speed (τ 0.5 s) towards pace × BPM / 60 or the base 1.5 × pace, capped at 3 rings/s,
  halved by Reduce Motion; smoothed bass brightness (≤ 0.8); phase += speed · dt on the injected clock, wrapped every
  4096 rings.

`NoiseFieldConfiguration` gains `tunnelPace` (rings per beat; 0 = not a tunnel; a tunnel forces `wedges` 0).
`NoiseFieldGenerator` gains `tempo` (set by the host each frame), a `tunnelDrive`, a third entry point
`vis_tunnel_fragment` with its own lazily built pipeline, and writes the tunnel's phase and brightness into the
existing uniform slots (layout unchanged, so the plain and folded frames stay byte-identical). `NoiseFieldFlashAreas`
samples the tunnel through the CPU mirror. The app adds Visual choice "Tunnel", key `settings.tunnel.pace`, a Pace
picker, and a host closure that reads SHOW-011's tempo snapshot once per frame (as MOD-009's `lfoTempoBPM`).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal, FlashSafety. No new package dependency (the generator takes a plain `TunnelTempo`;
the app maps `TempoSnapshot` to it, so VisualGenerators does not import PerformanceControl).

**Storage**: One UserDefaults key (`settings.tunnel.pace`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and Linux shape), RenderGoldens golden
(macOS host, iOS Simulator), app unit tests and one UI test on "VIS15 iPhone 17".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: one `atan2`, a division and 4 value-noise lookups (2 octaves × angular blend) per pixel —
cheaper than the noise field's 3 × fBm; 64 CPU samples per frame; no allocation per frame; D1 frame rate `{device}`.

**Constraints**: owner rule 7 budgets; injected clocks only; type-check budget; plain/kaleidoscope digests unchanged;
no new Metal compile site (ADR-0066).

**Scale/Scope**: 1 new package source file; 4 edited package files; about 11 app files; 2-3 package test files,
1 golden test, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator receives bands, a frame context, a configuration and a plain tempo value; it knows nothing of SHOW-011, settings or projectM. |
| VII Real-time safety | Uniforms, samples and envelope storage preallocated; the tempo read is a struct copy on the main actor; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, GPU, golden and UI tests; device look and frame rate stay `{device}`. |
| SHD-011 shader policy | The tunnel text is a module constant appended to the reviewed `NoiseFieldGenerator.shaderSource` (already a PERF-009 archive key source); no new compile site, nothing from user text. |

Post-design re-check: no violation; no ADR needed.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualGenerators/
  TunnelWarp.swift                # NEW: pace, tempo, CPU mapping + texture, MSL text, drive
  NoiseFieldConfiguration.swift   # + tunnelPace, tunnel(pace:…) preset
  NoiseFieldFlashAreas.swift      # tunnel samples via the CPU mirror
  NoiseFieldGenerator.swift       # tempo, tunnelDrive, third entry point and pipeline
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
  TunnelDriveTests.swift, TunnelFlashTests.swift, TunnelRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/TunnelGoldenTests.swift (+ GeneratorGoldens/Tunnel)
Apps/projectM-iOS/... AppSettings, AppCoordinator(+LFOs), NativeSpectrumHost, SettingsView, VisualizerView,
  SceneAutosaveCapture, ShowSceneSnapshot, SnapshotBatchJob; Views/TunnelOptions.swift;
  Tests/TunnelAppTests.swift (+ CameraVisualTests, SettingsTests); UITests/TunnelUITests.swift
```

**Structure Decision**: Follow VIS-014 exactly: a mode of the existing generator, not a new one.
