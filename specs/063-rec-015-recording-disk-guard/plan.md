# Implementation Plan: REC-015 Recording disk guard

**Branch**: `feature/rec-015` | **Date**: 2026-11-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/063-rec-015-recording-disk-guard/spec.md`

## Summary

`FrameRecording` (Packages/Compositor) gains the plain-Swift storage rules: `RecordingStorageEstimate`
(bytes per second from the output size, frame rate and the highest bit rate among the preferred
codecs, plus 25% headroom), `RecordingStoragePolicy` (start needs reserve 200 MiB + 60 s; stop when
less than reserve + two 5 s intervals at the larger of the estimated and measured rates), the
`StorageProbe` protocol, the out-of-space error classifier, a new `RecordingFailure.storageFull`,
`RecordingStopReason.lowStorage` and `RecordingRefusal.lowStorage`. On Apple platforms,
`VolumeStorageProbe` reads `volumeAvailableCapacityForImportantUsage` of the recording folder, and a
`RecordingWriterFault` seam makes the recorder's sink fail with an injected error after N frames.
`VideoFileWriter` maps real writer errors through the classifier, so an out-of-space failure becomes
`storageFull` and the partial file is deleted (REC-003-R17's path).

The app's `VideoRecordingCoordinator` reads the probe once at Record (after the existing refusals),
refuses with the low-storage notice, and while recording runs a second, 5 s storage loop that reads
the probe and the file's size off the main actor (`Task.detached`), then decides on the main actor
and stops with `.lowStorage` (the normal finish: the file is finished and offered). DEBUG
`-uitestStorage low|dropAfter:<n>` installs a scripted probe (1 s interval); the DEBUG probe also
reads back an offered file so a UI test can see it plays. The privacy manifest declares Disk space
(E174.1); `check_privacy_manifest.py` checks reasons per category (research REC-015-D1 to D7).

## Technical Context

**Language/Version**: Swift 6 (Xcode 27.2 on the build Mac; Xcode 26 / iOS SDK 26.5 in CI); Python 3
for the manifest scan.

**Primary Dependencies**: Foundation (`URLResourceKey.volumeAvailableCapacityForImportantUsageKey`,
`fileSizeKey`, `NSError` domains), AVFoundation (existing writer). No new package or dependency.

**Storage**: none new. The free-storage value is used in memory only (REC-015-R10).

**Testing**: package `FrameRecordingTests` (estimate math with typed literals, policy start/stop,
classifier incl. nested errors, fixture: offline writer stopped at frame k decodes with k frames and
increasing times, injected disk-full → `storageFull` and no file); app `VideoRecordingAppTests`
(pre-flight refusal, low-storage stop offers a finished file, injected disk-full → notice, no file,
unreadable value proceeds); one UI test `RecordingDiskGuardUITests`; script tests for the manifest
reasons; `check_privacy_manifest.py` on the Debug simulator app.

**Target Platform**: iOS/iPadOS 26+ (package also macOS host and the Linux shape).

**Project Type**: mobile app + Swift package.

**Performance Goals**: nothing on the frame loop; one volume query at Record and every 5 s while
recording, off the main actor.

**Constraints**: public APIs only; no networking; the only new required-reason API is Disk space
(E174.1); file size via `fileSizeKey` (no file timestamps); explicit closure types; typed literals;
no C stdio globals; no main-actor mutation in setUp/tearDown; no wall-clock assertions; owner rule
7 budgets; never the Simulator panel tool; small edits to shared files (FILE-001 and SHOW-014 run in
parallel).

**Scale/Scope**: about 250 lines of source, 350 of tests.

## Constitution Check

*GATE: passed before Phase 0 and re-checked after Phase 1 design.*

| Principle | Check |
|---|---|
| I Public APIs | `URLResourceValues.volumeAvailableCapacityForImportantUsage`, `fileSize`, AVFoundation errors: public and documented. |
| VI Modular boundaries | Rules in `FrameRecording` (no app or engine imports); the app only wires them. |
| VII Real-time safety | No work on the frame loop; the storage read runs off the main actor every 5 s. |
| X Evidence | Unit/fixture tests for the rules; simulator UI test; the device check (REC-015-S6) stays `{device}`. Privacy review below; the manifest scan runs on the built app. |
| Privacy | The free-storage value never leaves memory; declared E174.1; label unchanged (Data Not Collected). |
| ADR | Amends ADR-0027 (its Consequences named REC-015); no constitution default is overridden. |

Result: pass (pre- and post-design). No Complexity Tracking entries.

## Project Structure

```text
Packages/Compositor/Sources/FrameRecording/
  RecordingStorage.swift          # new: estimate, policy, probe protocol, file size, classifier, fault seam
  RecordingOutcome.swift          # + lowStorage stop/refusal, storageFull failure
  VideoFileWriter.swift           # writer errors → classifier
  MetalFrameRecorder.swift        # fault-injecting sink wrapper (init parameter)
Packages/Compositor/Tests/FrameRecordingTests/
  RecordingStorageTests.swift     # new: rules (Linux shape)
  MetalFrameRecorderTests.swift   # + fixture stop at frame k, injected disk full
Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift   # pre-flight, storage loop, DEBUG probe
Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift              # + guard tests
Apps/projectM-iOS/UITests/RecordingDiskGuardUITests.swift         # new
Apps/projectM-iOS/PrivacyInfo.xcprivacy                           # + Disk space E174.1
scripts/check_privacy_manifest.py, scripts/test_scripts.py        # reasons per category
docs/release/app-privacy.md, docs/adr/0027-video-recording-pipeline.md, docs/privacy-policy.md
```

**Structure Decision**: rules in the existing `FrameRecording` target (Linux-testable); app wiring in
the existing coordinator; no new target.

## Privacy Review (REC-015)

Reviewed 2026-11-13 against the constitution's privacy constraints, FR-065 and FR-066:

- **What is read**: the free storage available for important use on the volume holding the app's
  temporary folder, at Record and every 5 s while recording; the size of the app's own recording
  file. Nothing about other apps or files.
- **Use**: only to refuse or stop a recording on the device. Not stored, not logged (the DEBUG probe
  string shows only the guard's decision), not sent; the app has no network code.
- **Required-reason API**: Disk space, `NSURLVolumeAvailableCapacityForImportantUsageKey`, declared
  as `NSPrivacyAccessedAPICategoryDiskSpace` with reason **E174.1** ("check whether there is
  sufficient disk space to write files"); the value is not sent off the device, as E174.1 requires.
  The file size uses `fileSizeKey`, which is not a required-reason API; no file timestamps.
- **Label**: unchanged, Data Not Collected; `docs/release/app-privacy.md` records it; the owner
  confirms in App Store Connect.
