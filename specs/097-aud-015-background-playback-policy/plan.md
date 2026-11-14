# Implementation Plan: AUD-015 Background Playback Policy

**Branch**: `feature/aud-015` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/097-aud-015-background-playback-policy/spec.md`

## Summary

One pure decision function, `BackgroundPolicy` (CaptureKit, Linux-testable), says per source what
happens when the app is away (background or locked) and whether it may resume automatically. The
inputs are the source, `isBackgrounded`, `isLocked`, `declaresAudioBackgroundMode` and
`keepPlayingInBackground`; the output is an action (`run`, `pausePlayback`, `stopCapture`,
`continuePlayback`, `followSystem`) and a reason that carries the user-visible notice text.
`CaptureManager.handle(_:)` replaces its single "presentable" flag with two independent flags
(background, locked; entering the foreground clears both, as PERF-011-R1 does), asks the policy on
every lifecycle event, and holds a Microphone or In-App Playback start or resume that completes
while the app is away (research AUD-015-D1, D2). It publishes `backgroundNotice` (the reason) when
it paused or stopped a source while away; the app shows it under the status on return for 8 s
(research AUD-015-D3). The app reads `UIBackgroundModes` from its Info.plist into the policy's
`declaresAudioBackgroundMode` (false in the shipped app) and passes `keepPlayingInBackground =
false` (no setting). Rendering already pauses through LifecycleCoordinator and PERF-011's registry;
tests pin it. ADR-0036 records the policy; the privacy policy gains a "When the app is in the
background" section.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), strict concurrency

**Primary Dependencies**: none new; CaptureKit (AudioCore), the app target (SwiftUI, UIKit)

**Storage**: none (no new setting; nothing persisted)

**Testing**: XCTest in CaptureKit (host and Linux), app unit tests (`projectM-iOSTests`), one
XCUITest (`BackgroundPolicyUITests`)

**Target Platform**: iOS/iPadOS 26.0+ (D1-D3); Linux for the package tests

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: resume on return within 2 s (FR-050, unchanged)

**Constraints**: no new background mode; public APIs only; no networking; owner rule 7 test budgets

**Scale/Scope**: 1 new source file in CaptureKit, edits to CaptureManager, the app coordinator and
the visualizer view; 3 test files; docs

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `Bundle.infoDictionary`, existing UIKit notifications. |
| IV. Truthful source labeling | Pass: the notice names the real source and what happened; states unchanged. |
| VI. Modular boundaries | Pass: policy in CaptureKit (no platform types), UI in the app. |
| VII. Real-time audio safety | Pass: no change in audio callbacks. |
| X. Evidence-based quality | Pass: unit and UI tests; device task AUD-015-T13 stays open. |
| Platform/privacy constraints (background modes documented from the SDK) | Pass: only `screen-capture`, unchanged; compliance check unchanged. |

Post-design re-check: unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/097-aud-015-background-playback-policy/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/background-policy.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/BackgroundPolicy.swift        (new)
Packages/CaptureKit/Sources/CaptureKit/CaptureManager.swift          (lifecycle flags, policy, notice)
Packages/CaptureKit/Tests/CaptureKitTests/BackgroundPolicyTests.swift (new)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                  (policy configuration, notice)
Apps/projectM-iOS/Views/VisualizerView.swift                         (notice view)
Apps/projectM-iOS/Tests/BackgroundPolicyAppTests.swift               (new)
Apps/projectM-iOS/Tests/LifecycleCoordinatorTests.swift              (unlock-in-background fix)
Apps/projectM-iOS/UITests/BackgroundPolicyUITests.swift              (new)
docs/privacy-policy.md, docs/adr/0036-background-playback-policy.md
```

**Structure Decision**: the decision lives next to `InterruptionPolicy` in CaptureKit, because the
manager that enforces it is there and CaptureKit's tests run on Linux.

## Complexity Tracking

None.
