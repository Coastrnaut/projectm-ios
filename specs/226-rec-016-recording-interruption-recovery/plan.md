# Implementation Plan: REC-016 Recording interruption recovery

**Branch**: `feature/rec-016` | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

## Summary

Make the REC-003 writer write movie fragments (1 s) so a failed writer leaves readable frames; add a
salvage step to the recorder that finishes a still-healthy writer early or keeps the completed
fragments, reads the file back and keeps it only when it has at least two frames; widen REC-015's
fault seam to append, writer, finish and start failures; count live recorders and writers to prove
release; add a thermal guard (warn at Serious, stop at Critical, refuse Record at Critical); prove the
background stop offers the finished file.

## Technical Context

**Language/Version**: Swift 6.4.2 (Xcode 27.2), Swift 6 language mode
**Primary Dependencies**: AVFoundation (`AVAssetWriter.movieFragmentInterval`), CoreVideo, Metal; no new dependency
**Storage**: temporary files in `<tmp>/Recordings` only (unchanged)
**Testing**: XCTest — FrameRecording package tests (host and simulator), app tests on the "REC16 iPhone 17" iOS 27.2 simulator, one UI test
**Target Platform**: iOS/iPadOS 26+; Linux shape of the Compositor package must build (plain-Swift files only there)
**Performance Goals**: no added work on the frame loop; fragment headers once per second on the writer queue
**Constraints**: short fixtures (≤ 2 s of 64×48 frames); no wall-clock assertions (read-back counts only)
**Scale/Scope**: FrameRecording (4 files), VideoRecordingCoordinator, StatusEvents, one UI test

## Constitution Check

- Public Apple APIs only (`movieFragmentInterval` is public AVFoundation): PASS.
- Privacy/local-first: no new storage, keys or network; the ledger lives in memory: PASS.
- Honest reporting: simulator results are not device evidence; the fragment cost is a `{device}` task: PASS.
- Linux shape: thermal guard and fault types are plain Swift; writer and ledger are Apple-only: PASS.

## Project Structure

```text
Packages/Compositor/Sources/FrameRecording/
  RecordingStorage.swift          # RecordingWriterFault: kinds (append, writer, finish, start)
  RecordingRecovery.swift         # NEW plain Swift: RecordingSalvageOutcome, RecordingThermalLevel, RecordingThermalGuard, notices
  RecordingOutcome.swift          # stop reason .thermal, refusal .thermal, writerFailed notice, RecordedVideo.interruption
  RecordingSettings.swift         # fragmentIntervalSeconds (1.0)
  VideoFileWriter.swift           # fragments, salvage, failure injection, ledger, fault sink kinds
  MetalFrameRecorder.swift        # salvage path, start-failure cleanup, texture cache flush, ledger
Packages/Compositor/Tests/FrameRecordingTests/RecordingRecoveryTests.swift      # NEW
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift                  # thermal, kept-part notice, DEBUG fault argument
Apps/projectM-iOS/Coordinators/StatusEvents.swift                               # .thermal rows, notice classification
Apps/projectM-iOS/Tests/RecordingRecoveryAppTests.swift                         # NEW
Apps/projectM-iOS/UITests/RecordingRecoveryUITests.swift                        # NEW
docs/adr/0061-recording-fragmented-writing-and-salvage.md                        # NEW (amends REC-003-R17)
```

## Complexity Tracking

None. ADR-0061 records the one default that changes (REC-003-R17 "no partial file is kept").
