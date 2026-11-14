# Implementation Plan: AUD-009 Channel Selection

**Branch**: `feature/aud-009` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/089-aud-009-channel-selection/spec.md`

## Summary

A user-chosen analysis channel (Mix, Left, Right, Mid, Side; default Mix) on the analysis copy of
the audio only. A pass-through `ChannelSelectionReader` (AudioCore) wraps the normalized ring's
analysis tap: it forwards each read, then replaces both channels of every frame just read with the
selected signal s, in the consumer's own scratch buffer. In Mix it returns at once (bit-exact,
today's (L + R)·0.5 is still computed downstream). AUD-008's `InputTrimReader` wraps it, so the
order is tap → selection → trim → `WaveformTap` → ANL-016 pipeline (research AUD-009-D2). The mode
lives in a lock-free `ChannelSelectionControl` written by Settings and read once per read on the
analysis worker. `AppCoordinator.trimmedAnalysisTap` composes the two wrappers, so all seven call
sites follow without change.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AudioCore (`Synchronization.Atomic`), VisualGenerators' `VisualBandFeed`
(tests only), SwiftUI (Settings)

**Storage**: one UserDefaults user-setting key, `settings.analysisChannel.mode` (String)

**Testing**: XCTest: AudioCore (host and `-DAUDIOCORE_NO_AVFAUDIO`), VisualGenerators (host and the
Linux shape `-DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE`), app unit tests and one UI test on the
feature's simulator "AUD9 iPhone 17" (iOS 27.2, deleted afterwards)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: one add or subtract and at most one multiply per frame on the analysis
worker; nothing at all in Mix

**Constraints**: no allocation, lock, log or I/O per read; nothing on the audio callback or main
thread; bit-exact in Mix; Left/Right exact copies

**Scale/Scope**: 1 new AudioCore file, 1 app store class, 1 Settings section, a one-line change to
`trimmedAnalysisTap`, tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: Swift stdlib, Synchronization, SwiftUI. |
| IV/V. Truthful labeling, no capture claims | Pass: no source claims; the footer states what the mode does not change. |
| VI. Modular boundaries | Pass: processing in AudioCore (no UI), wiring in the app. |
| VII. Real-time safety | Pass: no state but the mode, one atomic load per read, analysis worker only (R9). |
| VIII. Upstream projectM fidelity | Pass: projectM's ring is never touched; no analysis reaches projectM. |
| IX. Dependencies | Pass: none added. |
| X. Evidence | Pass: unit tests for every mode and fixture; device checks stay `{device}`. |
| Privacy (FR-065) | Amended by AUD-009-R6: one user-setting key, added to the device check's allowed list. |

Post-design re-check: unchanged, pass. No ADR is needed: nothing overrides a constitution default;
the mid/side definition is recorded in the spec's Clarifications and research AUD-009-D1.

## Project Structure

### Documentation (this feature)

```text
specs/089-aud-009-channel-selection/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/channel-selection.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/ChannelSelection.swift              # AnalysisChannelMode, ChannelSelection (maths), ChannelSelectionControl, ChannelSelectionReader
Packages/AudioCore/Tests/AudioCoreTests/ChannelSelectionTests.swift      # fixtures per mode, bit-exactness, trim composition, seam
Packages/VisualGenerators/Tests/VisualGeneratorsTests/ChannelSelectionBandTests.swift  # band values per mode, WaveformTap shows s
Apps/projectM-iOS/Coordinators/ChannelSelectionSetting.swift             # @Observable store + shared control
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                      # property, -uitestResetNotice, trimmedAnalysisTap composition
Apps/projectM-iOS/Views/ChannelSelectionSection.swift                    # Settings section
Apps/projectM-iOS/Views/SettingsView.swift                               # one optional parameter + one line
Apps/projectM-iOS/Views/VisualizerView.swift                             # passes coordinator.channelSelection
Apps/projectM-iOS/Tests/ChannelSelectionSettingTests.swift               # persistence, unknown values, control sync, composition
Apps/projectM-iOS/UITests/ChannelSelectionUITests.swift                  # Left persists across relaunch
scripts/run_device_tests.py                                              # ALLOWED_KEYS gains the key
```

**Structure Decision**: Same as AUD-008: a `NormalizedPCMReader` decorator in AudioCore (runs on
Linux, no dependency beyond the ring's format) and a separate app store and section file, so
ANL-006 and ACC-006 (in flight) do not edit the same lines.

## Complexity Tracking

None.
