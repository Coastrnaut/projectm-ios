# Implementation Plan: AUD-016 Reference tone suite

**Branch**: `feature/aud-016` | **Date**: 2026-11-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-aud-016-reference-tone-suite/spec.md`

## Summary

1. **AudioCore** gets a Foundation-only, deterministic tone generator (`ToneMath`, `ToneFormat`,
   `ToneSignal`, `ToneGenerator`) and a versioned fixture catalog with expected analysis values
   (`ReferenceToneCatalog`, `ReferenceToneFixture`). Bit-identical output comes from computing every
   sample from the frame index with correctly rounded basic arithmetic and the generator's own
   polynomial sine, exponential and logarithm (research AUD-016-D1, D2).
2. **AudioCore tests** prove it: golden SHA-256 per fixture and variant (two runs; host, Linux flag,
   iOS Simulator), a reference DFT, onset scan and sweep-frequency measurement written in the tests
   only, and identical level-meter and classifier results on repeated runs.
3. **CaptureKit** plays a fixture as In-App Playback: `InAppPlaybackTrack.tone`, an in-memory
   buffer storage in `InAppPlaybackGraph.Content`, buffer scheduling with the same cuts, loops and
   positions; `PlaybackItem.tone`. Offline-render tests compare delivered frames with the generator.
4. **CaptureUI** adds the Diagnostics section, the Test Signals list and their strings, and the
   status-line composition.
5. **App**: the chooser shows the section; `AppCoordinator.playTestSignal`; the indicator names the
   signal. A UI test covers chooser → signal → indicator and relaunch.

## Technical Context

**Language/Version**: Swift 6.4.2 (strict concurrency), Xcode 27.2, iOS SDK 27.2

**Primary Dependencies**: Foundation (generator); AVFAudio (`AVAudioEngine`, `AVAudioPlayerNode`,
`AVAudioPCMBuffer`) in CaptureKit; SwiftUI in CaptureUI and the app. No new dependency.

**Storage**: none. Nothing is persisted; the tone buffer lives in memory while it plays.

**Testing**: XCTest. `swift test` on the macOS host (AudioCore also with
`-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`); `xcodebuild test` of the packages on the iOS 27.2 simulator;
app unit and UI tests on the simulator. Audio through the graph only in offline manual rendering.

**Target Platform**: iOS/iPadOS 26.0 and later (ADR-0002); macOS host and Linux for AudioCore

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: a 10 s 48 kHz stereo loop generated in under 100 ms on D1 in Release
(measured in the device phase; the host measurement is recorded in tasks); memory 3.84 MB per
playing signal.

**Constraints**: generator Foundation-only and allocation-free in `render`; nothing on the render
thread beyond what the player already does; public APIs only; no networking, entitlement,
background mode or stored data; bit-identical output across hosts.

**Scale/Scope**: about 550 lines of production Swift (AudioCore ~350, CaptureKit ~80, CaptureUI ~90,
app ~30) and about 900 lines of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check | Result |
|---|---|---|
| I Public APIs only | AVFAudio, SwiftUI, Foundation; no private API, no `dlopen` | Pass |
| II Capture feasibility | No capture change | Pass (n/a) |
| III ScreenCaptureKit | Not touched | Pass (n/a) |
| IV Truthful labeling | Test signals are In-App Playback; indicator `In-App Playback · <name> · <state>`; names begin with "Test"; "Active audio" still needs verified samples | Pass |
| V No universal claims | No compatibility text | Pass |
| VI Modular boundaries | Generator in AudioCore (no platform types), playback in CaptureKit, strings and views in CaptureUI, app thin; projectM unaware of the source | Pass |
| VII Real-time safety | Buffer generated before playback on the main actor; `render` allocation-free; the tap path unchanged | Pass |
| VIII ProjectM fidelity | No analysis is added: the generator synthesizes signals, and the FFT/onset code is a test oracle only (ADR-0008 decision 5 boundary untouched) | Pass |
| IX Dependencies | None added; signals are generated in-house (no license question) | Pass |
| X Evidence | Unit tests, golden hashes; device checks tagged `{device}` for the final phase | Pass |
| Privacy | No recording, no stored data, nothing leaves the device; privacy policy unchanged | Pass |

Post-design re-check: unchanged, all pass. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/011-aud-016-reference-tone-suite/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md
├── checklists/requirements.md
└── contracts/
    ├── tone-generator.md      # API and playback guarantees
    ├── fixture-catalog.md     # fixtures, expected values, golden hashes, tolerance
    └── ui-strings.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/ReferenceTones/
  ToneMath.swift  ToneSignal.swift  ToneGenerator.swift  ReferenceToneCatalog.swift
Packages/AudioCore/Tests/AudioCoreTests/
  ToneMathTests.swift  ToneGeneratorTests.swift  ReferenceToneCatalogTests.swift
  ReferenceToneGoldens.swift  ReferenceToneOracleTests.swift  ToneAnalyzerDeterminismTests.swift
  TestSHA256.swift
Packages/CaptureKit/Sources/CaptureKit/InAppPlayback/
  InAppPlaybackSource.swift (track case)  InAppPlaybackGraph.swift (buffer content)
  PlayOrder.swift (PlaybackItem.tone)  ToneContent.swift (generation into AVAudioPCMBuffer)
Packages/CaptureKit/Tests/CaptureKitTests/ToneTrackTests.swift
Packages/CaptureUI/Sources/CaptureUI/
  UIStrings.swift  TestSignalsSection.swift
Packages/CaptureUI/Tests/CaptureUITests/TestSignalStringsTests.swift (+ ViewRenderTests)
Apps/projectM-iOS/ProjectMApp.swift  Coordinators/AppCoordinator.swift  Views/SourceStatusIndicator.swift
Apps/projectM-iOS/Tests/TestSignalCoordinatorTests.swift
Apps/projectM-iOS/UITests/TestSignalsUITests.swift
```

`project.yml` needs no change (the app's targets take whole folders). Shared files touched with
small, local edits: `AppCoordinator.swift` (one method and one comment line), `ProjectMApp.swift`
(one section).

**Structure Decision**: extend AudioCore, CaptureKit, CaptureUI and the app; no new package (the
roadmap's proposed `AnalysisFeatures` package is for ANL rows, which will depend on AudioCore's
catalog).

## Test design (deterministic)

- Every assertion on samples is exact equality or an exact hash; tolerances only where physics
  needs them (accuracy against Foundation, sweep frequency measurement, sample-rate conversion).
- No wall clock: the classifier test uses `t = frames / rate`; offline rendering has no real-time
  pacing.
- Each determinism test generates twice in the same process and compares; the cross-host claim is
  the same golden values passing on the host, with the Linux flag and in the simulator.
- Red run first: tests are written against missing symbols and fail to compile (recorded in
  tasks.md), then the implementation makes them pass.

## Persistence and rollback

No persistence: the feature stores nothing (AUD-016-R14), so there is no migration and no data to
clean up. Rollback is reverting the feature's commits (research AUD-016-D10).

## Complexity Tracking

None.
