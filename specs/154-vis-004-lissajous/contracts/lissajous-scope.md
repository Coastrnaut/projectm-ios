# Contract: VIS-004 Lissajous Scope

## C1 — Stereo history (`VisualBandFeed.WaveformTap`)

- `stereoOutput: WaveformFrameBuffer`: after each forwarded read with frames > 0, holds the newest
  2,048 frames as interleaved L, R (oldest first; zeros before the first frames), `totalWritten` =
  frames read in total.
- The forwarded read, its return value, `output` (mono history) and the session generation are
  unchanged (VIS-003 contract C3).
- No allocation per read.

## C2 — Layout (`VisualGenerators.LissajousLayout`, builds on Linux)

```swift
public final class LissajousLayout: FlashAreaLevelSource {
    public static let windowFrames: Int          // 1,024
    public static let snapshotCapacity: Int      // 8
    public static let snapshotPoints: Int        // 128
    public static let maximumVertexCount: Int
    public var configuration: LissajousConfiguration   // clamped; a mode change clears snapshots
    public private(set) var autoGain: LissajousAutoGain
    public private(set) var pointCount: Int      // 0 when silent
    public private(set) var snapshotCount: Int
    public func layout(stereo: UnsafeBufferPointer<Float>, frameDuration: Double, width: Int, height: Int)
    public func point(_ j: Int) -> (x: Double, y: Double)            // pixels, y down
    public func normalizedPoint(_ j: Int) -> (u: Double, v: Double)  // −1…1, y up
    public func snapshotWeight(_ i: Int) -> Double                   // i = 0 oldest
    public func reset()                                              // gain + snapshots + clock
    public func tessellate(into: UnsafeMutablePointer<SpectrumVertex>, capacity: Int, gain: Float) -> Int
    public func meanLevels<T: FrameLuminanceTransfer>(gain: Float, transfer: T, into: UnsafeMutableBufferPointer<FlashLevels>)
}
```

- `stereo` is interleaved, oldest first; the newest `windowFrames` frames are used (fewer → missing
  frames read 0). Non-finite samples read 0.
- Silence (peak < 0.0001): `pointCount` 0, no snapshot taken; snapshots still age.
- Tessellation order: snapshots oldest first, then the live trace; colors × weight (premultiplied).

## C3 — Generator (`VisualGenerators.LissajousGenerator`, Metal)

`SpectrumTextureGenerator`; `encode(bands:)` takes the interleaved stereo history; the frame context's
`frameDuration` drives gain and persistence; FX-019 gain over the layout's areas; `restartLoop()`
resets the limiter's slew and the layout (gain, snapshots).

## C4 — App

- `VisualChoice.lissajous` ("Lissajous", native); `NativeSpectrumStyle.lissajous(mode:persistence:)`,
  accessibility identifier `lissajous`, value "<X/Y|Mid/Side>, Persistence <on|off>, <glow>".
- Settings identifiers: `visual.lissajous`, `lissajousModePicker` (segments "X/Y", "Mid/Side"),
  `lissajousPersistenceToggle`.
- The host sets the generator's half-life from `persistenceHalfLife(enabled:clamp:)` on every style or
  `safetyClamp` change.
