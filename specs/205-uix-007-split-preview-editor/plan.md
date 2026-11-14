# Implementation Plan: UIX-007 Split Preview/Editor

**Branch**: `feature/uix-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/205-uix-007-split-preview-editor/spec.md`

## Summary

On iPad in regular width, Settings opens in an editor pane on the trailing side of the visualizer
instead of a sheet; the live output stays visible in the leading pane, uniformly scaled and centred so
its aspect ratio always equals the full window's. A draggable, adjustable divider sets the editor
width within bounds, with snap points, remembered on the device.

- `Packages/ShowControl/Sources/ShowControl/SplitEditorLayout.swift` (new): pure value type
  (`Double`, no UI import, beside UIX-005's `PerformanceLayout`): from the window size, a requested
  editor width and the output aspect → whether the split fits, the clamped editor width, the output
  pane, the output rect (exact aspect, centred) and its scale; snapping and the next/previous snap
  point (research UIX-007-D1, D2, D3).
- `Apps/projectM-iOS/Coordinators/SplitEditorSetting.swift` (new): the remembered width
  (`settings.splitEditor.width`, `-uitestResetNotice` removes it; D5).
- `Apps/projectM-iOS/Views/SplitEditorHost.swift` (new):
  - `SplitEditorHost`: wraps the visualizer's layers; when Settings is open and the split fits in
    regular width, adds the divider and the editor as a trailing safe-area inset and publishes the
    output placement through the environment.
  - `SplitOutputPlacement` (environment value) and `.splitOutputScaled()`: the visual keeps its full
    window size and is scaled (`scaleEffect`) and offset into the output rect (D1: no re-layout).
  - `SplitEditorDivider`: drag gesture, 24 pt hit area, grip, adjustable accessibility element.
  - DEBUG probe `splitOutputFrame` (device slot frame from UIKit, window size; D6).
- `VisualizerView.swift`: the body wraps `layers` in `SplitEditorHost`; `visual` gets
  `.splitOutputScaled()`; the Settings sheet's construction moves into one property used by the sheet
  and the editor pane; the sheet's binding is false while the split shows Settings.
- `SettingsView.swift`: Done calls the environment's `splitEditorClose` when set (else `dismiss()`).
- `AppCoordinator.swift`: one stored `splitEditor` setting.
- Key lists: `scripts/run_device_tests.py` `ALLOWED_KEYS`, FILE-005 `excludedKeys`.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), Swift 6 language mode.
**Primary Dependencies**: SwiftUI, UIKit (probe only), Observation; ShowControl.
**Storage**: one UserDefaults Double `settings.splitEditor.width` (excluded from backups).
**Testing**: ShowControl unit tests (geometry sweep, snapping); app unit tests (setting persistence
and reset); XCUITest `SplitEditorUITests` on an iPad simulator (open, drag, aspect probe; < 30 s each).
**Target Platform**: iOS 26.5+ (iPad regular width); CI Xcode 26 type-check budget.
**Performance Goals**: no rendering work on resize (the visual is scaled, not re-laid out); no per-frame work.
**Constraints**: public APIs only; no networking; small edits to shared files.

## Constitution Check

- I Public APIs only: SwiftUI layout, gestures, `accessibilityAdjustableAction`, UIKit `convert`. Pass.
- VI Modular boundaries: geometry in ShowControl (pure Swift), UI in the app. Pass.
- VII Real-time audio safety: main-actor UI only. Pass.
- X Evidence-based quality: geometry unit tests; simulator UI test for UI behavior; device pass on D2
  is `{device}`. Pass.
- Privacy (FR-065): one layout preference, device-only, never backed up. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/205-uix-007-split-preview-editor/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/split-editor.md
└── checklists/requirements.md
```

### Source Code

```text
Packages/ShowControl/Sources/ShowControl/SplitEditorLayout.swift          (new)
Packages/ShowControl/Tests/ShowControlTests/SplitEditorLayoutTests.swift  (new)
Apps/projectM-iOS/Coordinators/SplitEditorSetting.swift                   (new)
Apps/projectM-iOS/Views/SplitEditorHost.swift                             (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                       (one property)
Apps/projectM-iOS/Views/VisualizerView.swift                              (wrap, scale, sheet binding)
Apps/projectM-iOS/Views/SettingsView.swift                                (Done)
Apps/projectM-iOS/Tests/SplitEditorSettingTests.swift                     (new)
Apps/projectM-iOS/UITests/SplitEditorUITests.swift                        (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift        (excluded key)
scripts/run_device_tests.py                                               (allowed key)
```

**Structure Decision**: geometry as a package value type (fast host/Linux tests), views in the app.

## Complexity Tracking

None.
