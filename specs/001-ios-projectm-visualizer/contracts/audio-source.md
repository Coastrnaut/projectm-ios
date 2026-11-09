# Contract: AudioSource, CaptureManager, AudioStateClassifier

Package boundary: **CaptureKit** (sources, manager) depends on **AudioCore** (formats, ring,
classifier). Nothing above CaptureKit sees ScreenCaptureKit or AVFAudio types.

Illustrative Swift signatures. Names may be refined during implementation; the guarantees may not.

## AudioSource

```swift
public protocol AudioSource: AnyObject, Sendable {
    var mode: AudioSourceMode { get }
    var availability: SourceAvailability { get }      // evaluated before start
    /// Requests permission / presents system UI as needed. Throws StopReason-mapped errors.
    func start(into sink: PCMSink) async throws
    /// Idempotent. Returns within 1 s. No callbacks into `sink` after return.
    func stop() async
    var events: AsyncStream<SourceEvent> { get }      // interruption, routeChange, endedBySystem, formatChange
}
```

Guarantees:

1. `start` presents the system picker (capture) or the permission prompt (mic) only when called
   from a user action. It never starts silently (FR-002).
2. Real-time callbacks write only to `PCMSink.write(_:)`, which is allocation-free and lock-free.
   They never call `async` code, log, or touch the main actor.
3. `stop()` is idempotent and safe to call concurrently with an in-flight `start` (FR-052).
   `CaptureManager` relies on this: Stop, Restart or choosing another source cancels a start that
   is still in flight (for example waiting on the system picker), and the attempt ends as
   "Not started — cancelled" (owner review 2026-11-08, ADR-0001 ruling 7).
4. After `stop()` returns, the source holds no reference to `sink`.
5. Source-specific types (`SCStream`, `CMSampleBuffer`, `AVAudioPCMBuffer`) never cross this
   boundary.

## PCMSink (AudioCore)

```swift
public final class PCMSink: @unchecked Sendable {
    /// Real-time safe. Copies `frameCount` frames into the SPSC ring; drops oldest on overflow.
    public func write(_ buffer: UnsafePointer<AudioBufferList>, format: AudioFormat,
                      frameCount: Int, hostTime: UInt64)
    public var droppedFrames: UInt64 { get }
}
```

## CaptureManager

```swift
@MainActor public final class CaptureManager: ObservableObject {
    @Published public private(set) var activeMode: AudioSourceMode?
    @Published public private(set) var state: AudioState
    @Published public private(set) var stopReason: StopReason?
    @Published public private(set) var diagnostics: AudioDiagnosticsSnapshot  // ≥ 1 Hz (FR-020)
    public func availableSources() -> [AudioSourceMode: SourceAvailability]
    public func select(_ mode: AudioSourceMode) async   // stops current first (FR-016)
    public func stop() async                             // ≤ 1 s (FR-007)
    public func restart() async                          // one-tap restart (FR-055)
    public var normalizedOutput: NormalizedPCMReader { get } // consumed by the bridge
}
```

Guarantees: one active source (FR-001). The `state` published is exactly the classifier output.
`waiting` is shown during switches (FR-016).

## AudioStateClassifier (AudioCore, pure)

```swift
public struct AudioStateClassifier {
    public init(thresholds: ClassifierThresholds)
    public mutating func dataArrived(at t: Duration, peakDBFS: Float, frames: Int) -> AudioState
    public mutating func tick(at t: Duration) -> AudioState      // timeouts with no data
    public mutating func lifecycle(_ e: LifecycleEvent) -> AudioState
    public var prolongedSilenceHint: Bool { get }
}
```

Guarantees: deterministic for a given input timeline; implements the transition table in
[data-model.md](../data-model.md). This is the unit-test surface for SC-002/SC-003.

## NormalizedPCMReader

```swift
public protocol NormalizedPCMReader: Sendable {
    /// Reads up to `maxFrames` interleaved stereo Float32 @ 44.1 kHz. Non-blocking; returns 0 when empty.
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int
}
```
