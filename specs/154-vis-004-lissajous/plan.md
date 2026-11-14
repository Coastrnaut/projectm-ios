# Implementation Plan: VIS-004 Lissajous Scope

**Branch**: `feature/vis-004` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/154-vis-004-lissajous/spec.md`

## Summary

A fourth native visual beside VIS-001 to VIS-003: the left channel plotted against the right (X/Y)
or rotated 45° (Mid/Side), drawn as a palette-colored polyline through the shared `FlatShapePass`,
scaled by a deterministic auto-gain with hold, with an optional phosphor-style persistence made of
weighted CPU snapshots whose half-life follows FX-009 Trails' ACC-012 caps. Stereo samples come from
VIS-003's pass-through `WaveformTap`, which gains a stereo history. The app adds a Visual choice
"Lissajous" with two setting keys. Proof: CPU principal-axis metrics on in-phase and quadrature
fixtures, two GPU goldens, a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (runtime-compiled shader already in `FlatShapePass`), FlashSafety
(`SafetyClamp`, the envelope), AudioCore (`NormalizedPCMRing` channel count). No new dependency.

**Storage**: Two UserDefaults keys (`settings.lissajous.mode`, `settings.lissajous.persistence`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and the Linux shape
`-Xswiftc -DVISUAL_NO_METAL`), `Packages/RenderGoldens` goldens (macOS host, iOS Simulator), app unit
tests and one UI test on the agent's own simulator "VIS4".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: Per frame at most 1,023 + 8 × 127 segments (≈ 13,000 vertices) and as many
flash regions; no allocation per frame; the tap's extra copy ≤ 16 KB per analysis read.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions (frame durations injected);
type-check budget (300 ms per function, 200 ms per expression).

**Scale/Scope**: About 4 new package source files, edits to 7 app files, 4 test files, goldens.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, QuartzCore, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of capture, settings or projectM; the stereo history lives in `VisualBandFeed`'s tap; the ACC-012 rule is a pure function in the package. |
| VII Real-time safety | The tap's stereo copy runs on the analysis worker (never an audio callback), fixed storage, one atomic exchange; the layout preallocates everything (tested by stable addresses). |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device GPU timing stays `{device}`. |
| Privacy | Samples live only in memory (16 KB); nothing stored or sent; two setting keys added to every key list. |

No deviation; no ADR needed (ADR-0009 already covers native visuals; VIS-003 set the sample-path
precedent).

## Project Structure

### Documentation (this feature)

```text
specs/154-vis-004-lissajous/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/lissajous-scope.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── LissajousConfiguration.swift   # mode, half-life, thickness, palette, background; ACC-012 limit
├── LissajousAutoGain.swift        # level with hold and release (injected frame durations)
├── LissajousLayout.swift          # CPU geometry, snapshots, tessellation, flash regions
└── LissajousGenerator.swift       # Metal generator (FlatShapePass), behind VISUAL_NO_METAL
Packages/VisualGenerators/Sources/VisualBandFeed/WaveformTap.swift   # + stereo history
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── LissajousFixtures.swift, LissajousLayoutTests.swift, LissajousPersistenceTests.swift,
├── LissajousRenderTests.swift (Metal), WaveformTapStereoTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/LissajousGoldenTests.swift
Packages/RenderGoldens/GeneratorGoldens/Lissajous/<class>/   # 4 PNGs + manifest per class
Apps/projectM-iOS/Coordinators/AppSettings.swift      # choice, keys, LissajousMode titles
Apps/projectM-iOS/Coordinators/AppCoordinator.swift   # style mapping (one case)
Apps/projectM-iOS/Coordinators/ShowSceneSnapshot.swift, SceneAutosaveCapture.swift  # no layer
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift    # style, stereo input, clamp → half-life
Apps/projectM-iOS/Views/SettingsView.swift            # Plot, Persistence, footer
Apps/projectM-iOS/Views/VisualizerView.swift          # onChange for the two settings
Apps/projectM-iOS/Tests/LissajousAppTests.swift, UITests/LissajousUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py  # key lists
```

**Structure Decision**: Follow VIS-003 exactly: package CPU parts plus a Metal generator, one host
style, generator-level goldens in a folder of their own.

## Complexity Tracking

None.
