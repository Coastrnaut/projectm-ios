# Contract: VideoLayer (MED-002)

## Decoder boundary (MED-002-R15; MED-014 seam)

```swift
public protocol VideoFrameReading: AnyObject {
    associatedtype Frame
    /// Opens the stored copy at `startNanoseconds` (0…duration) on the decode thread.
    func open(startNanoseconds: Int64) throws(VideoImportError) -> VideoTrackInfo
    /// The next picture in presentation order (pts on the file's own timeline), or nil at the end.
    func next() throws(VideoImportError) -> (pts: Int64, frame: Frame)?
    /// Releases the reader (called on the decode thread before reopen and at the end).
    func close()
}
```

The pipeline owns looping and seeking (it calls `open` again); readers never loop.

## Pipeline (plain Swift)

```swift
public final class VideoDecodePipeline<Reader: VideoFrameReading>: @unchecked Sendable {
    public init(reader: Reader, capacity: Int = 3, seekThresholdNanoseconds: Int64 = 1_000_000_000)
    public func start(atNanoseconds: Int64)          // starts the decode thread
    public func take(upTo playback: Int64) -> TimedFrame<Reader.Frame>?   // render side; never waits
    public func stop()                               // cancels; the thread exits; frames released
    public var statistics: VideoPipelineStatistics { get }
    public var state: VideoPipelineState { get }
    public func waitUntilIdle(timeout: Double) -> Bool   // tests: queue full, failed, or waiting
}
```

## Layer source (Metal)

```swift
public final class VideoLayerSource: LayerSource {
    layerName "video"; fallback .transparent
    public var content: VideoLayerContent        // .none | .file(URL); setting restarts playback at 0
    public var state: VideoLayerState { get }
    public var onStateChange: (@MainActor @Sendable (VideoLayerState) -> Void)?
    public func suspendDecoding()                // background: release decoder and pictures
    public private(set) var framesShown: Int
    public private(set) var shownPresentationNanoseconds: Int64?   // diagnostics, tests
    public var statistics: VideoPipelineStatistics
}
```

`render` advances the clock, takes the frame for the playback time, draws it (aspect fill, rotation,
sRGB → linear, alpha 1) or throws `.notReady` (nothing yet, empty, failed). It never decodes, waits
or does I/O.

## Import (AVFoundation)

```swift
public enum VideoProbe { static func check(_ url: URL, limits: VideoImportLimits) async throws(VideoImportError) -> VideoTrackInfo }
public enum VideoSanitizer { static func copy(_ source: URL, to destination: URL, limits: VideoImportLimits) async throws(VideoImportError) -> VideoTrackInfo }
```
