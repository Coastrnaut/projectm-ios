# Implementation Plan: VIS-005 Radial Waveform

**Branch**: `feature/vis-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/176-vis-005-radial-waveform/spec.md`

## Summary

A fifth native visual beside VIS-001 to VIS-004: the newest 1,024 mono samples wrapped around a ring,
radius r = R₀ + A·s, drawn as a closed, palette-colored polyline through the shared `FlatShapePass`,
scaled by VIS-004's deterministic auto-gain. The seam is removed by a raised-cosine crossfade of the
last 256 points into the samples before the window. Samples come from VIS-003's `WaveformTap` mono
history (unchanged). The app adds a Visual choice "Radial Waveform" with two setting keys (Ring,
Amplitude). Proof: CPU seam and sign tests, a flash-envelope test, two GPU goldens (sine ring,
silence), a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (`FlatShapePass`), FlashSafety (envelope). No new dependency.

**Storage**: Two UserDefaults keys (`settings.radialWaveform.ring`, `settings.radialWaveform.amplitude`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and the Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` goldens
(macOS host, iOS Simulator), app unit tests and one UI test on the agent's own simulator "VIS5".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: Per frame 1,024 segments (6,144 vertices) and as many flash regions; no
allocation per frame; no change to the tap.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions (frame durations injected);
type-check budget (300 ms per function, 200 ms per expression).

**Scale/Scope**: 3 new package source files, edits to about 8 app files, 4 package test files, a golden
test with 4 images per platform class, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of capture, settings or projectM; samples arrive through the existing tap. |
| VII Real-time safety | Layout preallocates everything (tested by stable addresses); nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device GPU timing stays `{device}`. |
| Privacy | Samples live only in memory; nothing stored or sent; two setting keys added to every key list. |

No deviation; no ADR needed (ADR-0009 covers native visuals; VIS-003/VIS-004 set the sample path and gain).
Post-design re-check: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/176-vis-005-radial-waveform/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/radial-waveform.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── RadialWaveformConfiguration.swift   # R₀, A, thickness, palette, background; clamped
├── RadialWaveformLayout.swift          # CPU geometry, taper, gain, FlashRegionLayout
└── RadialWaveformGenerator.swift       # Metal generator on FlatShapePass (behind VISUAL_NO_METAL)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── RadialWaveformFixtures.swift, RadialWaveformLayoutTests.swift
├── RadialWaveformFlashTests.swift, RadialWaveformRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/RadialWaveformGoldenTests.swift
Packages/RenderGoldens/GeneratorGoldens/RadialWaveform/{macos,ios-simulator}/
Apps/projectM-iOS/Coordinators/{AppSettings,AppCoordinator,SceneAutosaveCapture,ShowSceneSnapshot}.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/{SettingsView,VisualizerView}.swift
Apps/projectM-iOS/Tests/RadialWaveformAppTests.swift (+ native lists in SettingsTests, CameraVisualTests)
Apps/projectM-iOS/UITests/RadialWaveformUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: mirror VIS-004 file for file; no persistence and no tap change.

## Complexity Tracking

None.
