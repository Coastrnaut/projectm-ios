# Implementation Plan: UIX-013 Scene Performance HUD

**Branch**: `feature/uix-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A compact, device-only HUD at the top of the visualizer's status stack shows the current cue, the next cue,
the tempo with its source and the audio source. A pure `SceneHUDContent` builds the texts from existing state
(SHOW-001 cue list, SHOW-002 countdown, SHOW-003 queued step, SHOW-011/ANL-006 tempo readout, FR-042 source
text); `SceneHUDSetting` stores the one preference; `SceneHUDLayer` draws it on the ACC-008 overlay surface.
Exclusion from the output is structural (research UIX-013-D1) and proven by tests that compare the external
window, a recording and a saved frame with the HUD on and off.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: SwiftUI, ShowControl, PerformanceControl (existing app modules only)
**Storage**: one UserDefaults Bool `settings.visualizer.sceneHUD`
**Testing**: XCTest app unit tests (`projectM-iOSTests`), one XCUITest; private simulator "UIX13 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26.5+
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no frame-loop cost (the HUD is SwiftUI text; the visual's Metal path is untouched)
**Constraints**: type-check budget (300 ms per body, 200 ms per expression); unit test ≤ 10 s, UI test < 30 s
**Scale/Scope**: 2 new source files, 2 test files, small edits to `VisualizerView`, `SettingsView`, `AppCoordinator` and three key lists

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Pass: SwiftUI and UIKit only. |
| IV Truthful source labeling | Pass: the source line is the FR-042 indicator text verbatim (R6). |
| VI Modular boundaries | Pass: view layer only; no engine, capture or renderer change. |
| VII Real-time audio safety | Pass: reads main-actor state already published; nothing on audio threads. |
| X Evidence | Unit and UI tests on the simulator; the device look on D1 is a `{device}` task. Simulator results are not device evidence. |
| Privacy | Pass: one preference Bool, backed up and erased with Settings; no network, no new permission. |

Post-design re-check: unchanged, all pass. No ADR needed (no default overridden).

## Project Structure

```text
specs/233-uix-013-performance-hud/  spec, plan, research, data-model, contracts/scene-hud.md, quickstart, tasks
Apps/projectM-iOS/Coordinators/SceneHUDSetting.swift     preference (new)
Apps/projectM-iOS/Views/SceneHUD.swift                   SceneHUDContent + SceneHUDLayer (new)
Apps/projectM-iOS/Views/VisualizerView.swift             one line in topStatus, one SettingsView argument
Apps/projectM-iOS/Views/SettingsView.swift               one property, one row in performanceSection
Apps/projectM-iOS/Coordinators/AppCoordinator.swift      one lazy property
Apps/projectM-iOS/Tests/SceneHUDAppTests.swift           content, preference, exclusion acceptance (new)
Apps/projectM-iOS/UITests/SceneHUDUITests.swift          HUD with the show seed (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Tests/LibraryBackupAppTests.swift  key lists
```

**Structure Decision**: app-layer feature; no new package.
