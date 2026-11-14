# Implementation Plan: VIS-006 Beat Pulse Rings

**Branch**: `feature/vis-006` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/186-vis-006-beat-rings/spec.md`

## Summary

A sixth native visual beside VIS-001 to VIS-005: a ring spawns at the centre on each beat, grows eased
out over its life and fades. The ring state (`BeatRingField`) is a pure function of the accepted birth
times, the configuration and the frame time; at most 16 live rings, a rate cap (1/6 s, 1/3 s under a
rise-limited envelope), a 50 ms attack and a 0.8 peak. Each ring is 64 flat annulus segments drawn by
the shared `FlatShapePass`; the segments are the FX-019 flash regions. The host drains its analyzer's
bus events per frame through `BeatRingTrigger` (ANL-005 confident beats, ANL-007 kick fallback) and
stamps births with the frame time. The app adds the Visual choice "Beat Rings" with one setting key
(Ring life). Proof: CPU acceptance (four beats, four independent rings, zero after life), cap, rate,
determinism and flash-envelope tests, one GPU golden of four rings, app tests and a short UI test.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26), Swift 6 language mode

**Primary Dependencies**: Metal (`FlatShapePass`), FlashSafety (envelope), AnalysisFeatures (bus
events, only in `VisualBandFeed`). No new dependency.

**Storage**: One UserDefaults key (`settings.beatRings.life`).

**Testing**: XCTest. `swift test --package-path Packages/VisualGenerators` (host and the Linux shape
`-Xswiftc -DVISUAL_NO_METAL -Xswiftc -DANALYSIS_NO_ACCELERATE`), `Packages/RenderGoldens` golden
(macOS host, iOS Simulator), app unit tests and one UI test on the agent's own simulator "VIS6".

**Target Platform**: iOS/iPadOS 26.0+ (app); macOS 15+ and Linux for the package's CPU parts.

**Project Type**: iOS app with SwiftPM packages.

**Performance Goals**: Per frame at most 16 × 64 = 1,024 segments (6,144 vertices) and as many flash
regions; no allocation per frame.

**Constraints**: Owner rule 7 test budgets; no wall-clock assertions (clock injected); type-check budget.

**Scale/Scope**: 4 new package source files, edits to about 8 app files, 3 package test files, a golden
test with 2 images per platform class, 1 app unit test file, 1 UI test.

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Metal, UIKit, SwiftUI only. `check_compliance.py` runs. |
| II-V Capture | Not touched; no claims. |
| VI Modular boundaries | The generator knows nothing of analysis, settings or projectM: it receives birth times. The trigger lives in `VisualBandFeed`, beside the analyzer. |
| VII Real-time safety | Field and layout preallocate everything; the bus drain copies value types from preallocated storage; nothing on an audio callback. |
| VIII Upstream fidelity | Nothing reaches projectM. |
| IX Dependencies | None added. |
| X Evidence | Unit, golden and UI tests; device GPU timing stays `{device}`. |
| Privacy | Events live only in memory; nothing stored or sent; one setting key added to every key list. |

No deviation; no ADR needed (ADR-0009 covers native visuals, ADR-0011 the envelope). Post-design
re-check: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/186-vis-006-beat-rings/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/beat-rings.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Packages/VisualGenerators/Sources/VisualGenerators/
├── BeatRingConfiguration.swift   # life, thickness, palette, background, curves, caps
├── BeatRingField.swift           # pure ring state: births, cap, rate cap, sampling
├── BeatRingLayout.swift          # CPU annulus geometry, FlashRegionLayout
└── BeatRingGenerator.swift       # Metal generator on FlatShapePass (behind VISUAL_NO_METAL)
Packages/VisualGenerators/Sources/VisualBandFeed/BeatRingTrigger.swift   # bus events → emissions
Packages/VisualGenerators/Tests/VisualGeneratorsTests/
├── BeatRingFieldTests.swift, BeatRingLayoutTests.swift (+ trigger), BeatRingFlashTests.swift, BeatRingRenderTests.swift
Packages/RenderGoldens/Tests/RenderGoldensTests/BeatRingGoldenTests.swift
Packages/RenderGoldens/GeneratorGoldens/BeatRings/{macos,ios-simulator}/
Apps/projectM-iOS/Coordinators/{AppSettings,AppCoordinator,SceneAutosaveCapture,ShowSceneSnapshot}.swift
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift
Apps/projectM-iOS/Views/{SettingsView,VisualizerView}.swift
Apps/projectM-iOS/Tests/BeatRingsAppTests.swift (+ native lists in SettingsTests, CameraVisualTests)
Apps/projectM-iOS/UITests/BeatRingsUITests.swift
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py
```

**Structure Decision**: mirror VIS-005 file for file, plus the pure field and the trigger.

## Complexity Tracking

None.
