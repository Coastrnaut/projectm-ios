# Implementation Plan: MOD-017 Quantized Parameter Changes

**Branch**: `feature/mod-017` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/206-mod-017-quantized-changes/spec.md`

## Summary

An opt-in quantize mode (Off, Beat, Bar, Cue) holds discrete parameter edits from the inspector, the shelf and
macros in a queue (one entry per parameter, latest wins) and applies each exactly once at its boundary.

- **PerformanceControl** (pure Swift, Linux-tested): `QuantizeMode`, `TempoSnapshot.nextBoundary(after:beats:)`
  (strictly after; reuses SHOW-011's grid) and the generic `QuantizedChangeQueue<Key, Value>` (request, cancel,
  `takeDue(at:)`, `cueStepped()`, `clear()`, `nextDeadline`). No clock is read; every time is an argument.
- **App**: `ParameterQuantizer` (main actor, observable) owns the queue and the mode (UserDefaults
  `settings.modulation.quantize`), reads `TempoCoordinator.snapshot` and the monotonic clock through injected
  closures, wakes once per due boundary (a task sleeping until `nextDeadline`), applies through the SCN-015-guarded
  `ParameterInspectorTargets.target(for:settings:)`, and announces on the `.parameter` lane.
  `ParameterInspectorTargets.quantizedTarget(for:settings:)` wraps discrete targets for the inspector, shelf and
  macros. The show's `applyScene` hook calls `cueApplied()`. A Settings section picks the mode; the inspector and
  shelf show "Queued for the next beat|bar|cue".

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: none new (PerformanceControl already depends on ParameterGraph; the app already links it).

**Storage**: one UserDefaults key `settings.modulation.quantize` (raw value; absent = Off), excluded from library
backups (FILE-005), listed in `ALLOWED_KEYS` and the UI-test reset.

**Testing**: XCTest. PerformanceControl on the host (Linux in CI); app unit tests and one UI test on the private
simulator "MOD17 iPhone 17" (iOS 27.2). Synthetic tempo snapshots and an injected clock; no wall-clock assertions.

**Target Platform**: iOS/iPadOS 26+; package also macOS 15 and Linux.

**Performance Goals**: at most one wake-up per due boundary while the queue is non-empty; nothing runs while it
is empty. At most one entry per parameter (the registry has 7 editable discrete-or-not parameters today).

**Constraints**: exactly-once application; type-check budget (explicit closure types); small edits to shared files.

**Scale/Scope**: a handful of queued entries at most.

## Constitution Check

- I Public APIs only: Foundation, Observation, SwiftUI. Pass.
- VI Modular boundaries: boundary logic in PerformanceControl next to the tempo snapshot it reads; the app only
  wires closures. Nothing reaches projectM. Pass.
- VII Real-time audio safety: main actor only; no audio callback touched. Pass.
- VIII Upstream fidelity: no new beat analysis; ANL-005/SHOW-011's grid is reused. Pass.
- X Evidence-based quality: deterministic unit tests for every boundary kind; no device claim. Pass.

Post-design re-check: unchanged, pass. No ADR: no constitution default is overridden.

## Project Structure

```text
Packages/PerformanceControl/Sources/PerformanceControl/QuantizedChangeQueue.swift                  (new)
Packages/PerformanceControl/Tests/PerformanceControlTests/QuantizedChangeQueueTests.swift          (new)
Apps/projectM-iOS/Coordinators/ParameterQuantizer.swift                                            (new)
Apps/projectM-iOS/Coordinators/AppSettings.swift                (one property)
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             (one connect call)
Apps/projectM-iOS/Coordinators/AppCoordinator+Show.swift        (cue hook)
Apps/projectM-iOS/Coordinators/MacroCoordinator.swift           (quantized target)
Apps/projectM-iOS/Views/QuantizeChangesSection.swift                                                (new)
Apps/projectM-iOS/Views/ParameterInspectorView.swift, ParameterShelfView.swift, SettingsView.swift  (small)
Apps/projectM-iOS/Tests/ParameterQuantizerAcceptanceTests.swift                                    (new)
Apps/projectM-iOS/UITests/QuantizedChangesUITests.swift                                            (new)
scripts/run_device_tests.py, Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, UI-test reset
```

**Structure Decision**: the queue is generic over key and value so the package stays independent of the app's
targets; `ParameterID`/`ParameterValue` are the app's instantiation.
