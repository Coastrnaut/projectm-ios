# Implementation Plan: AUD-011 Input Noise Gate

**Branch**: `feature/aud-011` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/091-aud-011-input-noise-gate/spec.md`

## Summary

An optional downward noise gate on the analysis copy of the audio, active only for the Microphone
source. A pass-through `NoiseGateReader` (AudioCore) wraps AUD-008's `InputTrimReader`, so the
chain is tap → `ChannelSelectionReader` → `InputTrimReader` → `NoiseGateReader` → `WaveformTap` →
ANL-016 pipeline (research AUD-011-D1). Per frame it updates a peak envelope (instant attack, 10 ms
release), runs a closed/attack/open/hold/release state machine with an open threshold and a close
threshold 6 dB lower, and multiplies the frame by a linearly ramped gain (attack 5 ms, hold 100 ms,
release 150 ms, closed = 0). When the gate is off or the source is not the microphone the reader
returns at once (bit-exact). A lock-free `NoiseGateControl` carries the enabled flag, the
microphone-source flag and the threshold; Settings writes the first and third, `AppCoordinator`
writes the source flag when it starts or stops a source. `AppCoordinator.trimmedAnalysisTap` gains
one wrapper, so all call sites follow without change.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AudioCore (`Synchronization.Atomic`, libm `expf`/`powf` at configuration
only), SwiftUI (Settings)

**Storage**: two UserDefaults user-setting keys, `settings.noiseGate.enabled` (Bool) and
`settings.noiseGate.thresholdDecibels` (Double)

**Testing**: XCTest: AudioCore on the host and with `-DAUDIOCORE_NO_AVFAUDIO` (the Linux job's
shape, `.github/workflows/ios-ci.yml`), app unit tests and one UI test on the feature's simulator
"AUD11 iPhone 17" (iOS 27.2, deleted afterwards)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: per frame two `abs`, three compares, one multiply for the envelope and one
or two for the gain; nothing when inactive

**Constraints**: no allocation, lock, log or I/O per read (two relaxed atomic loads); `powf` only
when the threshold changes; nothing on the audio callback or main thread; bit-exact when inactive

**Scale/Scope**: 1 new AudioCore file, 1 app store class, 1 Settings section, a few lines in
`AppCoordinator`, `SettingsView`, `VisualizerView`, tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Swift stdlib, Synchronization, libm, SwiftUI. |
| IV/V. Truthful labeling, no capture claims | Pass: the audio-state classifier (FR-011) is untouched, so "Listening/Silent" stays truthful; the footer states what the gate does not change. |
| VI. Modular boundaries | Pass: processing in AudioCore (no UI), wiring in the app. |
| VII. Real-time safety | Pass: scalar state, atomic loads, analysis worker only (R11). |
| VIII. Upstream projectM fidelity | Pass: projectM's ring is never touched. |
| IX. Dependencies | Pass: none added. |
| X. Evidence | Pass: sample-clock unit tests for every law; device checks stay `{device}`. |
| Privacy (FR-065) | Amended by AUD-011-R8: two user-setting keys, added to the device check's allowed list. |

Post-design re-check: unchanged, pass. No ADR is needed: nothing overrides a constitution default;
the law is recorded in the spec's Clarifications and research AUD-011-D1…D6.

## Project Structure

### Documentation (this feature)

```text
specs/091-aud-011-input-noise-gate/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/noise-gate.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/NoiseGate.swift                # NoiseGateParameters, NoiseGateControl, NoiseGateProcessor, NoiseGateReader
Packages/AudioCore/Tests/AudioCoreTests/NoiseGateTests.swift        # acceptance fixtures, hysteresis, hold/release, pass-through, composition, seam
Apps/projectM-iOS/Coordinators/NoiseGateSetting.swift               # @Observable store + shared control
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                 # property, -uitestResetNotice, composition, source flag
Apps/projectM-iOS/Views/NoiseGateSection.swift                      # Settings section
Apps/projectM-iOS/Views/SettingsView.swift                          # one optional parameter + one line
Apps/projectM-iOS/Views/VisualizerView.swift                        # passes coordinator.noiseGate
Apps/projectM-iOS/Tests/NoiseGateSettingTests.swift                 # persistence, validation, control sync, composition
Apps/projectM-iOS/UITests/NoiseGateUITests.swift                    # toggle and threshold
scripts/run_device_tests.py                                         # ALLOWED_KEYS gains the two keys
```

**Structure Decision**: Same as AUD-008 and AUD-009: a `NormalizedPCMReader` decorator in AudioCore
and a separate app store and section file, so ANL-007 and ACC-006 (in flight) do not edit the same
lines.

## Complexity Tracking

None.
