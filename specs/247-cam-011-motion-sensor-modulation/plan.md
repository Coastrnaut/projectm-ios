# Implementation Plan: CAM-011 Motion Sensor Modulation

**Branch**: `feature/cam-011` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/247-cam-011-motion-sensor-modulation/spec.md`

## Summary

Device attitude (pitch, roll, yaw) and shake become four bindable modulation sources, `audio.motion.<axis>`,
normalized 0…1 around a calibrated neutral.

- **ParameterGraph** (Foundation-free, Linux):
  - `MotionAxis`, `MotionSample`, `MotionRange`, `MotionFeatureValues` and `MotionTracker` (new,
    `MotionTracker.swift`): unwrapping, calibration, range normalization, MOD-005 one-pole smoothing (reused
    `AudioFeatureEnvelope.step`), shake envelope, NaN-safe, no allocation per sample.
  - `AudioFeatureSource.motion(MotionAxis)`: ID, parse, value from the new optional `AudioFeatureFrame.motion`.
  - `ParameterExpression`: the catalog refuses the names; the compiler's exhaustive switch gets an unreachable
    constant (as MOD-015-D5).
- **App**:
  - `MotionSampling` protocol with `CoreMotionSampler` (CMMotionManager device motion, the only CoreMotion import)
    and a DEBUG `StandInMotionSampler` (`-uitestMotionStandIn`), plus an injectable test sampler.
  - `MotionModulationCoordinator` (`@Observable`, main actor): owns the tracker and the sampler, the range
    preference (`settings.motion.range`), demand (host uses motion, Settings readout open, app active), rate from
    PERF-008's budget, Calibrate with an announcement.
  - `NativeSpectrumHost`: `usesMotion` recomputed when bindings or triggers change, a `motionValues` closure read
    in `applyModulation` (no allocation), a demand callback.
  - `AppCoordinator`: one lazy property, `connectMotion(host)` beside `connectLFOs`, `sceneBecame(active:)` hook.
  - `MotionModulationSection` in Settings (performance group), inspector names, privacy policy section.

## Technical Context

**Language/Version**: Swift 6.4.2 (tools 6.0, Swift 6 mode), Xcode 27.2; CI also Xcode 26 and Linux.

**Primary Dependencies**: CoreMotion (system framework, app target only). No package dependency added.

**Storage**: one UserDefaults key `settings.motion.range`. Calibration and motion values are memory only.

**Testing**: XCTest. ParameterGraph on the host (and Linux in CI); app unit tests and one UI test on the private
simulator "CAM11 iPhone 17" (iOS 27.2) with injected motion (the simulator has no sensors). Sample times injected;
no wall-clock assertions.

**Target Platform**: iOS/iPadOS 26+; packages also macOS 15 and Linux.

**Performance Goals**: per sample: a handful of `remainder`/`exp` calls; per frame: one closure call returning a
struct of four Doubles. 60 Hz sampling (30 Hz under the battery-saver budget).

**Constraints**: outputs finite 0…1; sensors off unless needed; type-check budget (small SwiftUI bodies).

**Scale/Scope**: 4 sources, 1 setting, 1 Settings section.

## Constitution Check

- I Public APIs only: `CMMotionManager.startDeviceMotionUpdates(using:to:withHandler:)`, public. Pass.
- VI Modular boundaries: normalization logic in ParameterGraph behind plain value types; the sensor API only in the
  app behind `MotionSampling`. Pass.
- VII Real-time audio safety: motion runs on the main queue, never an audio callback; no allocation per sample. Pass.
- Privacy: no permission prompt needed (device motion requires no usage description); data never stored, sent or
  logged; sensors only while needed and active; privacy policy updated. Pass.
- X Evidence-based quality: synthetic-stream bounds tests; device behaviour left as a `{device}` task. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/ParameterGraph/Sources/ParameterGraph/MotionTracker.swift                               (new)
Packages/ParameterGraph/Sources/ParameterGraph/AudioFeatureSource.swift
Packages/ParameterGraph/Sources/ParameterExpression/ExpressionCatalog.swift, ExpressionCompiler.swift
Packages/ParameterGraph/Tests/ParameterGraphTests/MotionTrackerTests.swift                       (new)
Apps/projectM-iOS/Coordinators/MotionSampling.swift                                              (new)
Apps/projectM-iOS/Coordinators/MotionModulationCoordinator.swift                                 (new)
Apps/projectM-iOS/Coordinators/AppCoordinator+Motion.swift                                       (new)
Apps/projectM-iOS/Views/MotionModulationSection.swift                                            (new)
Apps/projectM-iOS/Visuals/NativeSpectrumHost.swift, Coordinators/AppCoordinator.swift,
  Coordinators/ParameterInspectorModel.swift, Views/SettingsView.swift (small edits)
Apps/projectM-iOS/Tests/MotionModulationAppTests.swift                                           (new)
Apps/projectM-iOS/UITests/MotionCalibrationUITests.swift                                         (new)
Packages/LibraryBackup/Sources/LibraryBackup/LibrarySettings.swift, scripts/run_device_tests.py,
  Apps/projectM-iOS/Tests/LibraryBackupAppTests.swift (the new key)
docs/privacy-policy.md, docs/adr/00NN-device-motion-modulation.md
```

**Structure Decision**: the tracker sits next to `LFOBank` and `BandEnvelopeBank` (modulation sources) so the
acceptance test runs on Linux; the app owns only the sensor and the lifecycle.

## Complexity Tracking

None.
