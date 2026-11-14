# Contract: VIS-006 Beat Pulse Rings

## C1 BeatRingField and BeatRingLayout (CPU, every platform)

- `BeatRingField`: `emit(atNanoseconds:minimumInterval:) -> Bool` (false: inside the rate cap or earlier than the newest birth); full → the oldest slot is replaced; `rings(at:life:into:)` fills live rings oldest first, returns the count (expired rings are pruned); `reset()`.
- `BeatRingLayout`: `layout(field:atNanoseconds:width:height:)` builds 64 annulus segments per live ring (R3, R7), colors `palette.color(bar: sequence % 16, of: 16)` with alpha α. `ringCount`, `ring(_:)`, `segmentCount`, `thicknessPixels`; `tessellate(into:capacity:gain:) -> Int`, `meanLevels(gain:transfer:into:)`; conforms to `FlashRegionLayout` (regions = segments). No allocation.

## C2 BeatRingGenerator (Metal)

- `SpectrumTextureGenerator`; `init(device:pixelFormat:configuration:) throws(VisualGeneratorError)`; `configuration` get/set; `field`; `layout`; `limiter`; `lastGain`; `downstreamLuminance`; `barCount`; `restartLoop()` (clears the rings and the limiter's slew; the envelope's history is kept, FX-019-R11).
- `emitRing(atNanoseconds:flashConfiguration:) -> Bool`: applies `BeatRingConfiguration.minimumInterval(for:)`.
- `encode(into:commandBuffer:bands:context:)`: `bands` is ignored; layout at `context.timeNanoseconds` → envelope gain → tessellate → `FlatShapePass.draw`.

## C3 BeatRingTrigger (VisualBandFeed)

- `mutating func shouldEmit(_ event: AnalysisEvent) -> Bool`: `.beat` with confidence ≥ 0.5 → true (remembers its time); `.transient(.kick, …)` → true when no confident beat in the previous 2 s; session markers forget the beat; everything else false.

## C4 App

- `VisualChoice.beatRings` (`isNative`, not `usesBars`), title "Beat Rings"; `BeatRingLife` enum (raw strings, `title`, `seconds`).
- Settings row `beatRingsLifePicker`; host view label "Beat Rings visualization", identifier `beatRings`, value "<life> ring life, <glow>".
