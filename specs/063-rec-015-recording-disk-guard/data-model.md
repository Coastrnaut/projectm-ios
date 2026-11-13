# Data model: REC-015 Recording disk guard

All values are in memory; nothing is persisted.

| Entity | Fields | Rules |
|---|---|---|
| `RecordingStorageEstimate` | `bytesPerSecond: Int64` | ≥ 1; from geometry + settings (research D2) |
| `RecordingStoragePolicy` | `estimate`, `reserveBytes = 209_715_200`, `minimumStartSeconds = 60`, `checkIntervalSeconds = 5`, `horizonChecks = 2` | `allowsStart(available)`: nil → true; else `available ≥ reserve + 60 × rate`. `shouldStop(available, fileBytes, recordedSeconds)`: nil → false; else `available < reserve + 2 × 5 × max(rate, measured)` |
| `StorageProbe` | `availableBytes(at: URL) -> Int64?` | Sendable; real: `VolumeStorageProbe` |
| `RecordingWriterFault` | `afterFrames: Int`, `error: NSError` | `.diskFull(afterFrames:)` uses `AVFoundationErrorDomain` -11807 wrapping `NSPOSIXErrorDomain` 28 |
| `RecordingStopReason.lowStorage` | notice "Recording stopped because storage is almost full." | finishes and offers the file |
| `RecordingRefusal.lowStorage` | notice "There isn't enough free storage to record. Free up space and try again." | probe `refused: lowStorage` |
| `RecordingFailure.storageFull` | notice "Storage is full; the recording couldn't be saved." | partial file deleted; probe `failed: storageFull` |

## State (coordinator)

`idle → (Record, allowsStart) → recording → (shouldStop) → finishing(.lowStorage) → idle + offered`;
`recording → (writer out of space) → finishing(.writerFailed) → idle + storageFull notice, no file`.
