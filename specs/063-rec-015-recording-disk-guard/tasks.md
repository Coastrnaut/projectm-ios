# Tasks: REC-015 Recording disk guard

**Input**: design documents in `specs/063-rec-015-recording-disk-guard/` (spec, plan, research,
data-model, contracts/disk-guard.md, quickstart).

**Tests**: requested by the spec (REC-015-S1 to S5) and the brief; budgets follow owner rule 7
(unit test about 1-2 s, ≤ 10 s; suite < 1 min; UI test < 30 s).

Format: `- [ ] REC-015-Tnn [P?] [US?] description (file)`. `{device}` = needs the owner's hands and
physical devices; left open.

## Phase 1: Setup

- [ ] REC-015-T01 Simulator `REC15 iPhone 17` (iOS 27.2), `xcodegen generate`, preset submodules; PosterBoard reports counted before (no file)

## Phase 2: Foundational (blocks every story)

- [ ] REC-015-T02 [P] Storage rules per the contract: `StorageProbe` (`availableBytes(at:) -> Int64?`), `VolumeStorageProbe` (Apple platforms; `volumeAvailableCapacityForImportantUsageKey` only), `RecordingStorageEstimate` ("bytes/s = (max bit rate of codecPreference × 125 + 799) / 800"), `RecordingStoragePolicy` (reserve "209_715_200", start "60 s", interval "5 s", stop horizon "2 intervals"; unknown → start allowed, no stop), `RecordingStorage.fileBytes(at:)` (`fileSizeKey`), in `Packages/Compositor/Sources/FrameRecording/RecordingStorage.swift`
- [ ] REC-015-T03 [P] Outcomes: `RecordingStopReason.lowStorage`, `RecordingRefusal.lowStorage`, `RecordingFailure.storageFull` with the data-model notices verbatim; `RecordingFailure.isOutOfSpace` (Cocoa 640, AVFoundation -11807, POSIX 28, recursive through underlying errors, depth ≤ 4) and `fromWriterError(_:fallback:)`, in `Packages/Compositor/Sources/FrameRecording/RecordingOutcome.swift`
- [ ] REC-015-T04 Writer and seam: `VideoFileWriter` reports failures through `fromWriterError`; `RecordingWriterFault` (`afterFrames`, `error`, `.diskFull(afterFrames:)`) and a fault-injecting sink wrapper chosen by `MetalFrameRecorder`'s public init (`fault: RecordingWriterFault? = nil`); the `finishWriting` failure path is classified too (edge case: the index cannot be written), in `Packages/Compositor/Sources/FrameRecording/VideoFileWriter.swift`, `MetalFrameRecorder.swift`, `RecordingStorage.swift`
- [ ] REC-015-T05 Rule tests (Linux shape): estimate for 1920 × 1080 / 30 fps both codecs (1_944_000 B/s, start 326_355_200), HEVC only (1_166_400), the 1 Mb/s floor (156_250); policy start/stop edges, measured rate wins when larger, unknown values; classifier on direct, nested and unrelated errors; notices, in `Packages/Compositor/Tests/FrameRecordingTests/RecordingStorageTests.swift`

## Phase 3: User Story 1 - Record refuses when there is no room (P1)

**Goal**: pre-flight refusal. **Independent test**: app unit test with an injected probe; UI test `low`.

