# Contract: VIS-007 Mandala Symmetry

## C1 MandalaLayout (CPU, every platform)

- `layout(bands:atNanoseconds:width:height:)`: band groups (R2) → sector 0's petal (R3; one, or two with Mirror) → N rotated copies at angle ψ (R4, R5). Region k = sector k / regionsPerSector, petal, step. Color `palette.color(bar: step, of: 12)` with alpha 0.5 + 0.3·overall.
- `sectorCount`, `regionsPerSector`, `regionCount`, `angle`, `alpha`, `groups`; `quad(_:)` (4 corners in pixels: inner-left, outer-left, outer-right, inner-right, y down); `tessellate(into:capacity:gain:) -> Int` (6 vertices per region), `meanLevels(gain:transfer:into:)`; conforms to `FlashRegionLayout`. No allocation per frame.
- Rotation: `angle(atNanoseconds:)` reads the anchor; a change of the effective speed re-anchors at the frame's time.

## C2 MandalaGenerator (Metal)

- `SpectrumTextureGenerator`; `init(device:pixelFormat:configuration:) throws(VisualGeneratorError)`; `configuration` get/set; `layout`; `limiter`; `lastGain`; `downstreamLuminance`; `barCount` (carried); `restartLoop()` (the limiter's slew; the envelope's history is kept, FX-019-R11).
- `encode(into:commandBuffer:bands:context:)`: Reduce-flashing slew of `bands` → layout at `context.timeNanoseconds` → envelope gain → tessellate → `FlatShapePass.draw`.

## C3 App

- `VisualChoice.mandala` (`isNative`, not `usesBars`), title "Mandala"; `MandalaPetalStyle` titles Petal, Round, Spike; `NativeSpectrumStyle.mandala(symmetry:mirror:petal:)`.
- Settings rows `mandalaSymmetryPicker`, `mandalaMirrorToggle`, `mandalaPetalPicker`; host view label "Mandala visualization", identifier `mandala`, value "<N>-fold, Mirror on|off, <petal>, <glow>".
- `NativeSpectrumHost.reduceMotion` (set by the coordinator from `settings.systemReduceMotion`) reaches the mandala's configuration.
