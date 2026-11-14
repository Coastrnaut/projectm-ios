# Implementation Plan: PERF-008 Battery saver profile

**Branch**: `feature/perf-008` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/201-perf-008-battery-saver/spec.md`

## Summary

`PowerProfile` and `PowerBudget` (Packages/Rendering, next to `QualityGovernor`) give each profile a frame-rate
cap, a render-scale cap and a background-warm-up flag. `QualityGovernor.settings(…, budget:)` takes the per-value
minimum of today's thermal/Low Power result and the budget (30 fps floor kept); the existing overloads keep
Standard, so FR-049 and PERF-003 are unchanged. A process-wide, lock-protected `PowerProfileState` holds the active
profile for `QualityGovernor.current()` and posts `PowerProfileState.didChangeNotification` on change; every frame
loop already re-reads `current()` on the thermal and power-state notifications and now also on this one
(`QualityGovernor.changeNotifications`). The app's `PowerProfileSetting` (UserDefaults
`settings.performance.powerProfile`) writes the state and emits an os_signpost event. PERF-005's
`MediaPrewarmCoordinator` keeps only the next cue and the SC-104 preset warm-up is skipped when the budget
disallows background warm-up. REC-006's render limit gains the reason `batterySaver`. Settings → Performance gets
three rows; the overlay gets a `power …` line. Nothing references `CaptureManager`.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2; CI also Xcode 26)
**Primary Dependencies**: Foundation, QuartzCore (`CAFrameRateRange`), os (`OSSignposter` via Diagnostics)
**Storage**: one UserDefaults String, `settings.performance.powerProfile` (absent → Standard)
**Testing**: XCTest: RenderingTests `PowerProfileTests` (budgets, governor composition; host and iOS simulator);
Compositor `RecordingFrameRate` reason text; app unit tests `PowerProfileAppTests` (acceptance: budgets change,
capture state and configuration identical, prewarm budget, native host quality, recording limit, persistence);
one UI test `PowerProfileUITests` (pick Battery saver, survives relaunch) on simulator "PERF8 iPhone 17"
**Target Platform**: iOS/iPadOS 26+
**Project Type**: mobile app + SwiftPM packages
**Performance Goals**: no per-frame cost: the state is read only when a notification arrives or a loop starts
**Constraints**: profile never touches audio; governor never above the profile cap; no network
**Scale/Scope**: 3 profiles, 7 frame-loop consumers, 1 setting

## Constitution Check

| Principle | Check |
|---|---|
| I. Public Apple APIs only | `ProcessInfo`, `NotificationCenter`, `OSSignposter`, `CADisplayLink.preferredFrameRateRange`. Pass. |
| VI. Modular boundaries | Budgets live in Rendering beside the governor; the app wires UI and prewarm; CaptureKit untouched. Pass. |
| VII. Real-time audio safety | No audio-path code changes; the state lock is only taken on the main thread at notification time. Pass. |
| X. Evidence-based quality | Unit tests for deterministic budgets; energy/frame-time claim left to D1 (`{device}` T-task). Pass. |
| Privacy | The signpost carries only the profile name; no user content. Pass. |

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/Rendering/Sources/Rendering/PowerProfile.swift        # PowerProfile, PowerBudget, PowerProfileState
Packages/Rendering/Sources/Rendering/QualityGovernor.swift      # budget composition, changeNotifications
Packages/Rendering/Sources/Rendering/GLESRenderer.swift         # observe the profile notification
Packages/ANGLERendering/Sources/ANGLERendering/ANGLERenderer.swift
Packages/Rendering/Tests/RenderingTests/PowerProfileTests.swift
Packages/Compositor/Sources/FrameRecording/RecordingFrameRate.swift   # Reason.batterySaver
Packages/Diagnostics/Sources/Diagnostics/Logging.swift          # powerProfile signpost event
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift   # includedKeys
Apps/projectM-iOS/Coordinators/PowerProfileSetting.swift
Apps/projectM-iOS/Views/PowerProfileSection.swift
Apps/projectM-iOS/Coordinators/{MediaPrewarmCoordinator,RecordingQualitySetting,AppCoordinator,AppCoordinator+FrameStages}.swift
Apps/projectM-iOS/Visuals/{NativeSpectrumHost(+EffectQuality),Photo,Text,Video,CameraVisualHost}.swift
Apps/projectM-iOS/Views/{SettingsView,VisualizerView}.swift (small)
Apps/projectM-iOS/Tests/PowerProfileAppTests.swift, UITests/PowerProfileUITests.swift
scripts/run_device_tests.py (ALLOWED_KEYS)
```

## Complexity Tracking

None.
