# Implementation Plan: UIX-005 Performance Control Layout

**Branch**: `feature/uix-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/193-uix-005-performance-controls/spec.md`

## Summary

A session-only "performance layout" that shows a persistent pad of large targets (Previous cue,
Next cue, Tap tempo, Blackout) and two readouts on the visualizer. The geometry is a pure value type
in the ShowControl package (Linux-testable); the pad and its wiring are app views.

- `Packages/ShowControl/Sources/ShowControl/PerformanceLayout.swift` (new): `PerformanceLayout`
  (arrangement, target side, spacing, margin, column width, reserved insets) from the area's size and
  whether both size classes are regular (research UIX-005-D1, D2). Pure Swift (`Double`), no UI import.
- `Apps/projectM-iOS/Views/PerformancePad.swift` (new):
  - `PerformancePadLayer`: a `GeometryReader` inside the safe area; builds `PerformanceLayout`,
    draws the bottom bar or the side columns, and reports the insets it reserves (callback).
  - `PerformancePadButton`: one target (`frame(width: side, height: side)`, ACC-008 overlay surface,
    symbol only, Large Content Viewer, label/value/identifier).
  - `PerformanceCueReadout`, `PerformanceTempoReadout`: the readouts (ACC-008 surface, two lines max).
  - The Blackout target's state (`PerformancePadBlackout`): title, icon, enabled, action and whether it
    carries the B key, from `OutputBlackout.Phase` (pure, unit-tested).
- `Apps/projectM-iOS/Coordinators/AppCoordinator+PerformanceLayout.swift` (new): `togglePerformanceLayout()`
  and the DEBUG launch flag. The pad receives the show, tempo and output coordinators and calls
  `show.next()`/`previous()` and `tempo.tap()` directly (no `showControls()`; research UIX-005-D8).
- `AppCoordinator.swift`: one stored property `performanceLayout` (other agents edit this file).
- `ControlsOverlay.swift`: one `Item` in `allButtons` ("Performance layout"/"Standard layout").
- `VisualizerView.swift`: one `@State` for the reserved insets, one layer line, one `.padding` on the
  status stack, and the emergency button's condition gains `!coordinator.performanceLayout`.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), Swift 6 language mode.
**Primary Dependencies**: SwiftUI, Observation; ShowControl, PresentationLifecycle, PerformanceControl (read-only).
**Storage**: none (session state only; FR-065).
**Testing**: ShowControl package unit tests (geometry), app unit tests (blackout target state, toggle),
XCUITest `PerformanceLayoutUITests` (portrait, landscape, AX5, audit; each < 30 s).
**Target Platform**: iOS 26.5+; CI Xcode 26 type-check budget (bodies split into properties).
**Performance Goals**: no per-frame work; the pad observes the same state as the controls.
**Constraints**: public APIs only; no networking; targets ≥ 60 pt; inside the safe area.

## Constitution Check

- I Public APIs only: SwiftUI layout, accessibility modifiers, Large Content Viewer. Pass.
- VI Modular boundaries: geometry in ShowControl (Foundation-free pure Swift), UI in the app. Pass.
- VII Real-time audio safety: main-actor UI only; actions call existing coordinator methods. Pass.
- X Evidence-based quality: unit tests for geometry, UI tests on the simulator for UI behavior only;
  a performer's pass on a device is `{device}`. Pass.
- Privacy (FR-065): nothing stored. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/193-uix-005-performance-controls/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/performance-pad.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ShowControl/Sources/ShowControl/PerformanceLayout.swift             (new)
Packages/ShowControl/Tests/ShowControlTests/PerformanceLayoutTests.swift     (new)
Apps/projectM-iOS/Views/PerformancePad.swift                                  (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+PerformanceLayout.swift         (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                           (one property)
Apps/projectM-iOS/Views/ControlsOverlay.swift                                 (one button)
Apps/projectM-iOS/Views/VisualizerView.swift                                  (layer, insets, emergency condition)
Apps/projectM-iOS/Tests/PerformancePadTests.swift                             (new)
Apps/projectM-iOS/UITests/PerformanceLayoutUITests.swift                      (new)
```

**Structure Decision**: geometry as a package value type (fast host/Linux tests), views in the app.

## Complexity Tracking

None.
