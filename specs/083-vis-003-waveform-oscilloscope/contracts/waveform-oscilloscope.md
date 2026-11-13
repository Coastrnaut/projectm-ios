# Contract: VIS-003 Waveform Oscilloscope

## C1 WaveformTrigger

```swift
public final class WaveformTrigger {
    public static let maximumCrossings = 32
    public static let referencePoints = 64
    public init()
    /// Finds the window start in `history` (oldest first) for a window of `windowSamples`.
    public func locate(in history: UnsafeBufferPointer<Float>, windowSamples: Int) -> WaveformTriggerResult
    public func reset()   // forgets the reference
}
```

- Deterministic: the same history and state give the same result. No allocation.
- `windowSamples` is clamped to 2…history.count; an empty history gives start 0, `.freeRun(.silence)`.

## C2 WaveformFrameBuffer

```swift
public final class WaveformFrameBuffer: @unchecked Sendable {
    public static let capacity = 4_096
    public func write(_ source: UnsafeBufferPointer<Float>, totalWritten: UInt64)   // one writer
    public func readLatest(into: UnsafeMutablePointer<Float>, capacity: Int) -> UInt64?   // one reader; nil if nothing new
}
```

## C3 WaveformTap (VisualBandFeed)

```swift
public final class WaveformTap: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    public init(_ reader: any NormalizedPCMReader)
    public let output: WaveformFrameBuffer
    public func read(into: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int   // forwards, then folds
    public var analysisSessionGeneration: UInt64   // forwarded, 0 if the wrapped reader has none
}
```

Exactly one reading thread (the analysis worker). The bytes returned are exactly the wrapped reader's.

## C4 OscilloscopeGenerator

`SpectrumTextureGenerator` (VIS-002): `encode(into:commandBuffer:bands:context:)` reads `bands` as the
sample history (oldest first). Per frame: trigger → layout for the target size → envelope gain over 17
areas (after `downstreamLuminance`) → tessellate → `FlatShapePass`. `barCount` is kept for the host
(carried over between styles) and does not affect drawing. `restartLoop()` forgets the trigger
reference; the envelope history is kept (FX-019-R11).

## C5 App

- `VisualChoice.oscilloscope` (`"oscilloscope"`, "Oscilloscope", `isNative`).
- `NativeSpectrumStyle.oscilloscope(line: OscilloscopeLine, windowMilliseconds: Int)`; identifier
  `oscilloscope`; label "Oscilloscope visualization"; value "<window> ms, <glow>".
- Settings identifiers: `visual.oscilloscope`, `oscilloscopeLinePicker` (Thin, Medium, Thick),
  `oscilloscopeWindowPicker` (10 ms, 20 ms, 40 ms).
