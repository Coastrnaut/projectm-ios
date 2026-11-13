# Implementation Plan: UIX-001 Guided First Scene

**Branch**: `feature/uix-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

## Summary

A five-step, full-screen, unanimated tutorial (Welcome → Sound → Visual → Look → Play) offered once
after the photosensitivity notice on a fresh install. A pure flow type holds the step and the draft
choices; a small coordinator stores one UserDefaults value (`guide.firstScene`: `pending`,
`finished`, `skipped`; absent = never offered), decides whether to offer it at launch (not while the
PERF-010 offer is pending, not in DEBUG harness launches unless `-uitestGuidedFirstScene`), and is
re-opened from a Settings row. Play applies the visual and look through the existing settings path
(`AppSettings`, `TextOverlayCoordinator`), commits the scene at once (SCN-002 `commitNow()`), and
starts In-App Playback with the built-in reference track only when nothing plays (the chooser's own
`select(.inAppPlayback)` path). Nothing touches networking, OSC, the camera, the microphone or any
picker. All code is in the app target; no package changes.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac Studio; CI also builds with Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI, Observation; no new dependency
**Storage**: one key in the app's UserDefaults, `guide.firstScene` (string)
**Testing**: XCTest app unit tests (flow, store, launch rule, apply; in-memory defaults suites),
one XCUITest suite `GuidedFirstSceneUITests` on an iOS 27.2 simulator (acceptance, skip, largest
text size)
**Target Platform**: iOS/iPadOS 26.5+
**Project Type**: mobile app (XcodeGen `project.yml`; new files are picked up by the folder globs)
**Performance Goals**: no launch cost beyond one defaults read
**Constraints**: public APIs only; no networking; explicit closure types, no long untyped numeric
expressions (Linux/Xcode 26 type checker); no main-actor mutation in test setUp/tearDown; no
wall-clock assertions; unit tests about 1 s, each UI test under 30 s (owner rule 7)
**Scale/Scope**: 4 new Swift files (flow + coordinator, view, AppCoordinator extension, tests) and 1
UI test file; small edits to AppCoordinator (one stored property, reset, notice hook), RootView,
VisualizerView (Settings closure), SettingsView (one row)

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: SwiftUI, UserDefaults. |
| VI. Modular boundaries | Pass: the flow type has no UI imports; the view only calls the coordinator. |
| VII. Real-time audio safety | Pass: nothing on audio threads; the source starts through the existing path. |
| X. Evidence-based quality | Pass: unit tests for the deterministic flow; simulator UI tests are not device evidence; the D1 Airplane Mode and VoiceOver pass is `{device}` task T14. |
| Privacy: capture only after explicit user action; permission at point of use | Pass: the tutorial offers only In-App Playback (no input, no permission); Microphone, capture and Camera are only named. No permission request is made (UIX-015 owns explainers). |
| Security: no network in capture/audio path | Pass: no networking code; OSC keeps its stored off-by-default setting. |
| Privacy policy accurate | Pass after T12: the stored value is listed. |

No violations; no default overridden, so no ADR. No complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/075-uix-001-guided-first-scene/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/guided-first-scene.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Coordinators/
├── GuidedFirstScene.swift              # pure flow + stored state + launch rule + coordinator (new)
├── AppCoordinator+Guide.swift          # finish (apply, commit, start), open from Settings (new)
└── AppCoordinator.swift                # `guide` property, reset, offer after the notice
Apps/projectM-iOS/Views/
├── GuidedFirstSceneView.swift          # the five steps (new)
├── SettingsView.swift                  # "Guided first scene" row
└── VisualizerView.swift                # passes the row's action to Settings
Apps/projectM-iOS/ProjectMApp.swift     # RootView overlay
Apps/projectM-iOS/Tests/GuidedFirstSceneTests.swift        # unit (new)
Apps/projectM-iOS/UITests/GuidedFirstSceneUITests.swift    # acceptance UI tests (new)
docs/privacy-policy.md                                     # the stored value
```

**Structure Decision**: app-target only (Play depends on AppSettings, TextOverlayCoordinator,
SCN-002's coordinator and the source start path, all in the app target).

## Complexity Tracking

None.
