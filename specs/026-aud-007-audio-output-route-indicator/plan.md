# Implementation Plan: AUD-007 Audio output route indicator

**Branch**: `feature/aud-007` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/026-aud-007-audio-output-route-indicator/spec.md`

## Summary

Show which audio route the active local source uses (In-App Playback: outputs; Microphone: inputs)
in a compact, accessible indicator in the visualizer controls, and explain each change for about
4 seconds ("Now playing through Headphones", "Headphones disconnected — paused"). The route is a
typed, platform-neutral model in CaptureKit, read through a replaceable provider and refreshed from
the audio session's route-change notification. The explanation logic is pure and tested on the
host (and Linux); the strings and the indicator view live in CaptureUI; the app layer only wires the
monitor to the coordinator and the views. AUD-014's pause on a lost output is untouched; the one
decision both features need (which route-change reason pauses playback) moves into a single shared
definition.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), Xcode 27.2 / iOS SDK 27.2

**Primary Dependencies**: AVFAudio (`AVAudioSession.currentRoute`, `routeChangeNotification`),
SwiftUI, Observation; existing packages CaptureKit, CaptureUI, AudioCore. No new dependency.

**Storage**: None. The route lives in memory only (AUD-007-R14); nothing persisted, nothing exported.

**Testing**: XCTest. CaptureKit and CaptureUI on the macOS host (pure parts also with
`-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`, the Linux path) and on the iOS 27.2 simulator (iOS-only parts:
port-constant mapping, the notification observer with a private center). App unit tests for the
route coordinator; one UI test with a Debug launch hook (`-uitestFakeRoutes`).

**Target Platform**: iOS/iPadOS 26.0+ (app), macOS 15 host and Linux for package tests.

**Project Type**: Mobile app with Swift packages.

**Performance Goals**: The indicator updates within 1 second of iOS's notification (AUD-007-S5);
the work per change is reading a handful of ports on the main actor.

**Constraints**: Nothing on the audio callback (Constitution VII); no wall-clock assertions in tests;
each test about 1-2 s, the UI test under 30 s (owner rule 7).

**Scale/Scope**: About 4 new source files in packages, 3 small app files, edits to 4 existing files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Public Apple APIs only | `AVAudioSession.currentRoute`, `AVAudioSessionPortDescription.portType/portName`, `routeChangeNotification` with `AVAudioSessionRouteChangeReasonKey`: all public | Pass |
| II/III. Capture feasibility, ScreenCaptureKit strategy | Not touched; no capture path changes | Pass |
| IV. Truthful source labeling | The indicator never names a source mode, never says "capture", never names an app, and is not shown for System/App Capture (AUD-007-R4, R11); the source-and-state indicator is unchanged | Pass |
| V. No universal-capture claims | No compatibility wording added | Pass |
| VI. Modular boundaries | AVFAudio types stay in CaptureKit; CaptureUI and the app see only `AudioRoute` | Pass |
| VII. Real-time audio safety | Route handling runs on the main actor from notifications; no change to any render or tap callback | Pass |
| VIII/IX. Upstream fidelity, pinned dependencies | No engine or dependency change | Pass |
| X. Evidence-based quality | Unit and UI tests are simulator/host evidence only; the plug/unplug acceptance is a `{device}` task | Pass |
| Privacy | No permission, entitlement, network or storage; device names stay in memory | Pass |

Post-design re-check (after Phase 1): unchanged, all pass.

## Project Structure

### Documentation (this feature)

```text
specs/026-aud-007-audio-output-route-indicator/
├── spec.md
├── plan.md              # this file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── route-model.md   # model, change summary, shared pause rule
│   └── ui-strings.md    # every text, its accessibility label and announcement
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Packages/CaptureKit/Sources/CaptureKit/Route/
├── AudioRoute.swift            # RoutePortKind, RoutePort, AudioRoute, AudioRouteChangeReason,
│                               # AudioRouteChange, AudioRouteContext, change summary (pure)
├── AudioRouteMonitor.swift     # AudioRouteProviding protocol, AudioRouteMonitor (@MainActor, pure)
└── SystemAudioRoute.swift      # iOS only: SystemAudioRouteProvider, AudioRouteObserver
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/AudioSessionSignal.swift   # uses the shared pause rule
Packages/CaptureKit/Tests/CaptureKitTests/
├── AudioRouteTests.swift       # mapping, reasons, summaries, context (host + Linux)
├── AudioRouteMonitorTests.swift# monitor sequences with a fake provider (host + Linux)
└── SystemAudioRouteTests.swift # iOS only: port constants, observer, AUD-014 agreement
Packages/CaptureUI/Sources/CaptureUI/
├── UIStrings.swift             # + route strings (one MARK section)
└── AudioRouteIndicator.swift   # the compact indicator view
Packages/CaptureUI/Tests/CaptureUITests/RouteStringsTests.swift
Apps/projectM-iOS/Coordinators/RouteCoordinator.swift      # monitor + explanation + announcement
Apps/projectM-iOS/Coordinators/AppCoordinator.swift        # + `routes` (two lines)
Apps/projectM-iOS/Views/ControlsOverlay.swift              # + the indicator next to the source indicator
Apps/projectM-iOS/Views/VisualizerView.swift               # + explanation capsule, refresh on source change
Apps/projectM-iOS/Debug/UITestRoutePanel.swift             # DEBUG: fake provider and route buttons
Apps/projectM-iOS/Tests/RouteCoordinatorTests.swift
Apps/projectM-iOS/UITests/RouteIndicatorUITests.swift
```

**Structure Decision**: Extend CaptureKit (where AUD-014's session handling already lives) and
CaptureUI (where the shared strings and status views live). `project.yml` needs no edit if the app's
targets take their sources by folder (checked in implementation; otherwise one line per new file).

## Persistence and rollback

Nothing is stored, so there is no migration and no data to roll back. Rollback is reverting the
feature's commits; the only change to existing behavior code is `AudioSessionSignal.parse` reading
the shared pause rule, which is behavior-identical (proved by a test over every reason) and reverts
cleanly on its own.

## Test design (deterministic, short)

- Pure functions over values: no timers, no clocks, no audio hardware. The 4-second explanation
  lifetime is a `Task.sleep` in the app coordinator and is never asserted.
- The monitor takes a provider protocol; tests set the fake's route and call `routeDidChange(reason:)`.
- The iOS observer takes its NotificationCenter and notification object, so simulator tests post to a
  private center (the pattern of `AudioSessionObserver`, AUD-014).
- The UI test injects routes with `-uitestFakeRoutes` and posts the real route-change notification
  through Debug-only buttons, so AUD-014's real backend pauses as it would on a device.

## Complexity Tracking

None: no constitution violation to justify.
