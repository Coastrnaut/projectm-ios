# Contract: VIS-005 Radial Waveform

## C1 RadialWaveformLayout (CPU, every platform)

- `static let windowSamples = 1_024`, `taperSamples = 256`, `inputSamples = 1_280`, `silenceThreshold = 0.0001`.
- `layout(samples: UnsafeBufferPointer<Float>, frameDuration: Double, width: Int, height: Int)`: reads the newest `inputSamples` of the mono history (oldest first; missing → 0, non-finite → 0, clamped ±1), applies the taper (VIS-005-R4), the auto gain (R5), and builds N closed segments (R2, R3, R7). No allocation.
- `normalizedSample(_:)`, `radius(_:)` (fraction of half the shorter side), `point(_:)` (pixels), `pointCount`, `segmentCount`, `thicknessPixels`, `autoGain`, `reset()`.
- `static func taperedWindow(...)` is internal; `taperEnabled` (internal, tests only) turns the taper off for the negative control.
- `tessellate(into:capacity:gain:) -> Int`, `meanLevels(gain:transfer:into:)`; conforms to `FlashRegionLayout` (regions = segments).

## C2 RadialWaveformGenerator (Metal)

- `SpectrumTextureGenerator`; `init(device:pixelFormat:configuration:) throws(VisualGeneratorError)`; `configuration` get/set; `layout`; `limiter`; `lastGain`; `downstreamLuminance`; `barCount`; `restartLoop()`.
- `encode(into:commandBuffer:bands:context:)`: `bands` is the mono history; layout → envelope gain → tessellate → `FlatShapePass.draw`.

## C3 App

- `VisualChoice.radialWaveform` (`isNative`, not `usesBars`), title "Radial Waveform".
- `RadialWaveformRing`, `RadialWaveformAmplitude` enums (raw strings, `title`, `value`).
- Settings rows `radialWaveformRingPicker`, `radialWaveformAmplitudePicker`; Settings row id `visual.radialWaveform`.
- Host view: label "Radial Waveform visualization", identifier `radialWaveform`.
