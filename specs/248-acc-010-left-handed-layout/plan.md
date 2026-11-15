# Implementation Plan: ACC-010 Left-Handed Layout

**Branch**: `feature/acc-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/248-acc-010-left-handed-layout/spec.md`

## Summary

A stored "Left-handed controls" switch mirrors the horizontal placement of the edge-anchored performance controls:
UIX-005's pad (bar, grid and side columns) and SHOW-014's emergency Black out corner button. The placement is a pure
value in ShowControl (`ControlsSide`, `PadPlacement`, `PerformanceLayout.targetFrames`), tested on the host and on
Linux for exact mirroring and identical identifiers; the SwiftUI pad draws from that placement. Nothing that renders
the visual or the output is touched, and no view is flipped or given a layout direction. ACC-009's one-handed hand,
when active, decides the side (research ACC-010-D2).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2; CI also builds with Xcode 26)

**Primary Dependencies**: SwiftUI; ShowControl (pure geometry, Linux-tested); PresentationLifecycle (external display, for the isolation test)

**Storage**: one UserDefaults Boolean, `settings.controls.leftHanded` (absent = off)

**Testing**: XCTest: ShowControl package tests (geometry), app unit tests (preference, side, output isolation), one XCUITest suite (two tests)

**Target Platform**: iOS/iPadOS 26+ (iPhone and iPad)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: no measurable cost: the placement is a few array operations per layout pass

**Constraints**: owner rule 7 test budgets; type-check budget (300 ms per body, 200 ms per expression); small focused edits in `VisualizerView.swift` and `SettingsView.swift` (other agents edit them)

**Scale/Scope**: 4 pad targets, 2 readouts, 1 corner button, 1 setting

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | SwiftUI layout only. Pass. |
| IV/V. Truthful labels, no capture claims | Labels and identifiers unchanged; no capture change. Pass. |
| VI. Modular boundaries | Geometry in ShowControl (no UI import); views in the app; renderer and output untouched. Pass. |
| VII. Real-time audio safety | No audio path change. Pass. |
| X. Evidence-based quality | Unit tests for the geometry and preference; UI test on a simulator is UI evidence only; `{device}` task for D1. Pass. |
| Privacy | One local preference; backed up and erased with Settings (FILE-005/FILE-011). No network. Pass. |

Post-design re-check: unchanged, pass. No ADR needed (no constitution default is overridden).

## Project Structure

### Documentation (this feature)

```text
specs/248-acc-010-left-handed-layout/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/left-handed-layout.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/ShowControl/Sources/ShowControl/HandedPlacement.swift      # ControlsSide, PadTarget, PadPlacement, targetFrames (new)
Packages/ShowControl/Tests/ShowControlTests/HandedPlacementTests.swift  # mirror and identifier tests (new)
Apps/projectM-iOS/Coordinators/OneHandedSetting.swift               # + leftHanded preference, controlsSide
Apps/projectM-iOS/Views/LeftHandedControls.swift                    # LeftHandedSection, EmergencyBlackoutCorner (new)
Apps/projectM-iOS/Views/PerformancePad.swift                        # draws from PadPlacement
Apps/projectM-iOS/Views/VisualizerView.swift                        # passes the side (2 lines)
Apps/projectM-iOS/Views/SettingsView.swift                          # shows the section (1 line)
Apps/projectM-iOS/Tests/LeftHandedAppTests.swift                    # preference, side, output isolation (new)
Apps/projectM-iOS/UITests/LeftHandedUITests.swift                   # switching in Settings, columns (new)
Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift, Packages/LibraryBackup/.../LibrarySettings.swift,
scripts/run_device_tests.py                                         # key lists
```

**Structure Decision**: follow ACC-009: pure geometry beside `PerformanceLayout` and `OneHandedLayout` in ShowControl;
the preference lives on ACC-009's `OneHandedSetting` object (one handedness object, no new coordinator property).

## Complexity Tracking

None.
