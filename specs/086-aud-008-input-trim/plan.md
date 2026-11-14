# Implementation Plan: AUD-008 Input Trim

**Branch**: `feature/aud-008` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/086-aud-008-input-trim/spec.md`

## Summary

A bounded gain (−12…+24 dB, default 0 dB) on the analysis copy of the audio only. A pass-through
`InputTrimReader` (AudioCore) wraps the normalized ring's analysis tap: it forwards each read, then
scales and soft-clips the frames in the consumer's own scratch buffer, with a 2,048-frame linear
gain ramp. The target lives in a shared lock-free `InputTrimControl` written by the app's Settings
and read once per read on the analysis worker. `AppCoordinator` hands every native host and the tap
tempo's own analysis a fresh wrapper instead of the raw tap; `WaveformTap` therefore sees trimmed
samples. projectM's ring, the sink and the classifier are untouched by construction (research D1).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AudioCore (`Synchronization.Atomic`), VisualGenerators' `VisualBandFeed`
(tests only), SwiftUI (Settings)

**Storage**: one UserDefaults user-setting key, `settings.inputTrim.decibels` (Double)

**Testing**: XCTest: AudioCore (host and `-DAUDIOCORE_NO_AVFAUDIO`), VisualGenerators (host and
the Linux shape `-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), app unit tests and one UI test on the
feature's simulator "AUD8 iPhone 17" (iOS 27.2)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: one multiply, one compare and (above the knee) a cubic per sample on the
analysis worker; ≤ 10 ms of audio per read (≈ 882 stereo frames)

**Constraints**: no allocation, lock, log or I/O per read; nothing on the audio callback or main
thread; bit-exact at 0 dB; output finite and in [−1, 1] when active

**Scale/Scope**: 1 new AudioCore file, 1 app store class, 1 Settings section, coordinator wiring
(7 call sites), tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Swift stdlib, Synchronization, SwiftUI. |
| IV/V. Truthful labeling, no capture claims | Pass: no source claims; footer states what the trim does not change. |
| VI. Modular boundaries | Pass: processing in AudioCore (no UI), wiring in the app. |
| VII. Real-time safety | Pass: scalar state only, one atomic load per read, analysis worker only (R10). |
| VIII. Upstream projectM fidelity | Pass: projectM's ring is never touched; no analysis reaches projectM. |
| IX. Dependencies | Pass: none added. |
| X. Evidence | Pass: unit tests for every rule; device checks stay `{device}`. |
| Privacy (FR-065) | Amended by AUD-008-R6: one user-setting key, added to the device check's allowed list. |

Post-design re-check: unchanged, pass. No ADR is needed: nothing overrides a constitution default.

## Project Structure

### Documentation (this feature)

```text
specs/086-aud-008-input-trim/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/input-trim.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/InputTrim.swift            # InputTrim (law), InputTrimControl, InputTrimProcessor, InputTrimReader
Packages/AudioCore/Tests/AudioCoreTests/InputTrimTests.swift     # law, ramp, saturation, bit-exactness, seam
Packages/VisualGenerators/Tests/VisualGeneratorsTests/InputTrimBandTests.swift  # band levels, WaveformTap shows trimmed
Apps/projectM-iOS/Coordinators/InputTrimSetting.swift           # @Observable store + shared control
Apps/projectM-iOS/Coordinators/AppCoordinator.swift             # trimmedAnalysisTap at every tap call site
Apps/projectM-iOS/Views/InputTrimSection.swift                  # Settings section
Apps/projectM-iOS/Views/SettingsView.swift                      # one optional parameter + one line
Apps/projectM-iOS/Views/VisualizerView.swift                    # passes coordinator.inputTrim
Apps/projectM-iOS/Tests/InputTrimSettingTests.swift             # persistence, clamping, control sync
Apps/projectM-iOS/UITests/InputTrimUITests.swift                # +6 dB persists across relaunch; Reset
scripts/run_device_tests.py                                     # ALLOWED_KEYS gains the key
```

**Structure Decision**: The processing goes in AudioCore beside `NormalizedPCMRing` because it is a
`NormalizedPCMReader` decorator with no dependency beyond the ring's format, and AudioCore runs on
Linux. The app keeps its setting in its own small store rather than `AppSettings`, so ANL-003 (also
touching Settings) and this row do not edit the same lines.

## Complexity Tracking

None.
