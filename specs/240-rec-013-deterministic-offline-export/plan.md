# Implementation Plan: REC-013 Deterministic Offline Export

**Branch**: `feature/rec-013` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

When Export is tapped, a main-actor `OfflineExportCoordinator` captures an `OfflineExportJob`: REC-002's capture of the
open scene's native visual (style, glow values, Reduce flashing, safety clamp) plus the ANL-003 smoothing, the size, the
rate, the seed and the audio source. A detached task loads the audio (the seeded fixture, or a user-picked file read
with AVFoundation and converted to 44.1 kHz stereo Float32, at most 10 minutes) and runs `OfflineSceneRenderer`.

The renderer owns everything it uses: a Metal command queue, a generator from `NativeSpectrumHost.makeGenerator`, the
FX-001 glow chain, an `OfflineAnalysisDriver` and a `MetalFrameRecorder` in offline mode (`realTime: false`, with an
AAC track). For frame n (research REC-013-D1):

1. `OfflineFrameClock` gives the time n × 1e9 / fps ns and the sample position round(n × 44,100 / fps).
2. The driver lets its `OfflinePCMSource` expose the audio up to that sample and calls ANL-016's `AnalysisPipeline.step()`
   (synchronous, fixed clock); it then reads the newest bands and features, the waveform histories (VIS-003/004
   `WaveformTap`) and drains the frame's bus events (D2).
3. The renderer smooths the bands (ANL-003 `BandSmoother`, interval 1 / fps), hands events to the beat rings or
   particle visuals as the live host does, and encodes the generator (through the glow chain when the glow is on) into a
   private `bgra8Unorm_srgb` texture.
4. The same command buffer blits the texture into a shared read-back buffer and into the recorder's pixel buffer
   (`recordFrame` at the frame's time); after `waitUntilCompleted` the BGRA bytes are hashed (SHA-256, CryptoKit) and
   the frame's audio slice is handed to the recorder; `waitForPendingFrames` keeps the writer in step, so nothing is
   ever dropped and nothing waits for the real clock.

After the last frame the recorder finishes the MP4 and the sidecar (`OfflineExportManifest`, JSON with sorted keys) is
written next to it. Cancel is a flag checked before each frame; cancel, a failure or leaving the foreground cancels the
recorder and deletes the export's folder (`<tmp>/OfflineExport/<UUID>/`).

The pure parts (clock, PCM source, analysis driver, fixture audio, manifest) live in `VisualBandFeed` (VisualGenerators
package) and build on Linux; the Metal, AVFoundation and CryptoKit parts live in the app.

UI: Settings › Visual gets "Export Video Offline…" under the snapshot rows (one `SettingsView` line), opening a sheet
with Audio (Fixture / Choose File…), Seed, Shape, Rate, Export, progress and Cancel, then Save…, Share… and Save to
Photos.

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 host; CI also Xcode 26)
**Primary Dependencies**: Metal, AVFoundation (audio file read), CryptoKit (SHA-256), SwiftUI, Observation; VisualGenerators (`VisualBandFeed`, `VisualEffects`, `VisualParameters`), AnalysisFeatures (`AnalysisPipeline`, `BandSmoother`), AudioCore (`NormalizedPCMReader`), Compositor `FrameRecording` (`MetalFrameRecorder`, `RecordedVideoInspector`), FlashSafety; app REC-002 job capture, REC-011 photos, REC-012 sharing, ACC-004 announcer
**Storage**: temporary files only (`<tmp>/OfflineExport`), removed on Done and at launch; no UserDefaults key
**Testing**: package unit tests (VisualGeneratorsTests); app unit tests with real Metal rendering at 160 × 90 on simulator "REC13 iPhone 17" (iOS 27.2); one UI test under 30 s
**Target Platform**: iOS 26+
**Performance Goals**: offline: as fast as the device renders and encodes; the main actor does no rendering
**Constraints**: no projectM engine change (Constitution VIII); no scene format change, no new UserDefaults key, no permission, no networking; owner rule 7 budgets; Xcode 26 type-check budget; one-line edits in shared files

## Constitution Check

- I (public APIs only): Metal, AVFoundation, CryptoKit, SwiftUI, Photos add-only (existing). Pass.
- VI (modular boundaries): the export never touches projectM, the capture layer or the live host; pure logic in a package. Pass.
- VII (real-time audio safety): no audio callback involved; the export reads a file into memory off the main thread. Pass.
- VIII (upstream projectM fidelity): projectM scenes are refused instead of patching the engine's random numbers (D3). Pass.
- IX (dependencies): none added (CryptoKit is a system framework). Pass.
- X (evidence): simulator tests prove behavior and repeatability on the simulator's GPU only; the device run is a `{device}` task.
- FR-072 / ACC-012 (flash safety): frames go through the generators' Reduce-flashing limiter with the clamped glow, as on screen. Pass.

Post-design re-check: unchanged, pass.

## Project Structure

```text
Packages/VisualGenerators/Sources/VisualBandFeed/OfflineFrameClock.swift        # new: frame n → time, sample position, count
Packages/VisualGenerators/Sources/VisualBandFeed/OfflinePCMSource.swift         # new: in-memory reader with an advancing limit
Packages/VisualGenerators/Sources/VisualBandFeed/OfflineAnalysisDriver.swift    # new: AnalysisPipeline stepped per frame
Packages/VisualGenerators/Sources/VisualBandFeed/OfflineFixtureAudio.swift      # new: seeded 44.1 kHz stereo fixture
Packages/VisualGenerators/Sources/VisualBandFeed/OfflineExportManifest.swift    # new: sidecar model + JSON
Packages/VisualGenerators/Tests/VisualGeneratorsTests/OfflineExportCoreTests.swift   # new
Apps/projectM-iOS/Coordinators/OfflineExportJob.swift                           # new: job capture, sizes, rates, refusals
Apps/projectM-iOS/Coordinators/OfflineExportCoordinator.swift                   # new: state machine, folder, cancel, offers
Apps/projectM-iOS/Coordinators/AppCoordinator+OfflineExport.swift               # new: wiring
Apps/projectM-iOS/Coordinators/AppCoordinator.swift                             # owns `offlineExport`; one connect call
Apps/projectM-iOS/Visuals/OfflineAudioLoader.swift                              # new: file → 44.1 kHz stereo
Apps/projectM-iOS/Visuals/OfflineSceneRenderer.swift                            # new: frame loop, checksums, recorder
Apps/projectM-iOS/Views/OfflineExportViews.swift                                # new: row, sheet
Apps/projectM-iOS/Views/SettingsView.swift                                      # one line: the row
Apps/projectM-iOS/Tests/OfflineExportAcceptanceTests.swift                      # new: the roadmap acceptance
Apps/projectM-iOS/UITests/OfflineExportUITests.swift                            # new
```

## Complexity Tracking

None.
