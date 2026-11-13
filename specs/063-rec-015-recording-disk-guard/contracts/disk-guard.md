# Contract: recording disk guard (REC-015)

## FrameRecording (package API)

```swift
public protocol StorageProbe: Sendable { func availableBytes(at directory: URL) -> Int64? }
public struct VolumeStorageProbe: StorageProbe          // Apple platforms only
public struct RecordingStorageEstimate: Sendable, Equatable {
    public let bytesPerSecond: Int64
    public init(bytesPerSecond: Int64)
    public init(geometry: RecordingGeometry, settings: RecordingSettings)
}
public struct RecordingStoragePolicy: Sendable, Equatable {
    public static let reserveBytes: Int64          // 209_715_200
    public static let minimumStartSeconds: Int64   // 60
    public static let checkIntervalSeconds: Int64  // 5
    public init(estimate: RecordingStorageEstimate)
    public var bytesNeededToStart: Int64
    public func allowsStart(availableBytes: Int64?) -> Bool
    public func shouldStop(availableBytes: Int64?, fileBytes: Int64?, recordedSeconds: Double) -> Bool
}
public enum RecordingStorage { public static func fileBytes(at url: URL) -> Int64? }
extension RecordingFailure {
    case storageFull
    public static func isOutOfSpace(_ error: any Error) -> Bool
    public static func fromWriterError(_ error: (any Error)?, fallback: String) -> RecordingFailure
}
public struct RecordingWriterFault: Sendable { afterFrames: Int; error: NSError; static func diskFull(afterFrames:) }
MetalFrameRecorder.init(device:url:drawableWidth:drawableHeight:settings:realTime:fault:)   // fault defaults to nil
```

## App (`VideoRecordingCoordinator`)

- `init(..., storageProbe: any StorageProbe, storageCheckInterval: Duration?, writerFault: RecordingWriterFault?)`
  (defaults: `VolumeStorageProbe()`, 5 s, nil; DEBUG `-uitestStorage` overrides the first two).
- `checkStorage() async`: one sample (tests call it with `storageCheckInterval` nil).
- Probe strings: `refused: lowStorage`, `failed: storageFull`; DEBUG offered recordings are read back
  into the probe (`video <codec> <w>x<h> frames=<n> …`).
- DEBUG launch option `-uitestStorage low` (always 50 MB available) or `-uitestStorage dropAfter:<n>`
  (the first n reads 64 GB, then 50 MB); either sets the storage interval to 1 s.
- Notices (identifier `videoRecordingNoticeText`): the three texts in data-model.md.
