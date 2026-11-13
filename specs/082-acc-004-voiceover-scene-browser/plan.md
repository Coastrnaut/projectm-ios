# Implementation Plan: ACC-004 VoiceOver Scene Browser

**Branch**: `feature/acc-004` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/082-acc-004-voiceover-scene-browser/spec.md`

## Summary

Three parts, all in the app target:

1. **Announcements** (R5-R7, R9): `Apps/projectM-iOS/Coordinators/AccessibilityAnnouncer.swift`.
   - `AnnouncementKind` (preset, cue, playback, output, recording, favorite).
   - `AnnouncementGate`: a pure value type implementing the rule of Clarification 1 with times
     passed in (`submit(text:kind:now:)` → speak now / wait until a time / drop;
     `windowClosed(kind:now:)` → the pending text to speak, if any). Unit-tested with a fake clock.
   - `AccessibilityAnnouncer` (`@MainActor @Observable`): owns a gate, a poster (default
     `UIAccessibility.post(notification: .announcement, …)`), a monotonic clock
     (`ProcessInfo.systemUptime`) and a scheduler (default: a main-actor `Task` that sleeps until the
     window closes). It records `lastSpoken` ("<kind>|<text>") for the DEBUG probe
     `announcementProbe` (shown with `-uitestDiagnostics`).
   - Wiring: `AppCoordinator.announcer`. Preset changes after `next()`, `previous()`, `random()`
     and `choose(_:from:)` when the current preset actually changed ("Preset: <name>");
     `togglePause()` ("Visualization paused" / "Visualization resumed"); `VisualizerView`
     `.onChange` of `externalDisplay.isBlackoutRequested` ("Output blacked out" / "Output restored")
     and of `videoRecording.state` ("Recording started" / "Recording stopped") and its `notice`
     (the refusal text); `ShowCoordinator.announce` routed through kind `cue`;
     `PresetCoordinator.toggleFavoriteAnnounced(_:)` for the star and the new rotor action
     ("Added to favorites: <name>" / "Removed from favorites: <name>").
2. **Labels, traits, hints, actions** (R1-R4): `PresetRow` gets `.isSelected` for the current
   preset, the hint "Plays this preset" (or "Opens the unlock sheet" when locked), and a rotor action
   "Add to Favorites" / "Remove from Favorites"; show cue rows get `.isSelected` when active and
   rotor actions Move Up / Move Down (`ShowCoordinator.move(fromOffsets:toOffset:)`); the controls'
   Previous, Next, Random, Presets and Black out buttons get hints. No visible text changes.
3. **Automated check** (R8, R1): `Apps/projectM-iOS/UITests/AccessibilityScreensUITests.swift`.
   One test per screen group (each < 30 s): visualizer controls with the show seed; preset browser
   home + a pack folder; collections + My Presets; Settings + show editor; one test for the
   announcement probe (Next, Pause, Black out). Each screen runs
   `performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .contrast,
   .dynamicType, .trait])` with an issue handler that consults a per-issue filter list
   (`AccessibilityAuditFilter`, contract C3) and then checks the declared primary controls (contract
   C2): exists, non-empty label, `isHittable`, declared element type.

No ADR: no default is overridden.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; Xcode 26 in CI: explicit closure types, no C
stdio globals).

**Primary Dependencies**: SwiftUI, UIKit (`UIAccessibility`), Observation, XCTest/XCUIAutomation
(`performAccessibilityAudit`, iOS 17+). No new package.

**Storage**: none.

**Testing**: `projectM-iOSTests` (new `AccessibilityAnnouncerTests`), new UI suite
`AccessibilityScreensUITests` (each test < 30 s), regression UI suites of changed screens:
`ShowCueUITests`, `SceneDuplicateUITests` (show editor rows), `ReduceMotionUITests` (controls),
`EmergencyBlackoutUITests`, `OutputBlackoutUITests`. Not edited: the suites another agent is
shortening (PresetCollections, UserPresets, UserPresetEditing, UserPresetExport, RepeatMode, Status,
Interruption, Transport, PresetLibrary). No wall-clock assertions: the gate takes times as input.

**Target Platform**: iOS 26+ (app); the audit needs iOS 17+ (the test simulator runs 27.2).

**Project Type**: mobile app.

**Performance Goals**: none new; one dictionary lookup per announcement.

**Constraints**: public APIs only; DEBUG-only probe; no main-actor mutation in setUp/tearDown;
UI strings pinned by contracts unchanged.

**Scale/Scope**: 6 announcement kinds, about 10 view edits, 1 UI suite (5 tests), 1 unit suite.

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: `UIAccessibility.post`, SwiftUI accessibility modifiers, XCTest audit. |
| II-V Capture | Not affected; no capture claim. |
| VI Modular boundaries | Pass: UI concerns stay in the app target; the gate is a pure value. |
| VII Real-time audio safety | Not affected (main actor only). |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | Pass: none added. |
| X Evidence-based quality | Pass: unit and simulator UI tests; device VoiceOver pass is a `{device}` task. |
| Privacy | Pass: announcements are spoken locally; nothing stored or sent. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/082-acc-004-voiceover-scene-browser/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/accessibility-tree.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/AccessibilityAnnouncer.swift        (new)
├── Coordinators/AppCoordinator.swift                (announcer, preset/pause announcements)
├── Coordinators/AppCoordinator+Show.swift           (cue announcements through the announcer)
├── Coordinators/PresetCoordinator.swift             (toggleFavoriteAnnounced)
├── Views/PresetBrowserView.swift                    (PresetRow trait, hint, favorite action)
├── Views/ShowEditorView.swift                       (selected trait, Move Up/Down actions)
├── Views/ControlsOverlay.swift                      (hints)
├── Views/VisualizerView.swift                       (blackout/recording announcements, probe)
├── Tests/AccessibilityAnnouncerTests.swift          (new)
└── UITests/AccessibilityScreensUITests.swift        (new)
```

**Structure Decision**: app target only, matching ACC-001.

## Complexity Tracking

None.
