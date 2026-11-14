# Implementation Plan: ACC-006 Dynamic Type Inspector

**Branch**: `feature/acc-006` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/087-acc-006-dynamic-type-inspector/spec.md`

## Summary

Two parts:

1. **Fixes** (R1-R3, R5), each only at accessibility sizes (`@Environment(\.dynamicTypeSize)
   .isAccessibilitySize`), so standard sizes keep today's layouts:
   - `Views/ControlsOverlay.swift`: the compact layout's status and tempo row stacks vertically; the
     preset, visual and scope names wrap to three lines; the whole controls body is a
     `ViewThatFits(in: .vertical) { content; ScrollView { content } }` with `.layoutPriority(1)`, so it
     takes the height above it first and scrolls only when it does not fit; a simultaneous drag gesture
     restarts the auto-hide (`showControls()`).
   - `Views/TempoControls.swift`: the readout's one line and 0.7 minimum scale apply only at standard
     sizes.
   - `Views/PermissionNoticeView.swift`: `AnyLayout` HStack → VStack; the text never truncates.
   - `Views/UserPresetEditorView.swift`: the Name field becomes a vertical-axis field (1-4 lines,
     newlines replaced by spaces).
   - `Views/SceneRepairReportView.swift`: the buttons move from the bottom inset into the list's last
     section.
   - `Packages/CaptureUI`: `AudioRouteIndicator` and `TransportBar`'s title wrap to three lines.
2. **Inspector** (R4, R6, R7): `UITests/DynamicTypeInspectorUITests.swift`, ten screen groups × {AX5,
   AX3} = 20 tests, each one launch under 30 s. Per screen: `performAccessibilityAudit(for:
   [.dynamicType, .textClipped])` with per-element filters (contract C2), then affordance checks
   (contract C1): `scrollTo` + `isHittable` for the last control, inside-the-window frames for pinned
   buttons, `typeText` + value check for fields. `TEST_RUNNER_ACC006_SIZE` overrides the size,
   `TEST_RUNNER_ACC006_SURVEY` keeps going after failures. ACC-004's `AccessibilityScreensUITests`
   loses the Dynamic Type filters its AX5-start runs no longer need (R7).

No ADR: no default is overridden. No DEBUG in-app overlay (research ACC-006-D1), so nothing new in
the app binary beyond the layout changes.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; Xcode 26 in CI: explicit closure types, typed
steps for strings, no C stdio globals).

**Primary Dependencies**: SwiftUI (`ViewThatFits`, `AnyLayout`, `dynamicTypeSize`), XCTest
(`performAccessibilityAudit`, `.textClipped`). No new package.

**Storage**: none.

**Testing**: new `DynamicTypeInspectorUITests` (20 tests, < 30 s each); `AccessibilityScreensUITests`
(filters changed); regression suites of changed screens that this agent may run but not edit:
`SceneRepairUITests`, `PermissionAuditUITests`, `CameraPrivacyStatusUITests`, `TapTempoUITests`,
`RouteIndicatorUITests`, `GuidedFirstSceneUITests`, `ReduceMotionUITests`, `VisualizerUITests`;
`UserPresetEditingUITests` (owned by another agent; run, not edited); `projectM-iOSTests`; CaptureUI
package tests.

**Target Platform**: iOS 26+; the audit's `.textClipped` needs iOS 17+.

**Project Type**: mobile app.

**Performance Goals**: none new; `ViewThatFits` measures the controls once per layout pass only at
accessibility sizes.

**Constraints**: public APIs only; UI strings unchanged (no pinned text touched); no animation added
(MotionPolicy unaffected); `SettingsView` untouched (other agents add rows there).

**Scale/Scope**: 7 view files, 1 UI suite (20 tests), 1 suite's filters.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: SwiftUI layout and XCTest audit APIs. |
| II-V Capture | Not affected. |
| VI Modular boundaries | Pass: CaptureUI changes stay inside its views. |
| VII Real-time audio safety | Not affected. |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | Pass: none added. |
| X Evidence-based quality | Pass: simulator UI tests; device pass is `{device}` (ACC-006-T12). |
| Privacy | Not affected. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/087-acc-006-dynamic-type-inspector/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/dynamic-type-inspector.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Views/ControlsOverlay.swift, TempoControls.swift, PermissionNoticeView.swift,
│   UserPresetEditorView.swift, SceneRepairReportView.swift
└── UITests/DynamicTypeInspectorUITests.swift (new), AccessibilityScreensUITests.swift (filters)
Packages/CaptureUI/Sources/CaptureUI/AudioRouteIndicator.swift, TransportBar.swift
specs/082-acc-004-voiceover-scene-browser/contracts/accessibility-tree.md (C3 update)
```

**Structure Decision**: app target plus two CaptureUI views, matching ACC-004.

## Complexity Tracking

None.
