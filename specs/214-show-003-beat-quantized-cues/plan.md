# Implementation Plan: SHOW-003 Beat-Quantized Cue Advance

**Branch**: `feature/show-003` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/214-show-003-beat-quantized-cues/spec.md`

## Summary

An opt-in "Quantize cue steps" setting (Off, Beat, Bar) holds a cue step request (Next, Previous, Go to a cue) until
the first beat or bar boundary strictly after the request and then runs it once through SHOW-001's unchanged step
path.

- **PerformanceControl** (pure Swift, Linux-tested): `QuantizedCueStep` — one pending request with its deadline,
  `request(_:at:tempo:timed:)` (queue, replace, cancel on repeat, keep for a timed advance, or apply now with the
  MOD-017 `QuantizeImmediateReason`), `takeDue(at:)` (exactly once by removal), `cancel()`, `setMode(_:)`. It reuses
  MOD-017's `QuantizeMode`, `QuantizeImmediateReason` and `TempoSnapshot.nextBoundary(after:beats:)`; no clock is read.
- **App**: `ShowCueQuantizer` (main actor, observable; owned by `AppSettings` like MOD-017's `ParameterQuantizer`) owns
  the pure model, the mode (UserDefaults `settings.show.quantizeCues`), the injected clock and tempo, one wake-up task
  per deadline, and the cue-lane announcements. `ShowCoordinator.next/previous/go(to:)` ask it first
  (`cueQuantizer`, nil in SHOW-001's own tests = immediate); a queued request returns the new `ShowStepOutcome.queued`.
  At the boundary it calls MOD-017's `tick(at:)` first (`willStep`), then `ShowCoordinator.stepNow(_:)`, the old
  `perform` path, so MOD-017's cue-mode queue still applies right after the scene. SHOW-002's driver calls
  `show.timedNext()` (a non-cancelling request). Settings › Show gets a picker; the controls row and the performance
  pad show "Cue queued for the next beat|bar".

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new (the app links PerformanceControl and ShowControl already).

**Storage**: one UserDefaults key `settings.show.quantizeCues` (raw value; absent = Off): `AppSettings.allKeys`
(UI-test reset), FILE-005 `excludedKeys`, FILE-011 erase list, `ALLOWED_KEYS`.

**Testing**: XCTest. PerformanceControl on the host; app unit tests and one UI test on the private simulator
"SHOW3 iPhone 17" (iOS 27.2). Synthetic tempo snapshots and an injected clock; wake-ups off in unit tests.

**Target Platform**: iOS/iPadOS 26+; package also macOS 15 and Linux.

**Performance Goals**: one wake-up per queued step; nothing runs while nothing is queued.

**Constraints**: exactly-once application; type-check budget (explicit closure types); small edits to shared files
(`AppCoordinator`, `SettingsView`).

**Scale/Scope**: at most one queued step.

## Constitution Check

- I Public APIs only: Foundation, Observation, SwiftUI. Pass.
- VI Modular boundaries: the boundary model lives in PerformanceControl next to MOD-017's queue; ShowControl stays
  free of tempo types (only a new outcome case). Nothing reaches projectM. Pass.
- VII Real-time audio safety: main actor only; no audio callback touched. Pass.
- VIII Upstream fidelity: no new beat analysis; SHOW-011/ANL-005's grid is reused. Pass.
- X Evidence-based quality: deterministic unit tests with synthetic beats; no device claim. Pass.

Post-design re-check: unchanged, pass. No ADR: no constitution default is overridden.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/QuantizedCueStep.swift                    (new)
Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedCueStepTests.swift            (new)
Packages/ShowControl/Sources/ShowControl/ShowCueList.swift          (ShowStepOutcome.queued)
Apps/projectM-iOS/Coordinators/ShowCueQuantizer.swift                                             (new)
Apps/projectM-iOS/Coordinators/ShowCoordinator.swift                (gate in next/previous/go, stepNow, timedNext)
Apps/projectM-iOS/Coordinators/ShowAutoAdvanceCoordinator.swift     (timedNext)
Apps/projectM-iOS/Coordinators/AppSettings.swift                    (property, allKeys)
Apps/projectM-iOS/Coordinators/AppCoordinator+ParameterQuantizer.swift (connect)
Apps/projectM-iOS/Views/QuantizeCueStepsSection.swift                                             (new)
Apps/projectM-iOS/Views/SettingsView.swift, ShowControls.swift, PerformancePad.swift              (small)
Apps/projectM-iOS/Tests/ShowCueQuantizerAcceptanceTests.swift                                     (new)
Apps/projectM-iOS/UITests/QuantizedCueStepsUITests.swift                                          (new)
scripts/run_device_tests.py, Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift and LibraryErasePolicy.swift
```

**Structure Decision**: a dedicated single-slot model instead of instantiating `QuantizedChangeQueue` (research
SHOW-003-D1); its timing helpers and enums are reused, not copied.
