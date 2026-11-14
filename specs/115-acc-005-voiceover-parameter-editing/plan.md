# Implementation Plan: ACC-005 VoiceOver Parameter Editing

**Branch**: `feature/acc-005` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Every continuous slider in Settings gets one shared accessibility modifier,
`.accessibleParameter(_:value:set:didStep:)`, built on `.accessibilityValue` and
`.accessibilityAdjustableAction`. A pure core does the work and is unit-tested without views:
`SpokenValueFormatter` (one formatter per unit: percent, signed decibels, decibels full scale,
milliseconds, seconds), `ParameterStepper` (grid step from the range's minimum, clamp, end flag) and
`AccessibleParameterCatalog` (one spec per control: identifier, label, range, step, unit; the glow's
range and step hint come from MOD-001's `VisualParameterCatalog`). Each section exposes a
`ParameterTarget` (get/set over the real setting) that both the view and the table test use, so the
test exercises the view's own write path. End swipes announce "Maximum, …"/"Minimum, …" through the
shared `AccessibilityAnnouncer` on a new `parameter` lane (rate-limited by the existing gate). Each
slider becomes one accessibility element of its own (research D1, revised). A UI test reaches the
accessibility increment and decrement through a DEBUG probe that calls `accessibilityIncrement()` on
the element (research D2, revised) and checks the spoken value and the persisted value after a relaunch.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), SwiftUI, iOS 26+ deployment
**Primary Dependencies**: SwiftUI accessibility modifiers (`accessibilityValue`,
`accessibilityAdjustableAction`, `AccessibilityAdjustmentDirection`); ParameterGraph and
VisualParameters (MOD-001 registry); the app's `AccessibilityAnnouncer` (ACC-004)
**Storage**: unchanged; every control keeps writing its existing setting (UserDefaults keys of
AppSettings, TextOverlayStore, InputTrimSetting, NoiseGateSetting, LatencyOffsetSetting, VideoStore)
**Testing**: XCTest in `projectM-iOSTests` (formatter, stepper, catalog, announcement lane, table test
over every control with fresh UserDefaults suites); XCUITest `VoiceOverParameterUITests` (increment and
decrement on two sliders, relaunch); existing slider UI suites updated for the spoken values
**Target Platform**: iPhone and iPad
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no per-frame work; formatting happens when a Settings row renders
**Constraints**: public APIs only; labels and identifiers unchanged (R9); small SwiftUI bodies, no
`+` chains with ternaries inside modifiers (Xcode 26 type-check timeouts); nothing added to
`VisualizerView.body` (one argument added to the Settings sheet in `withPresentations`); minimal edits
to `SettingsView` (FILE-005 adds rows there in parallel)
**Scale/Scope**: 10 sliders in 5 views, 1 new source file, 1 new unit test file, 1 new UI test file

## Constitution Check

| Principle | Check | Status |
|---|---|---|
| I Public APIs only | SwiftUI accessibility modifiers, `UIAccessibility.post` via the existing announcer | Pass |
| II–V Capture | not touched | Pass |
| VI Modular boundaries | pure core in the app's Views layer with no UIKit dependency; registry read through its public API | Pass |
| VII Real-time audio safety | settings write the same thread-safe controls as before; no audio-thread code | Pass |
| VIII Upstream fidelity | engine untouched | Pass |
| IX Pinned dependencies | none added | Pass |
| X Evidence-based quality | unit, table and UI tests; the VoiceOver device pass stays `{device}` | Pass |

Post-design re-check: no change (no new module, no new storage, no network).

## Project Structure

### Documentation (this feature)

```text
specs/115-acc-005-voiceover-parameter-editing/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/accessible-parameters.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Views/AccessibleParameter.swift        # new: formatter, stepper, catalog, target, modifier
Apps/projectM-iOS/Views/SettingsView.swift               # glowSlider → modifier; announcer into the environment
Apps/projectM-iOS/Views/InputTrimSection.swift           # modifier + target
Apps/projectM-iOS/Views/NoiseGateSection.swift           # modifier + target
Apps/projectM-iOS/Views/LatencyOffsetSection.swift       # modifier + target (picked source)
Apps/projectM-iOS/Views/VideoLoopControls.swift          # modifier + target (dynamic range)
Apps/projectM-iOS/Views/VisualizerView.swift             # one argument in withPresentations (not body)
Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift  # AnnouncementKind.parameter
Apps/projectM-iOS/Tests/AccessibleParameterTests.swift   # new
Apps/projectM-iOS/UITests/VoiceOverParameterUITests.swift # new
scripts/check_status_events.py                           # adds AccessibleParameter.swift to the checked files
```

**Structure Decision**: the helper lives in the app target, beside the views that use it, because its
targets close over app settings types; the pure parts have no SwiftUI dependency beyond the modifier.

## Complexity Tracking

None.
