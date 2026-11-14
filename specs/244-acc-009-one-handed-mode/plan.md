# Implementation Plan: ACC-009 One-Handed Performance Mode

**Branch**: `feature/acc-009` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

A Settings choice (Off, Left hand, Right hand; iPhone only) moves the eleven critical actions out of the controls
card into a cluster of square targets in the bottom corner of the chosen side. The placement is a pure, Linux-tested
`OneHandedLayout` in ShowControl beside UIX-005's `PerformanceLayout`: thumb zone, target sides (44-56 pt with
Dynamic Type, the pad's 60/72 pt for the pad group), rows from the bottom in a fixed order, a reserved edge band.
`CriticalAction` defines the standard layout's set for a state (show, pad, visual, controls shown), which both
layouts use. In the app, `OneHandedSetting` stores the choice; `OneHandedControlsLayer` draws the main group (and the
pad group when the pad is off) and reports the reserved band, which the status stack already applies for the pad;
`PerformancePadLayer` gains a one-handed arrangement for its four targets; `ControlsOverlay`, `TempoControls` and
`ShowCueRow` leave out the moved actions while the mode is active.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: ShowControl (pure geometry), SwiftUI
**Storage**: one UserDefaults key `settings.controls.oneHanded` (String "left"/"right"; absent = Off)
**Testing**: ShowControl package tests (host, Linux-safe), app unit tests, XCUITests on private simulators "ACC9 iPhone 17" and a small iPhone (iOS 27.2); QA-009 manifest entry
**Target Platform**: iOS 26.0+ (iPhone only for this feature)
**Project Type**: mobile app (XcodeGen `project.yml`) + SwiftPM packages
**Performance Goals**: geometry is a few dozen arithmetic operations per layout pass; no per-frame work
**Constraints**: type-check budget (300 ms per body, 200 ms per expression); unit test ≤ 10 s, package suite < 1 min, UI test < 30 s; focused edits in ControlsOverlay, VisualizerView, AppCoordinator
**Scale/Scope**: 1 package file + tests, 3 app files (setting, layer, section), small edits to ControlsOverlay, PerformancePad, TempoControls, ShowControls, VisualizerView, SettingsView, AppCoordinator, key lists, QA-009 manifest

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Pass: SwiftUI layout only. |
| IV Truthful labeling | Pass: the source indicator and its text are unchanged. |
| VI Modular boundaries | Pass: the geometry knows no UI framework; the app maps actions to its coordinator calls. |
| VII Real-time audio safety | Pass: no audio-thread work. |
| X Evidence | Geometry table tests and simulator UI tests; thumb reach on D1 is a `{device}` task. |
| Privacy | Pass: one local preference, backed up and erased with Settings; no network, no permission. |

Post-design re-check: unchanged, all pass. No ADR (no default overridden; Off by default, iPad unchanged).

## Project Structure

```text
specs/244-acc-009-one-handed-mode/  spec, plan, research, data-model, contracts/one-handed-layout.md, quickstart, tasks
Packages/ShowControl/Sources/ShowControl/OneHandedLayout.swift          CriticalAction, Hand, layout (new)
Packages/ShowControl/Tests/ShowControlTests/OneHandedLayoutTests.swift  phone-size table (new)
Apps/projectM-iOS/Coordinators/OneHandedSetting.swift                    preference + AppCoordinator helpers (new)
Apps/projectM-iOS/Views/OneHandedControls.swift                          layer + Settings section (new)
Apps/projectM-iOS/Views/PerformancePad.swift                             one-handed arrangement of the pad
Apps/projectM-iOS/Views/ControlsOverlay.swift, TempoControls.swift, ShowControls.swift   leave out moved actions
Apps/projectM-iOS/Views/VisualizerView.swift, SettingsView.swift, Coordinators/AppCoordinator.swift   one property / row / layer
Apps/projectM-iOS/Tests/OneHandedAppTests.swift                          setting + action mapping (new)
Apps/projectM-iOS/UITests/OneHandedUITests.swift                         switch, zone, HUD (new)
Apps/projectM-iOS/UITests/PrimaryScreensManifest.swift, PrimaryScreensAccessibilityUITests.swift   QA-009 entry
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift, Debug/UITestSettingsSection.swift   key and anchor lists
```

**Structure Decision**: the geometry sits in ShowControl next to `PerformanceLayout` (same owner, already in CI's
library group and on Linux); no new package.
