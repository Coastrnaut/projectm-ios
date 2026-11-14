# Implementation Plan: AUD-010 Channel Balance

**Branch**: `feature/aud-010` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/138-aud-010-channel-balance/spec.md`

## Summary

A monitoring-only stereo balance for In-App Playback. The playback graph gains one node: a
dedicated `AVAudioMixerNode` (`balanceNode`) inserted **after** the main mixer, whose output bus 0
keeps the existing analysis tap: `player → mainMixer (tap → PCMSink) → balanceNode → output`. The
balance is the `pan` of the main mixer's input into `balanceNode` (measured to be a linear stereo
balance, research AUD-010-D1). `AudioCore.MonitorBalance` holds the validated value and the law
(gains per channel), tested on Linux. `InAppPlaybackGraph.monitorBalance`, `AVInAppPlaybackBackend`
and `InAppPlaybackSource.monitorBalance` carry the value (a protocol requirement with a default no-op
for scripted backends). The app's `PlaybackBalanceSetting` stores it under
`settings.playbackBalance.position` and pushes it into the source; `PlaybackBalanceSection` in
Settings › audio sections shows the slider, disabled unless the active source is In-App Playback.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AVFAudio (`AVAudioEngine`, `AVAudioMixerNode`, `AVAudioMixingDestination`),
AudioCore, SwiftUI (Settings)

**Storage**: one UserDefaults user-setting key, `settings.playbackBalance.position` (Double)

**Testing**: XCTest. AudioCore law tests (host; Linux shape `-DAUDIOCORE_NO_AVFAUDIO`); CaptureKit
offline manual-rendering acceptance tests (host); app unit tests and one UI test on the feature's
simulator "AUD10 iPhone 17" (iOS 27.2, deleted afterwards)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: no extra work per sample in Swift; one more Apple mixer node in the render
graph (negligible)

**Constraints**: the analysis tap's PCM must be bit-identical at every balance; no cut or discard on
change; no render-thread code added; REC-004 edits the same graph in parallel, so the change is one
node and a few commented lines

**Scale/Scope**: S: ~1 AudioCore file, a small graph and backend change, 1 setting, 1 section, tests

## Constitution Check

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `AVAudioMixerNode`, `AVAudioMixingDestination.pan`. |
| IV. Truthful source labeling | Pass: no label changes; disabled for sources the app does not play. |
| VI. Modular boundaries | Pass: law in AudioCore, graph in CaptureKit, UI in the app. |
| VII. Real-time audio safety | Pass: no Swift on the render thread; the parameter is set on the main actor. |
| X. Evidence-based quality | Pass: offline-render acceptance test; routes/interruptions left `{device}`. |
| Privacy (FR-065) | Pass: one user setting, listed in the three key lists. |

Post-design re-check: unchanged, pass.

## Project Structure

### Documentation (this feature)

```text
specs/138-aud-010-channel-balance/
├── plan.md, research.md, data-model.md, quickstart.md
├── contracts/playback-balance.md
└── tasks.md
```

### Source Code

```text
Packages/AudioCore/Sources/AudioCore/MonitorBalance.swift            (new: value + law)
Packages/AudioCore/Tests/AudioCoreTests/MonitorBalanceTests.swift    (new)
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackGraph.swift   (balance node)
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/AVInAppPlaybackBackend.swift
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/InAppPlaybackSource.swift  (protocol + source)
Packages/CaptureKit/Tests/CaptureKitTests/PlaybackBalanceTests.swift  (new: acceptance)
Apps/projectM-iOS/Coordinators/PlaybackBalanceSetting.swift          (new)
Apps/projectM-iOS/Views/PlaybackBalanceSection.swift                 (new)
Apps/projectM-iOS/Views/AccessibleParameter.swift                    (spoken unit + catalog spec)
Apps/projectM-iOS/Views/SettingsView.swift, VisualizerView.swift, Coordinators/AppCoordinator.swift (wiring)
Apps/projectM-iOS/Tests/PlaybackBalanceSettingTests.swift            (new)
Apps/projectM-iOS/UITests/PlaybackBalanceUITests.swift               (new)
scripts/run_device_tests.py, Packages/LibraryBackup/.../LibrarySettings.swift (key lists)
```

**Structure Decision**: existing packages and app; no new package.

## Complexity Tracking

None.
