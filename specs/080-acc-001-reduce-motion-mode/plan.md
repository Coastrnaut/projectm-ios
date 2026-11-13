# Implementation Plan: ACC-001 Reduce Motion Mode

**Branch**: `feature/acc-001` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/080-acc-001-reduce-motion-mode/spec.md`

## Summary

One small value type and its wiring, all in the app target:

1. **`MotionPolicy`** (`Apps/projectM-iOS/Views/MotionPolicy.swift`): `reduceMotion: Bool`;
   `decoration(_ animation: Animation) -> Animation?` returns nil while Reduce Motion is on;
   `seconds(_:)` returns 0 while on; the named decorative transition `controls` (0.2 s ease-in-out,
   inventory A1-A3) exposes `controlsAnimation` and `controlsSeconds`. `MotionPolicy.safetyFade(_:)`
   returns its animation unchanged and documents that safety fades are outside the policy. A
   `View.reduceMotionAware(_:value:policy:)` modifier applies `decoration` through `.animation`.
2. **Source of truth**: `AppSettings.systemReduceMotion` (already exists for FR-072).
   `AppCoordinator.motion` derives a `MotionPolicy` from it, so SwiftUI re-renders as soon as it
   changes. The `reduceMotionStatusDidChangeNotification` observer moves from `VisualizerView` to the
   app root (every screen), and `sceneBecame(active: true)` re-reads the setting (R3).
   `AppCoordinator.currentSystemReduceMotion()` reads `UIAccessibility.isReduceMotionEnabled`, or in
   DEBUG the `-uitestReduceMotion YES|NO` override.
3. **Views**: `VisualizerView`'s overlay stack replaces `.animation(.easeInOut(duration: 0.2), value:
   controlsVisible)` with `.reduceMotionAware(coordinator.motion.controlsAnimation, value:
   controlsVisible, …)`. The `.transition(.opacity)` badges (A2, A3) follow automatically: a
   transition animates only inside an animated transaction. `RenderPlaceholderView` (A4) wraps its
   fade in `MotionPolicy.safetyFade`.
4. **DEBUG probe** (R9, `-uitestDiagnostics`): `motionProbe` = `"reduce=<on|off> controls=<seconds>"`,
   where seconds is the duration the controls transition last used (recorded when `controlsVisible`
   changes, from the same policy the view uses). A hidden button `simulateReduceMotionToggle`
   (only with `-uitestReduceMotion`) flips the DEBUG override and calls the same handler the system
   notification calls.
5. **Static check** (R7): `scripts/check_motion_policy.py` scans `Apps/projectM-iOS/**/*.swift`
   (tests excluded) for `withAnimation(` and `.animation(` outside `MotionPolicy.swift`, except lines
   that go through `MotionPolicy.safetyFade(`. Tests in `scripts/test_scripts.py` (fixtures in
   memory plus the real tree), so CI's script-test step enforces it.

No ADR: no default is overridden (Reduce flashing keeps its rule; system presentations unchanged).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the Mac; Xcode 26 in CI: explicit closure types, no C
stdio globals); Python 3 for the check.

**Primary Dependencies**: SwiftUI, UIKit (`UIAccessibility`), Observation. No new package or
dependency.

**Storage**: none (the system setting is read, never stored).

**Testing**: `projectM-iOSTests` (new `MotionPolicyTests`, about 1 s), new UI test
`ReduceMotionUITests` (< 30 s), regression UI suites `NativeVisualUITests`, `SettingsUITests`,
`EmergencyBlackoutUITests`, `GuidedFirstSceneUITests` on an own iOS 27.2 simulator; `python3
scripts/test_scripts.py`. No wall-clock assertions: the probe reports configured durations.

**Target Platform**: iOS 26+ (app).

**Project Type**: mobile app.

**Performance Goals**: none new; a Bool read per render of the overlay stack.

**Constraints**: public APIs only; DEBUG-only probe and override (absent from Release); no
main-actor mutation in setUp/tearDown.

**Scale/Scope**: one decorative transition group (A1-A3), one safety fade in SwiftUI (A4).

## Constitution Check

| Principle | Status |
|---|---|
| I Public Apple APIs only | Pass: `UIAccessibility.isReduceMotionEnabled`, `reduceMotionStatusDidChangeNotification`, SwiftUI `Animation`. |
| II-V Capture | Not affected; no capture claim. |
| VI Modular boundaries | Pass: UI policy stays in the app target (SwiftUI `Animation` is not Linux-portable; the rule itself is a two-line Bool decision). |
| VII Real-time audio safety | Not affected (main actor, UI only). |
| VIII Upstream fidelity | Not affected. |
| IX Pinned dependencies | Pass: no new dependency. |
| X Evidence-based quality | Pass: unit, UI and script tests; simulator only; the device check is a `{device}` task. |
| Privacy / safety (FR-072, FX-019) | Pass: safety fades unchanged (R4); nothing stored or sent. |

Post-design re-check: unchanged (Pass).

## Project Structure

### Documentation (this feature)

```text
specs/080-acc-001-reduce-motion-mode/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── contracts/motion-policy.md
└── checklists/requirements.md
```

### Source Code

```text
Apps/projectM-iOS/Views/MotionPolicy.swift          (new)
Apps/projectM-iOS/Views/VisualizerView.swift        (overlay animation, observer moved, DEBUG probe)
Apps/projectM-iOS/ProjectMApp.swift                 (root observer)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift (motion, re-read on activation, DEBUG override)
Apps/projectM-iOS/Visuals/RenderPlaceholder.swift   (safetyFade marker)
Apps/projectM-iOS/Tests/MotionPolicyTests.swift     (new)
Apps/projectM-iOS/UITests/ReduceMotionUITests.swift (new)
scripts/check_motion_policy.py                      (new)
scripts/test_scripts.py                             (new test class)
```

## Complexity Tracking

None.