- [ ] REC-015-T06 [US1] Coordinator pre-flight: init parameters `storageProbe`, `storageCheckInterval`, `writerFault`; at Record (after `RecordingGate` and REC-012-R10) create the folder, read the probe once, refuse with `.lowStorage` (probe `refused: lowStorage`) when the policy does not allow the start, in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`
- [ ] REC-015-T07 [US1] App tests: low value refuses with the exact notice and starts nothing; enough space starts; unknown (nil) starts, in `Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift`

## Phase 4: User Story 2 - A recording stops cleanly before storage runs out (P1)

**Goal**: the low-storage stop finishes and offers the file. **Independent test**: fixture + app test + UI test.

- [ ] REC-015-T08 [US2] Storage loop: every `storageCheckInterval` (5 s) a sample read off the main actor (`Task.detached`: probe + `fileBytes`), decided on the main actor, `stop(.lowStorage)`; cancelled on every stop; `checkStorage()` for tests; DEBUG `-uitestStorage low|dropAfter:<n>` scripted probe with a 1 s interval; DEBUG read-back of an offered file into the probe, in `Apps/projectM-iOS/Coordinators/VideoRecordingCoordinator.swift`
- [ ] REC-015-T09 [P] [US2] Fixture: offline real writer, fake readings that drop below the threshold at frame k = 6, the policy stops, the finished file reads back with 6 frames and strictly increasing times (REC-015-S2), in `Packages/Compositor/Tests/FrameRecordingTests/MetalFrameRecorderTests.swift`
- [ ] REC-015-T10 [US2] App test: recording with a settable probe, drop, `checkStorage()` → `.lowStorage`, exact notice, the file read back (3 frames); a rise keeps recording, in `Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift`

## Phase 5: User Story 3 - The device really runs out of space (P2)

**Goal**: storage-full failure deletes the partial file. **Independent test**: injected failure.

- [ ] REC-015-T11 [P] [US3] Package test: real offline writer with `.diskFull(afterFrames: 3)` → `hasFailed`, `finish()` = `.failure(.storageFull)`, no file (REC-015-S3), in `Packages/Compositor/Tests/FrameRecordingTests/MetalFrameRecorderTests.swift`
- [ ] REC-015-T12 [US3] App test: coordinator with `writerFault: .diskFull(afterFrames: 2)` → notice "Storage is full; the recording couldn't be saved.", probe `failed: storageFull`, nothing offered, folder empty, in `Apps/projectM-iOS/Tests/VideoRecordingAppTests.swift`

## Phase 6: Privacy and UI test

- [ ] REC-015-T13 [P] Manifest: `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1`, in `Apps/projectM-iOS/PrivacyInfo.xcprivacy`; `ALLOWED_REASONS` per category in `scripts/check_privacy_manifest.py` (unknown reason → problem, undeclared use → problem) with tests in `scripts/test_scripts.py`
- [ ] REC-015-T14 UI test `RecordingDiskGuardUITests`: `low` → Record refused with the notice, no indicator; `dropAfter:3` → recording stops with the low-storage notice, "Recording ready" panel, probe reads back a video; the notices are found through the accessible `videoRecordingNoticeText` element (REC-015-R14); each < 30 s, in `Apps/projectM-iOS/UITests/RecordingDiskGuardUITests.swift`
- [ ] REC-015-T15 Docs: ADR-0027 amendment, `docs/release/app-privacy.md` (REC-015 note + manifest table row), `docs/privacy-policy.md` (free-space check sentence), spec status; the privacy review states the value is never stored, logged or sent (REC-015-R10), in `docs/`

## Phase 7: Verification

- [ ] REC-015-T16 Runs: `swift test --package-path Packages/Compositor`, the Linux shape, `xcodebuild test -scheme Compositor` once on the simulator, app tests (projectM-iOSTests, RecordingDiskGuardUITests, VideoRecordingUITests, CaptureShareUITests), `check_privacy_manifest.py` on the Debug (and Release) simulator app, `check_compliance.py`, `validate_docs.py`, `test_scripts.py`; REC-015-R13: confirm by reading the code and the existing tests that `<tmp>/Recordings` (REC-003-R13) and `<tmp>/Sharing` (REC-012-R6) are swept at launch; PosterBoard reports after; simulator deleted
- [ ] REC-015-T17 {device} On D1 nearly full (or a long recording), the guard stops the recording with "Recording stopped because storage is almost full." and the offered file plays (REC-015-S6)

## Dependencies

T01 → T02-T05 → US1 (T06-T07) → US2 (T08-T10) → US3 (T11-T12) → T13-T15 → T16; T17 owner.
T02 and T03 are parallel; T09 and T11 are parallel with app work.

## Analysis (speckit-analyze, 2026-11-13)

No critical or high findings. Applied: R13 (leftovers) had no task → T16 verifies it; R14 (accessible notices) → T14; R10 (not stored or sent) → T15; the edge case "the index cannot be written" → T04. Coverage after the fixes: R1-R14 and S1-S6 each map to at least one task (S6 = T17 `{device}`).

## Implementation strategy

MVP = Foundational + US1 + US2 (the row's observable behavior); US3 completes the acceptance.
