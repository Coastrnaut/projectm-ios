# Implementation Plan: ACC-011 Captioned Status Events

**Branch**: `feature/acc-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/100-acc-011-captioned-status-events/spec.md`

## Summary

All in the app target; no package changes, no UIStrings changes.

1. **Transition table** (R1, R2): `Apps/projectM-iOS/Coordinators/StatusEvents.swift`.
   - `StatusEvent` (id, kind, visible text, announcement, cause, presentation) and `StatusEventCatalog`,
     whose functions map each status enum to a row with exhaustive switches (no `default:`):
     source (AudioState × hold reason, switching), recording (`VideoRecordingCoordinator.State`,
     `RecordingStopReason`, `RecordingRefusal`, `RecordingFailure`), frame capture notices and ready
     panels, share notices, camera (`CameraFeedState` × position), OSC listener, blackout
     (`OutputBlackout.Phase`), background notice, route, recovery offer, scene reopened, repair report.
   - Texts come from the existing owners (UIStrings via `SourceStatusIndicator`, the FrameRecording
     notices, `CameraFeedState.notice`, `CameraIndicator`, `OSCReceiverCoordinator.badgeText`,
     `AccessibilityAnnouncer` texts); the catalog adds only "Frame ready" / "Recording ready" (the panel
     titles), "OSC off" (OSC-007-R7) and "Camera off" (CAM-012), all already shown or spoken today.
2. **Router** (R3, R4, R7, R10): `StatusEventRouter` (`@MainActor @Observable`, same file) owns the
   ACC-004 `AccessibilityAnnouncer` (`AppCoordinator.announcer` becomes a computed alias, so ACC-004's
   call sites are unchanged). `post(_:)` drops system-caused rows while the app is not active, announces
   through the gate with the row's kind, and for `.caption` rows sets `caption` for 4 s (a newer caption
   replaces it; injectable scheduler). `AnnouncementKind` gains `source, route, background, capture,
   camera, osc, session`.
3. **Wiring** (R3, R5, R6), kept small in shared files:
   - `AppCoordinator+StatusEvents.swift` (new): `announceSourceStatus()` (one text per change: the hold
     text when In-App Playback goes on hold, else the indicator text), router setup (`isActive`, route and
     repair announce closures).
   - `VisualizerView`: the source, blackout-phase, recording-state, recording-notice, frame-notice,
     ready-panel and share-notice `.onChange`s post catalog rows; `StatusCaptionView` in the top status
     stack.
   - `AppCoordinator`: camera stop/notice posts and "Last scene reopened." go to the router; camera on is
     announced when the badge appears.
   - `RootView` (ProjectMApp.swift): `.onChange(of: osc.badgePort)` for "OSC listening on port N"; the
     chooser shows `StatusCaptionView` too.
   - `OSCListenerBadge`, `BackgroundNoticeView`, `SessionRecoveryOfferCard` take an announce closure in
     place of their direct posts; `RouteCoordinator` and `SceneRepairCoordinator` get a settable announce
     closure (default no-op) that the app points at the router. `SourceStatusIndicator.announce` is
     removed.
4. **Checks** (R11, S1-S4): `StatusEventsTests` (unit: table walk with a fake clock and sink, rate
   rule, background suppression, captions, completeness over every enum case);
   `scripts/check_status_events.py` (no direct posts in the files of contract C2) run by
   `scripts/test_scripts.py`; `StatusEventsUITests` (source waiting → active → interrupted with hold,
   blackout → restored with caption) reading `announcementProbe` and `statusCaption`.

## Technical Context

**Language/Version**: Swift 6.4.2, Xcode 27.2 (27B52), iOS 26 minimum, iOS SDK 27.2
**Primary Dependencies**: SwiftUI, UIKit (`UIAccessibility.post` only inside `AccessibilityAnnouncer`)
**Storage**: none (nothing stored)
**Testing**: XCTest unit tests in projectM-iOSTests, XCUITest, Python script tests
**Target Platform**: iPhone and iPad
**Project Type**: mobile app (XcodeGen `project.yml`)
**Performance Goals**: no per-frame work; posts happen on state changes only
**Constraints**: owner rule 7 budgets (unit ≤ 10 s, UI test < 30 s); typed string building (no `+`
chains with ternaries in modifiers); no animation for captions (ACC-001 MotionPolicy not needed)
**Scale/Scope**: ~20 statuses, ~70 table rows over all enum cases

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs only | Pass: `UIAccessibility.post(notification:argument:)` and SwiftUI only |
| IV Truthful source labeling | Pass: announcements reuse the indicator's FR-010/FR-042 text verbatim |
| VI Modular boundaries | Pass: app target only; packages untouched |
| VII Real-time audio safety | Pass: main-actor UI state only; nothing on the audio thread |
| X Evidence-based quality | Pass: unit and UI tests on the simulator; the VoiceOver pass is `{device}` and left open |
| Privacy | Pass: nothing stored or sent; announcements stay on the device |

No violations; no ADR needed (no constitution default is overridden). Re-checked after design: unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/100-acc-011-captioned-status-events/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/status-events.md   # C1 transition table, C2 checked files, C3 probes
└── checklists/requirements.md
```

### Source Code (repository root)

```text
Apps/projectM-iOS/
├── Coordinators/StatusEvents.swift               # new: catalog, router
├── Coordinators/AppCoordinator+StatusEvents.swift # new: source status, router wiring
├── Coordinators/AccessibilityAnnouncer.swift      # kinds added
├── Coordinators/AppCoordinator.swift              # camera, recovery posts; announcer alias
├── Coordinators/RouteCoordinator.swift, SceneRepairCoordinator.swift   # settable announce
├── Views/StatusCaptionView.swift                  # new
├── Views/VisualizerView.swift, ProjectMApp.swift  # onChange wiring, caption placement
├── Views/SourceStatusIndicator.swift, OSCListenerBadge.swift, BackgroundNoticeView.swift,
│   SessionRecoveryOfferCard.swift                 # direct posts removed
├── Tests/StatusEventsTests.swift                  # new
└── UITests/StatusEventsUITests.swift              # new
scripts/check_status_events.py                     # new, run by test_scripts.py
```

## Complexity Tracking

None.
