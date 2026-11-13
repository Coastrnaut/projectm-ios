# Implementation Plan: PERF-010 Crash-Safe Session Recovery

**Branch**: `feature/perf-010` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

## Summary

Tell a clean exit from an abnormal one with a "session open" flag in the app's preferences, and act
on it before anything starts at launch: after an abnormal exit the stored OSC toggle is turned off
before the receiver is created (so no listener opens), SCN-002's restore is held instead of applied
(the scene settings are put at their defaults), and a non-blocking card offers **Reopen last scene**
or **Start fresh**. A crash within two sessions of a Reopen offers Start fresh only. The camera
already never starts by itself (CAM-001-R11); tests prove it stays so after an abnormal exit. All
code is in the app target; no package changes.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac Studio; CI also builds with Xcode 26)
**Primary Dependencies**: Foundation, SwiftUI, UIKit (lifecycle notifications); no new dependency
**Storage**: three keys in the app's UserDefaults (`session.recovery.open`,
`session.recovery.sessionsSinceReopen`, `session.recovery.heldVisual`)
**Testing**: XCTest app unit tests (pure state machine and launch policy with an in-memory defaults
suite), one XCUITest suite on the iOS 27.2 simulator
**Target Platform**: iOS/iPadOS 26.5+
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no measurable launch cost (a few defaults reads and writes)
**Constraints**: public APIs only; no networking; no file timestamps; no main-actor mutation in
test setUp/tearDown; explicit closure types and no long untyped numeric expressions (Linux/Xcode 26)
**Scale/Scope**: ~4 new Swift files, small edits to AppCoordinator, AppSettings readers, OSC
coordinator call order, VisualizerView, the chooser

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: UserDefaults, NotificationCenter UIApplication notifications. No MetricKit, no signal handlers, no private API. |
| VI. Modular boundaries | Pass: app-target coordinator; the pure decision type has no UI imports. |
| VII. Real-time audio safety | Pass: nothing on audio threads. |
| X. Evidence-based quality | Pass: simulator UI test is not device evidence; the D1 real-crash check is `{device}` task T15. |
| Privacy (capture and network only after explicit user action) | Strengthened: the network listener is never reopened after an abnormal exit without the user turning it on; the camera stays session only. |
| FR-068 / ADR-0008 OSC ruling (off until enabled) | Strengthened; the change to OSC-001-R15 persistence is recorded in an ADR. |

No violations; no complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/070-perf-010-crash-safe-session-recovery/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/session-recovery.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Coordinators/
├── SessionRecoveryPolicy.swift        # pure: SessionRecord, LaunchDecision, transitions (new)
├── SessionRecoveryCoordinator.swift   # defaults store, lifecycle observers, offer state, probe (new)
└── AppCoordinator.swift               # launch order: decide → OSC off → hold/apply scene → OSC created
Apps/projectM-iOS/Views/
├── SessionRecoveryOfferCard.swift     # the card (new)
└── VisualizerView.swift               # card in the top stack; DEBUG probe
Apps/projectM-iOS/ProjectMApp.swift    # card on the chooser
Apps/projectM-iOS/Tests/SessionRecoveryTests.swift      # unit (new)
Apps/projectM-iOS/UITests/SessionRecoveryUITests.swift  # acceptance UI test (new)
docs/adr/00NN-crash-recovery-consent.md                 # OSC toggle after an abnormal exit (new)
docs/privacy-policy.md                                  # the three stored values
```

**Structure Decision**: app-target only (the decision depends on AppSettings, SCN-002's coordinator
and the OSC coordinator, all in the app target).

## Complexity Tracking

None.
