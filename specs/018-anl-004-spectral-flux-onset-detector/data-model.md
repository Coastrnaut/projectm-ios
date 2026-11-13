# Data Model: ANL-004 Spectral Flux Onset Detector

Nothing is persisted. All entities live in memory on the analysis worker.

## SpectrumFrame (ANL-001, extended)

| Field | Type | Rule |
|---|---|---|
| index | Int64 | First sample of the window on the stream's sample clock; negative only during a lead-in |
| hop | Int | 1…size; samples to the next frame's first sample (new; default size/2 in the public init) |
| size | FFTSize | as before |
| sampleRate | Double | as before |
| timestampNanoseconds | UInt64 | as before |

## SpectrumLeadIn (new)

`.none` (default; today's behavior) or `.silence` (`size − hop` zeros before sample 0 at init and
after `reset()`, using the configuration current at that moment).

## OnsetDetectorConfiguration

| Field | Default | Valid range (else error) |
|---|---|---|
| sampleRate | 44,100 Hz | finite, ≥ 8,000 (ANL-002's minimum) → `.invalidSampleRate` |
| bandCount | 64 | any `BandCount` |
| floorDecibels | −70 | −120…−20 → `.invalidFloor` |
| thresholdOffset (δ) | 0.06 | > 0 and < 1 → `.invalidThresholdOffset` |
| thresholdMultiplier (κ) | 1.5 | 0…10 → `.invalidThresholdMultiplier` |
| thresholdWindowSeconds | 0.1 | > 0 and ≤ 2 → `.invalidThresholdWindow` |
| minimumInterOnsetSeconds | 0.05 | 0…2 → `.invalidMinimumInterOnsetInterval` |

Non-finite values are rejected by the same checks.

## OnsetEvent

| Field | Type | Rule |
|---|---|---|
| sequence | UInt64 | 1, 2, 3… over the detector's lifetime; never reset |
| sampleIndex | Int64 | `frame.index + size − hop` (ANL-004-R6) |
| frameIndex | Int64 | the producing frame's index |
| strength | Float | the frame's flux, in (threshold, 1] |
| threshold | Float | the threshold it crossed |
| sampleRate | Double | the detector's sample rate |
| timestampNanoseconds | UInt64 | the producing frame's timestamp |

## SpectralFluxOnsetDetector state

| State | Initial / after reset | Update per accepted contiguous frame |
|---|---|---|
| previous normalized bands | all 0 (silence) | current normalized bands |
| previous frame (index, hop, size) | none: the first frame is contiguous by definition and is compared with silence | this frame's |
| needsBaseline | false | set true by a gap, size change, or ignored frame |
| history (≤ 128 flux values) | empty | append flux (oldest dropped) |
| armed | true | false if flux > threshold, true otherwise |
| last event sample | none | event's sample index |
| sequence counter | kept | +1 per event |
| lastFlux / lastThreshold | 0 / 0 | this frame's values (0/0 for baseline frames) |
| processedFrames / ignoredFrames | kept | counters |

State transitions per frame:

1. Wrong sample rate or magnitude count → ignoredFrames += 1, needsBaseline = true, return nil.
2. Gap (index ≠ previous index + previous hop) or size change, or needsBaseline → store the
   frame's normalized bands, lastFlux = lastThreshold = 0, needsBaseline = false, return nil.
3. Otherwise compute flux and threshold; append to history; decide arming and event.
