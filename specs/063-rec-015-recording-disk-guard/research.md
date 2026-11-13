# Research: REC-015 Recording disk guard

## REC-015-D1: Which free-space API

- **Decision**: `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` on the
  recording folder (`<tmp>/Recordings`, created first). Nil or a thrown error = unknown.
- **Rationale**: Apple's documented figure for user-initiated work; it includes space the system can
  purge for important use. One key, one category (Disk space), reason E174.1.
- **Alternatives**: `volumeAvailableCapacityKey` (ignores purgeable space; refuses recordings that
  fit); `...ForOpportunisticUsage` (too pessimistic for a user action); `attributesOfFileSystem` /
  `statfs` (same category, return more than needed).

## REC-015-D2: Estimate

- **Decision**: bytes/s = ceil(max bit rate of `settings.codecPreference` at the output size and
  `maxFrameRate` × 125 / 100 / 8), integer math (`(bitRate × 125 + 799) / 800`). Start needs
  `reserve + 60 × bytes/s`; reserve = 200 MiB = 209,715,200 bytes.
- **Rationale**: the codec is chosen only when the writer starts, so the larger rate (H.264's 0.2
  bits/pixel) is conservative. 25% covers encoder peaks above the average and the MP4 index.
  Example: 1920 × 1080 at 30 fps: H.264 12,441,600 b/s → 1,944,000 B/s → start needs 326,355,200
  bytes (≈ 311 MiB).
- **Alternatives**: measure only (nothing to measure before the first frame); a fixed size (wrong
  for every size but one).

## REC-015-D3: In-recording check

- **Decision**: a separate main-actor loop every 5 s (`Task.sleep`); each sample reads the probe and
  the file size in `Task.detached` (utility priority) and returns to the main actor, which stops with
  `.lowStorage` when `available < reserve + 2 × 5 s × max(estimated, measured)`; measured =
  file bytes / recorded seconds, used once ≥ 1 s is recorded. Unknown available → no decision.
- **Rationale**: never on the frame loop or the writer queue; two intervals of headroom so a burst
  between samples cannot cross the reserve. File size via `fileSizeKey` (not a required-reason API;
  `attributesOfItem` would also be acceptable but returns dates).
- **Alternatives**: check every frame (syscalls on the frame loop); check on the 0.25 s context
  ticker (needlessly frequent, on the main actor).

## REC-015-D4: Out-of-space errors

- **Decision**: `RecordingFailure.storageFull`; an error is out-of-space when its domain/code is
  `NSCocoaErrorDomain` 640 (`NSFileWriteOutOfSpaceError`), `AVFoundationErrorDomain` -11807
  (`AVError.diskFull`) or `NSPOSIXErrorDomain` 28 (`ENOSPC`), checked recursively through
  `NSUnderlyingErrorKey` and `NSMultipleUnderlyingErrorsKey` (depth ≤ 4). `VideoFileWriter` uses it
  where it reported `writerFailed`; the partial file is deleted (an `AVAssetWriter` in `.failed`
  cannot finish a file).
- **Rationale**: AVFoundation wraps the underlying POSIX/Cocoa errors; domain strings keep the
  classifier plain Swift (Linux shape).
- **Alternatives**: string matching on descriptions (localized, fragile).

## REC-015-D5: Test seams

- **Decision**: `StorageProbe` protocol (`availableBytes(at:) -> Int64?`), injected into the
  coordinator; `RecordingWriterFault(afterFrames:error:)` passed to `MetalFrameRecorder`'s public
  init wraps the real sink: after N appended frames, appends fail and finishing cancels the real
  writer, deletes the file and reports the injected error through the classifier. DEBUG app option
  `-uitestStorage low|dropAfter:<n>` (scripted probe; storage interval 1 s). Release: no launch
  option reaches a fake.
- **Rationale**: real disk exhaustion cannot be produced on the simulator or CI safely.

## REC-015-D6: Privacy manifest check

- **Decision**: `check_privacy_manifest.py` gets `ALLOWED_REASONS` per category (UserDefaults
  CA92.1, SystemBootTime 35F9.1, FileTimestamp C617.1, DiskSpace E174.1): a used category must be
  declared with reasons that are all in its allowed set; a declared reason outside the set is a
  problem; an undeclared used category is still a problem.
- **Rationale**: "accepts exactly the declared use"; a wrong reason code (e.g. 85F4.1 for disk
  space, which is for a different purpose) fails the build check instead of App Review.

## REC-015-D7: Leftovers

- **Decision**: no new cleanup. `<tmp>/Recordings` is emptied at coordinator init (REC-003-R13) and
  `<tmp>/Sharing` at `CaptureShareCoordinator` init (REC-012-R6); a low-storage stop goes through the
  normal finish; a storage-full failure deletes its partial file.
