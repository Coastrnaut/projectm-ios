# Implementation Plan: VIS-007 Mandala Symmetry

**Branch**: `feature/vis-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/195-vis-007-mandala/spec.md`

## Summary

A seventh native visual beside VIS-001 to VIS-006: one band-driven petal (12 flat quads) per sector,
repeated by rotation N ∈ {3, 4, 5, 6, 8, 12} times, optionally mirrored within each sector, turning
slowly on the injected frame clock. `MandalaLayout` builds sector 0 once per frame from the three band
groups and rotates it N times with precomputed sines and cosines, so every sector is an exact rotated
copy; the quads are the FX-019 flash regions. `MandalaGenerator` draws them with the shared
`FlatShapePass`, after VIS-001-R10's Reduce-flashing slew of the bands and FX-019's envelope gain. The
rotation keeps an anchor (time, angle, speed) so a speed change (Reduce Motion) is continuous. The app
adds the Visual choice "Mandala" with three setting keys (Symmetry, Mirror, Petal) and passes the
system Reduce Motion to the host. Proof: CPU acceptance (N = 4 vs 8: sectors and vertices double,
rotated copies within 1e-9, repeat bit-identical), mirror, silence, rotation cap and Reduce Motion,
flash-envelope tests, one GPU golden at N = 6, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (`FlatShapePass`), FlashSafety (envelope). No new dependency.

**Storage**: Three UserDefaults keys (`settings.mandala.symmetry`, `settings.mandala.mirror`,
`settings.mandala.petal`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and the Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` golden
(macOS host, iOS Simulator), app unit tests and one UI test on the agent's own simulator "VIS7".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: Per frame at most 12 sectors × 2 petals × 12 quads = 288 regions (1,728
vertices); no allocation per frame.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions (clock injected); type-check budget.

**Scale/Scope**: 3 new package source files, edits to about 9 app files, 3 package test files, a golden
test with 2 images per platform class, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of analysis, settings or projectM: it receives bands, a time and a configuration (Reduce Motion is a configuration flag the host sets). |
| VII Real-time safety | The layout preallocates everything; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device GPU timing stays `{device}`. |
| Privacy | Nothing stored or sent besides three setting keys, added to every key list. |

No deviation; no ADR needed (ADR-0009 covers native visuals, ADR-0011 the envelope). Post-design
re-check: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/195-vis-007-mandala/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/mandala.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── MandalaConfiguration.swift   # symmetry, mirror, petal style, speed, Reduce Motion, palette; band groups and petal curves
├── MandalaLayout.swift          # CPU sector geometry, rotation anchor, FlashRegionLayout
└── MandalaGenerator.swift       # Metal generator on FlatShapePass (behind VISUAL_NO_METAL)
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── MandalaLayoutTests.swift, MandalaFlashTests.swift, MandalaRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/MandalaGoldenTests.swift
Packages/RenderGoldens/GeneratorGoldens/Mandala/{macos,ios-simulator}/
Apps/projectM-iOS/Coordinators/{AppSettings,AppCoordinator,SceneAutosaveCapture,ShowSceneSnapshot}.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/{SettingsView,VisualizerView}.swift
Apps/projectM-iOS/Tests/MandalaAppTests.swift (+ native lists in SettingsTests, CameraVisualTests)
Apps/projectM-iOS/UITests/MandalaUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: mirror VIS-005/VIS-006 file for file.

## Complexity Tracking

None.
