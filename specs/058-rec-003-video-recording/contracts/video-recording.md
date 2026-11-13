# Contract: Video Recording (REC-003)

## Package `FrameRecording` (in `Packages/Compositor`)

Plain Swift (builds on Linux):

```swift
public enum RecordingCodec: String, Sendable, CaseIterable { case hevc, h264 }
public struct RecordingSettings: Sendable, Equatable { … }           // data-model.md
public struct RecordingGeometry: Sendable, Equatable {
    public init?(drawableWidth: Int, drawableHeight: Int, maxLongSide: Int)
}
public struct RecordingTimeline: Sendable {
    public enum Admission: Equatable, Sendable { case candidate(tick: Int64), skippedRate, droppedNotIncreasing, durationReached }
    public init(settings: RecordingSettings)
    public mutating func admit(presentationNanoseconds: UInt64) -> Admission
    public mutating func markWritten(tick: Int64)
    public var endTick: Int64? { get }
}
public final class RecordingFrameGate: Sendable { init(capacity:), tryAcquire(), release(), inFlight, maxInFlight }
public struct RecordingStatistics, enum RecordingStopReason, enum RecordingRefusal, enum RecordingFailure
public struct RecordedVideo
public enum RecordingGate { static func refusal(visualAvailable:recordable:outputLive:paused:busy:) -> RecordingRefusal? }
```

Apple platforms (`canImport(AVFoundation)`):

```swift
public struct RecordedVideoInfo { … }
public enum RecordedVideoInspector { public static func inspect(_ url: URL) async -> RecordedVideoInfo? }
```

Metal (`canImport(Metal) && !COMPOSITOR_NO_METAL`):

```swift
public final class MetalFrameRecorder: @unchecked Sendable {
    public init(device: MTLDevice, url: URL, drawableWidth: Int, drawableHeight: Int,
                settings: RecordingSettings = .standard, realTime: Bool = true) throws(RecordingFailure)
    public let geometry: RecordingGeometry
    public let codec: RecordingCodec
    public enum FrameOutcome { case submitted, skippedRate, dropped, sizeChanged, durationReached, finished, failed }
    /// Render thread. Never waits. `encode` draws the frame into the given texture
    /// (bgra8Unorm_srgb, geometry.sourceWidth × sourceHeight) using `commandBuffer`.
    public func recordFrame(presentationNanoseconds: UInt64, drawableWidth: Int, drawableHeight: Int,
                            commandBuffer: MTLCommandBuffer, encode: (MTLTexture) -> Bool) -> FrameOutcome
    public var statistics: RecordingStatistics { get }
    public var recordedSeconds: Double { get }
    public func finish() async -> Result<RecordedVideo, RecordingFailure>   // idempotent
    public func cancel() async                                             // deletes the file
}
```

Rules: `recordFrame` is called by one thread (the frame loop); after `finish` starts it returns
`.finished` and takes nothing. Frames are appended in submission order on the writer's serial queue.
A failed command buffer releases its frame (counted as dropped).

## `Compositor.encodeOutput(into:commandBuffer:) -> Bool`

Encodes the output pass of the frame `composite` just encoded (composite × the flash guard's gain)
once more into `target` (a `supportedOutputFormats` render target no larger than the output), with
the same command buffer. Returns false, encoding nothing, when no frame was composited into this
command buffer, the target is larger than the composite, or its format is unsupported. Frames shown
are unchanged.

## App

```swift
@MainActor protocol VideoRecordingSource: AnyObject {
    var recordingDevice: MTLDevice { get }
    var recordingDrawableSize: CGSize { get }      // pixels
    var isPresentingFrames: Bool { get }           // false while suspended (PERF-011)
    var videoRecording: VideoRecordingTap? { get set }
}
```

Hosts: Camera, Photo, Video, Text (compositor `encodeOutput`), Circular/Linear Spectrum (blit).
`VideoRecordingCoordinator`: `toggle()`, `state`, `elapsedText`, `notice`, `showMover`, `fileToMove`,
`moverFinished(_:)`, DEBUG `probe`. Controls item `id: "record"` (title "Record" / "Stop recording");
indicator `id: "recordingIndicator"` (label "Recording, 0:05"). DEBUG launch argument
`-uitestRecordingDirectory <name>`; probe element `videoRecordingProbe`.

## Notices

| Event | Notice |
|---|---|
| Refused: blacked out | "Restore the output to record." |
| Refused: paused | "Resume to record." |
| Refused: projectM | "Recording is available for the Camera, Photo, Video, Text and spectrum visuals." |
| Stop: 10 minutes | "Recording stopped at the 10-minute limit." |
| Stop: background | "Recording stopped when the app left the screen." |
| Stop: paused | "Recording stopped when you paused." |
| Stop: blacked out | "Recording stopped when the output was blacked out." |
| Stop: visual changed | "Recording stopped when the visual changed." |
| Stop: size changed | "Recording stopped when the picture size changed." |
| Stop: presentation lost | "Recording stopped when the visual stopped drawing." |
| Failure | "The recording couldn't be finished." |
| Too few frames | "Nothing was recorded." |
| Saved | "Recording saved." |
