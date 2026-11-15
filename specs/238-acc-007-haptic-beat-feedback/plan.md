# Implementation Plan: ACC-007 Haptic Beat Feedback

**Branch**: `feature/acc-007` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

An opt-in Settings switch turns on short haptic pulses on confident beats, every fourth beat or kicks. The
decision per event is a pure, Linux-tested `HapticPulseGate` in PerformanceControl (choice filter, downbeat
count, stale drop, 150 ms / 4 per s / 180 per 60 s limits on the bus clock); `HapticCue` maps ANL-016 events
in PerformanceControlAnalysis. In the app, `HapticBeatCoordinator` stores the three preferences, installs an
event observer on SHOW-011's `TempoCoordinator` only while on (which then polls every 40 ms), checks the
conditions (app active, Low Power Mode off, hardware haptics, ACC-012 intensity limit) and plays through a
`HapticPlaying` protocol whose real implementation is `UIImpactFeedbackGenerator`.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: PerformanceControl (+ Analysis target), AnalysisFeatures, FlashSafety, UIKit, CoreHaptics (capability query only)
**Storage**: three UserDefaults keys `settings.haptics.beatPulses` (Bool), `settings.haptics.beatEvent` (String), `settings.haptics.strength` (String)
**Testing**: PerformanceControl package tests (host, Linux-safe), app unit tests (`projectM-iOSTests`), one XCUITest; private simulator "ACC7 iPhone 17" (iOS 27.2)
**Target Platform**: iOS/iPadOS 26.5+ (haptics on iPhone only)
**Project Type**: mobile app (XcodeGen `project.yml`) + SwiftPM packages
**Performance Goals**: off: zero cost; on: one 40 ms main-actor poll (already draining the same events) and one gate decision per event (a few comparisons, no allocation)
**Constraints**: type-check budget (300 ms per body, 200 ms per expression); unit test ≤ 10 s, package suite < 1 min, UI test < 30 s
**Scale/Scope**: 2 package files, 3 app files, 3 test files, small edits to TempoCoordinator, TempoAnalyzer, AppCoordinator, VisualizerView, SettingsView, SensorySafetySection and the key lists

## Constitution Check

| Principle | Status |
|---|---|
| I Public APIs | Pass: `UIImpactFeedbackGenerator`, `CHHapticEngine.capabilitiesForHardware()`, `ProcessInfo.isLowPowerModeEnabled`. |
| VI Modular boundaries | Pass: the gate knows no UIKit; the player is a protocol; analysis is read through the existing tempo subscription. |
| VII Real-time audio safety | Pass: events are drained on the main actor by the existing poll; nothing on the worker or audio threads. |
| VIII Upstream fidelity | Pass: no new analysis; ANL-005/007 events are reused. |
| X Evidence | Unit tests with an injected clock and a fake player; the felt pulses on D1 are a `{device}` task. |
| Privacy | Pass: three local preferences, backed up and erased with Settings; no network, no permission. |

Post-design re-check: unchanged, all pass. No ADR needed (no constitution default overridden; ACC-012-R9's
"no haptics" note is amended in its spec by `ACC-007-R10`).

## Project Structure

```text
specs/238-acc-007-haptic-beat-feedback/  spec, plan, research, data-model, contracts/haptic-beat.md, quickstart, tasks
Packages/PerformanceControl/Sources/PerformanceControl/HapticPulseGate.swift            gate, rules, choices (new)
Packages/PerformanceControl/Sources/PerformanceControlAnalysis/HapticCue+Analysis.swift  event mapping (new)
Packages/PerformanceControl/Sources/PerformanceControlAnalysis/TempoAnalyzer.swift       poll(onEvent:)
Packages/PerformanceControl/Tests/PerformanceControlTests/HapticPulseGateTests.swift    (new)
Apps/projectM-iOS/Coordinators/HapticBeatCoordinator.swift   setting + conditions + player (new)
Apps/projectM-iOS/Coordinators/HapticPlayer.swift            HapticPlaying + UIKit player (new)
Apps/projectM-iOS/Views/HapticBeatSection.swift              Settings section (new)
Apps/projectM-iOS/Coordinators/TempoCoordinator.swift        event observer, 40 ms poll while set
Apps/projectM-iOS/Coordinators/AppCoordinator.swift          one lazy property, attach at init
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift, SensorySafetySection.swift  one row each / footer
Apps/projectM-iOS/Tests/HapticBeatAcceptanceTests.swift      acceptance (new)
Apps/projectM-iOS/UITests/HapticBeatUITests.swift            toggle (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift, Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift  key lists
```

**Structure Decision**: pure logic in the existing PerformanceControl package (already Linux-tested, already
owns tempo and quantize timing); no new package, so CI's package groups are unchanged.
