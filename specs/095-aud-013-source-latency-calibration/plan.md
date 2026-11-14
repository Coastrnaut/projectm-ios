# Implementation Plan: AUD-013 Source Latency Calibration

**Branch**: `feature/aud-013` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/095-aud-013-source-latency-calibration/spec.md`

## Summary

A per-source visual delay (0…250 ms) that compensates for the output route's latency. One
real-time-safe `LatencyDelayReader` (AudioCore) is a `NormalizedPCMReader` decorator holding a
preallocated stereo delay line of 33,075 frames: it pulls everything the wrapped reader has and
releases only frames that are at least the applied delay old, on the sample clock (research
AUD-013-D1). Two instances per consumer kind share one lock-free `LatencyOffsetControl` (the target
in frames):

- **analysis**: outermost in `AppCoordinator.trimmedAnalysisTap` (tap → channel selection → trim →
  gate → **delay** → `WaveformTap` → pipeline), so bands, oscilloscope, bindings, kick, centroid and
  tempo all shift together; emptied when the session generation changes;
- **renderer**: wraps `manager.normalizedOutput` before `renderer.attach(pcm:)`; never emptied
  (AUD-012 continuity), trims the excess beyond delay + 2,205 frames (the freshness rule).

At target and applied delay 0 with nothing buffered the reader forwards the read unchanged
(bit-identical; today's behavior). A target change moves the applied delay by at most a quarter of
the frames pulled in that read (research AUD-013-D2). The app's `LatencyOffsetSetting` keeps three
values in UserDefaults and writes the active source's frames into the control on `onSessionMode`
(session start and switch) and on edits. "Estimate from Output" calls a pure function with the
route's `outputLatency + ioBufferDuration`, read through a small CaptureKit provider (iOS only)
that the app injects (research AUD-013-D3). ADR-0035 records the timing change (the next free number
at commit time).

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode

**Primary Dependencies**: AudioCore (`Synchronization.Atomic`), AnalysisFeatures (acceptance test
only), CaptureKit (`AVAudioSession` latency read, iOS only), SwiftUI (Settings)

**Storage**: three UserDefaults user-setting keys `settings.latencyOffset.<mode raw value>` (Double, ms)

**Testing**: XCTest: AudioCore (delay law, slew, flush, trim, estimate) on the host and with
`-DAUDIOCORE_NO_AVFAUDIO` (Linux shape); AnalysisFeatures (the acceptance: pulse train → real
pipeline → simulated 60 Hz display frames, injected clock); app unit tests (per-source storage,
control sync, reset key list); one UI test, all on the feature's simulator "AUD13 iPhone 17"
(iOS 27.2, deleted afterwards)

**Target Platform**: iOS 26.0+ (app), macOS 15 and Linux (packages)

**Project Type**: mobile app with SwiftPM packages

**Performance Goals**: per read at most one pass copying the pulled frames into the line and one
copying the released frames out (≤ 2 × 16 KB per 10 ms worker step); nothing extra at 0 ms

**Constraints**: no allocation, lock, log or I/O per read (one relaxed atomic load); the delay line
is allocated in `init` (≈ 265 KB per reader, two readers live); never on the audio callback or the
main thread (analysis worker and render thread only)

**Scale/Scope**: 1 AudioCore file, 1 CaptureKit file, 1 app store class, 1 Settings section, a few
lines in `AppCoordinator`, `SettingsView`, `VisualizerView`, `run_device_tests.py`; tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status |
|---|---|
| I. Public Apple APIs only | Pass: `AVAudioSession.outputLatency` and `ioBufferDuration` are public; no new framework. |
| IV/V. Truthful labeling, no capture claims | Pass: no source label or classifier change; the estimate is called an estimate, not a measurement. |
| VI. Modular boundaries | Pass: delay in AudioCore, the AVAudioSession read in CaptureKit, wiring and UI in the app. |
| VII. Real-time safety | Pass: preallocated bounded line with explicit overflow policies (drop-oldest, excess trim), atomic target, worker/render threads only (R13). |
| VIII. Upstream projectM fidelity | Pass: projectM still gets the same PCM through the documented API, only later; no analysis result reaches it. |
| IX. Dependencies | Pass: none added. |
| X. Evidence | Pass: sample-clock and simulated-time tests; the hardware measurement stays `{device}` (AUD-013-T15). |
| Privacy (FR-065) | Amended by AUD-013-R11: three user-setting keys, added to the device check's allowed list; no new permission (FILE-013 catalog unchanged). |

Post-design re-check: unchanged, pass. ADR needed: the feeds of projectM and the analysis gain a
delay stage (timing architecture), so ADR-0035 records it.

## Project Structure

### Documentation (this feature)

```text
specs/095-aud-013-source-latency-calibration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/latency-delay.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Packages/AudioCore/Sources/AudioCore/LatencyOffset.swift                 # LatencyOffset (bounds, conversion, estimate), LatencyOffsetControl, LatencyDelayReader
Packages/AudioCore/Tests/AudioCoreTests/LatencyOffsetTests.swift         # delay law, clamping, slew bounds, flush/keep, trim, pass-through, estimate
Packages/AnalysisFeatures/Tests/AnalysisFeaturesTests/LatencyOffsetAcceptanceTests.swift   # pulse train → pipeline → display frames
Packages/CaptureKit/Sources/CaptureKit/Route/SystemOutputLatency.swift   # iOS-only AVAudioSession read
Apps/projectM-iOS/Coordinators/LatencyOffsetSetting.swift                # @Observable store + shared control + readers
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                      # property, reset keys, analysis chain, renderer feed, session hook
Apps/projectM-iOS/Views/LatencyOffsetSection.swift                       # Settings section
Apps/projectM-iOS/Views/SettingsView.swift                               # one optional parameter + one line
Apps/projectM-iOS/Views/VisualizerView.swift                             # passes coordinator.latencyOffset
Apps/projectM-iOS/Tests/LatencyOffsetSettingTests.swift                  # persistence, per-source independence, control sync, estimate
Apps/projectM-iOS/UITests/LatencyOffsetUITests.swift                     # section, slider, reset
scripts/run_device_tests.py                                              # ALLOWED_KEYS gains the three keys
docs/adr/0035-source-latency-delay.md                                    # timing decision
```

**Structure Decision**: The AUD-008/009/011 pattern: a reader decorator in AudioCore plus an app
store and section in their own files, so ANL-014 and ACC-006 (in flight) do not edit the same lines.

## Complexity Tracking

None.
