# Implementation Plan: OUT-012 External Display Rehearsal

**Branch**: `feature/out-012` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/184-out-012-display-rehearsal/spec.md`

## Summary

A rehearsal shows on the device what an external display of a chosen profile would show. It reuses
OUT-004 end to end: a pure `ExternalOutputRehearsal` (PresentationLifecycle) builds the
`ExternalOutputPlacement` with the same initializer the real slot uses (the profile's PAR standing in
for the screen mode's) and adds the preview transform (slot → device frame, physical shape). In the
app, `RehearsalPreviewView` hosts a real `VisualSlotView(role: .external)` the size of the profile,
given a stand-in PAR, holding a test card, scaled by the preview transform. The coordinator gains an
observable rehearsal flag that a settled real display clears. Settings › External Display gets
"Rehearse output…" opening a full-screen cover.

## Technical Context

**Language/Version**: Swift 6.4 (Xcode 27.2), strict concurrency; CI also builds with Xcode 26 / iOS SDK 26.5
**Primary Dependencies**: UIKit (`UIView` transform, `CAShapeLayer`), SwiftUI (`fullScreenCover`), `PresentationLifecycle`
**Storage**: none (rehearsal state is transient)
**Testing**: PresentationLifecycle package tests (host, Linux): preview mapping and circle roundness; app unit tests: preview vs a real external slot (point mapping within 0.5 pt, bitmap axis ratio within 2 %), connect ends rehearsal; one UI test with the probe
**Target Platform**: iOS/iPadOS 26.5 and 27
**Performance Goals**: layout-only work; no render pass; the live visual is untouched
**Constraints**: public APIs only; no wall-clock assertions; unit tests ≤ 10 s, UI test ≤ 30 s; type-check budget
**Scale/Scope**: one pure type, one UIKit preview view, one SwiftUI screen, small slot/coordinator/section edits

## Constitution Check

| Principle | Check |
|---|---|
| I Public APIs only | UIView transforms, Core Animation shape layers, SwiftUI. PASS |
| VI Modular boundaries | Geometry pure Swift in `PresentationLifecycle` (Linux-tested); UIKit in the app. PASS |
| VII Real-time audio safety | Nothing touches audio or the renderer. PASS |
| X Evidence-based quality | Simulator only shows the mapping; matching a real projector is `{device}`. PASS |
| Privacy | Nothing stored, no network. PASS |

Post-design re-check: unchanged, PASS.

## Project Structure

```text
specs/184-out-012-display-rehearsal/
├── plan.md, research.md, data-model.md, quickstart.md, tasks.md
└── contracts/rehearsal.md

Packages/PresentationLifecycle/Sources/PresentationLifecycle/ExternalOutputRehearsal.swift          (new)
Packages/PresentationLifecycle/Tests/PresentationLifecycleTests/ExternalOutputRehearsalTests.swift  (new)
Apps/projectM-iOS/ExternalDisplay/VisualSlotView.swift              (stand-in PAR)
Apps/projectM-iOS/ExternalDisplay/ExternalDisplayCoordinator.swift  (rehearsal flag, settled-display flag)
Apps/projectM-iOS/ExternalDisplay/RehearsalPreviewView.swift        (new: UIKit preview + test card)
Apps/projectM-iOS/Views/ExternalRehearsalView.swift                 (new: full-screen rehearsal)
Apps/projectM-iOS/Views/ExternalDisplaySection.swift                (row + cover)
Apps/projectM-iOS/ExternalDisplay/ExternalOutputSetting.swift       (expose coordinator, strings)
Apps/projectM-iOS/Tests/ExternalRehearsalTests.swift                (new: acceptance)
Apps/projectM-iOS/UITests/ExternalRehearsalUITests.swift            (new)
```

**Structure Decision**: geometry beside `ExternalOutputPlacement`; the preview reuses the slot class.
No edits to SettingsView, VisualizerView, AppCoordinator or Compositor.

## Complexity Tracking

None.
