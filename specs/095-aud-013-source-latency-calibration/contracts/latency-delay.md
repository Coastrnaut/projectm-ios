# Contract: Latency delay (AUD-013)

## C1 `LatencyOffset` (AudioCore)

- `minimumMilliseconds = 0`, `maximumMilliseconds = 250`, `maximumDelayFrames = 11_025`,
  `lineCapacityFrames = 33_075`, `rendererExcessFrames = NormalizedPCMRing.freshnessFrames` (2,205).
- `validatedMilliseconds(_:) -> Double`: NaN → 0; clamp to 0…250; rounded to whole ms.
- `frames(milliseconds:) -> Int`: `round(validated × 44.1)`.
- `estimateMilliseconds(mode:outputLatency:ioBufferDuration:) -> Double`: `.microphone` → 0;
  otherwise `validated(round((max(0, ol) + max(0, io)) × 1,000))` with non-finite inputs as 0.

## C2 `LatencyOffsetControl` (AudioCore, Sendable)

- `init(targetFrames: Int = 0)`; `targetFrames` get/set (relaxed atomic; set clamps to
  0…`maximumDelayFrames`).

## C3 `LatencyDelayReader` (AudioCore; `NormalizedPCMReader`, `AnalysisSessionReporting`)

- `init(_ reader:, control:, mode: .analysis | .renderer)`; one consumer thread.
- `read(into:maxFrames:)`:
  1. `.analysis`: if the wrapped generation changed → empty the line, applied = target.
  2. target = `control.targetFrames`. If target = applied = 0 and the line is empty → return the
     wrapped read unchanged (C3.P: bit-identical, no copy).
  3. Pull every frame the wrapped reader has into the line (overflow: drop oldest, counted).
  4. Slew: applied moves toward target by at most ⌈pulled / 4⌉ (0 when nothing was pulled).
  5. `.renderer`: if buffered − applied > 2,205 → drop the oldest excess (counted).
  6. Release min(maxFrames, max(0, buffered − applied)) oldest frames into `dst`, unchanged.
- `analysisSessionGeneration`: the wrapped reader's (0 when it reports none).
- Diagnostics: `appliedDelayFrames`, `bufferedFrames`, `droppedFrames`.
- Steady state: each sample leaves the reader `applied` frames after it entered (sample clock).

## C4 App wiring

- `AppCoordinator.trimmedAnalysisTap` = `latencyOffset.analysisDelayed(noiseGate.gated(...))`.
- `renderer.attach(pcm: latencyOffset.rendererDelayed(manager.normalizedOutput))`.
- `manager.onSessionMode` and `start(_:)` set `latencyOffset.activeMode`; `stop()` sets nil.

## C5 Settings section

- Picker `latencyOffsetSource` ("Delay for source"), slider `latencyOffsetSlider` ("Visual delay",
  value = readout), readout `latencyOffsetValue` ("0 ms"), buttons `latencyOffsetEstimate`
  ("Estimate from Output") and `latencyOffsetReset` ("Reset").
