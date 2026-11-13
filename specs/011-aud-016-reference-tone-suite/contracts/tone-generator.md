# Contract: tone generator and playback (AUD-016)

## AudioCore API (Foundation only; builds with `-DAUDIOCORE_NO_AVFAUDIO` and on Linux)

```swift
public struct ToneFormat: Sendable, Hashable {
    public let sampleRate: Int, channels: Int
    public init(sampleRate: Int, channels: Int) throws(ToneError)
    public static let canonical: ToneFormat          // 48,000 Hz, 2 channels
}
public enum ToneSignal: Sendable, Hashable { case sine(SineTone), sweep(SweepTone), pulses(PulseTrain), silence }
public struct ToneGenerator: Sendable {
    public init(signal: ToneSignal, format: ToneFormat) throws(ToneError)
    public func sample(frame: Int64, channel: Int) -> Float
    public func render(into: UnsafeMutablePointer<Float>, frames: Int, startFrame: Int64)          // interleaved
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int, startFrame: Int64)
    public func interleaved(frames: Int, startFrame: Int64 = 0) -> [Float]
}
public enum ReferenceToneCatalog { static let version: Int; static let fixtures: [ReferenceToneFixture]; static func fixture(id:) -> ReferenceToneFixture? }
```

Guarantees:

1. `sample(frame:channel:)` depends on the signal, the format, the frame and the channel only.
   `render(…, startFrame: s)` for `frames: n` equals `sample(frame: s+i, …)` for `i < n`.
2. Output is bit-identical on every host (research AUD-016-D1).
3. `render` does not allocate, lock or call into the system; it may be used on a real-time thread.
4. Frames before 0 are not defined: `startFrame` must be ≥ 0 (precondition).
5. A sine with integer frequencies at an integer rate repeats exactly every `rate` frames; a sweep
   every `seconds × rate` frames; pulses every whole number of beats.

## CaptureKit playback

- `InAppPlaybackTrack.tone(fixture)` loads the fixture's 48 kHz stereo variant, one loop, into an
  in-memory buffer when the track is started, replaced or rebuilt (AUD-014 media-services reset).
  Failure to allocate: `SourceError(.inAppPlaybackFailed)`; no other track plays.
- Played as an order of one: it loops without a gap and never reports an end. Seek, pause, resume,
  Stop playback, Previous and Next behave as for the reference track (AUD-006 transport contract):
  after a cut the first delivered frame is the fixture's frame at the new position.
- At a 48 kHz output, every delivered frame equals the fixture's frame exactly (research
  AUD-016-D4); at another rate, see the tolerance in `fixture-catalog.md`.
- The tone is never written to disk and adds no stored data.
