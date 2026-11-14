# Implementation Plan: ACC-008 High Contrast Overlay

**Branch**: `feature/acc-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Give every element drawn over the visualization one shared, measurable backing. A new `OverlaySurface`
modifier draws a black scrim (opacity `OverlayContrast.scrimOpacity` = 0.84, chosen by research ACC-008-D2;
opaque with Increase Contrast) on top of the element's material, forces the dark appearance and sets an
overlay tint that passes on that scrim (research D4). The controls' `ControlsBacking` (ACC-004), ACC-003's
`statusBadgeBackground` (material case) and every `.background(.regularMaterial, …)` of the audit move to
it; ACC-003's opaque bordered badges stay for Increase Contrast. Prominent buttons in overlays get a darker
fill tint. A unit-test fixture renders each audited element's backing and text styles with `ImageRenderer`
over four frames, with and without the text, and measures per-pixel WCAG contrast over glyph core pixels
(research D1); a negative control and the previous backings must fail. A DEBUG probe exposes the backing
level for one UI test. No frame is read back from the renderer (research D3).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), SwiftUI, iOS 26+ deployment
**Primary Dependencies**: SwiftUI (`Material`, `ShapeStyle`, `ImageRenderer`, environment), Core Graphics
(8-bit RGBA context), ACC-003's `InterfacePalette` and `StatusAppearance`
**Storage**: none
**Testing**: XCTest `OverlayContrastTests` in `projectM-iOSTests` (fixture table, negative control, scrim
choice, tints); XCUITest `OverlayContrastUITests` (probe, standard and Increase Contrast); existing
`ColorBlindControlsUITests` and `StatusUITests` as regressions
**Target Platform**: iPhone and iPad
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no per-frame work added; the backing is a static view modifier; fixture table under
10 s
**Constraints**: identifiers, labels, announcements, layouts unchanged; small SwiftUI bodies (CI's Xcode 26
type-checker); `VisualizerView.body` untouched; no animation; the CaptureUI package is not changed (its
banner sits inside the app's surface)
**Scale/Scope**: 1 new view file, ~12 view files touched by one-line backing swaps, 2 test files

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI materials, colours, `ImageRenderer`, Core Graphics | Pass |
| IV Truthful labeling | No words change | Pass |
| VI Modular boundaries | The surface lives in the app next to ACC-003's status styles; CaptureUI untouched | Pass |
| VII Real-time safety | No audio or render path change; no frame read-back (D3) | Pass |
| VIII Upstream fidelity | Presets and the visualization are not dimmed or recoloured | Pass |
| X Evidence | Fixture measurements in unit tests; D1 over bright presets is a `{device}` task | Pass |
| Privacy | Nothing stored or sent | Pass |
| Accessibility (ACC-001/003/004/006/011) | No animation, no announcement; Increase Contrast honoured; large sizes keep the backing | Pass |

Post-design re-check: unchanged, Pass. No ADR: no constitution default is overridden; the target and the
backing are design decisions recorded in research D1-D4.

## Project Structure

```text
specs/119-acc-008-high-contrast-overlay/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/overlay-surface.md
└── checklists/requirements.md

Apps/projectM-iOS/Views/OverlaySurface.swift          (new: OverlayContrast, OverlaySurface, tints, probe)
Apps/projectM-iOS/Views/ControlsOverlay.swift         (ControlsBacking → surface)
Apps/projectM-iOS/Views/StatusCues.swift              (statusBadgeBackground material case → surface)
Apps/projectM-iOS/Views/VisualizerView.swift          (banner, notice and route backings; Restore tint)
Apps/projectM-iOS/Views/{StatusCaptionView,ShowControls,BackgroundNoticeView,PermissionNoticeView,
  SessionRecoveryOfferCard,CaptureResultPanels,SceneSwitcherView,EmergencyBlackoutButton,CameraIndicator}.swift
Apps/projectM-iOS/Tests/OverlayContrastTests.swift    (new)
Apps/projectM-iOS/UITests/OverlayContrastUITests.swift (new)
```

**Structure Decision**: one new view file keeps the shared-file edits to one-line swaps (FILE-008, CMP-015
and others run in parallel).

## Complexity Tracking

None.
