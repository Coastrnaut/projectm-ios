# Data model: ANL-001 Windowed FFT

Nothing is persisted. All types live in memory on the analysis worker (ANL-001-R14).

## FFTSize (enum, `AnalysisFeatures`)

| Case | Raw value (samples) | log2 | Bins (N/2 + 1) | Bin width at 44.1 kHz | at 48 kHz |
|---|---|---|---|---|---|
| `n512` | 512 | 9 | 257 | 86.133 Hz | 93.750 Hz |
| `n1024` | 1,024 | 10 | 513 | 43.066 Hz | 46.875 Hz |
| `n2048` | 2,048 | 11 | 1,025 | 21.533 Hz | 23.438 Hz |
| `n4096` | 4,096 | 12 | 2,049 | 10.767 Hz | 11.719 Hz |
| `n8192` | 8,192 | 13 | 4,097 | 5.383 Hz | 5.859 Hz |

`FFTSize(samples:)` returns nil for any other count (ANL-001-R2). `maximum = .n8192`.

## ChannelMode (enum)

`mid` (default, `(L + R)·0.5`), `left`, `right`. Applies to interleaved stereo input; mono input is
taken as is (ANL-001-R5).

## SpectrumConfiguration (struct, Sendable, Hashable)

| Field | Type | Rule | Default |
|---|---|---|---|
| `size` | `FFTSize` | one of five | `.n2048` |
| `hop` | `Int` | 1 … `size.rawValue` | `size.rawValue / 2` |
| `sampleRate` | `Double` | finite, > 0 | 44,100 (the normalized stream) |
| `channelMode` | `ChannelMode` | | `.mid` |

`init(size:hop:sampleRate:channelMode:) throws(SpectrumConfigurationError)`; errors:
`hopOutOfRange(hop, size)`, `invalidSampleRate(rate)`. Invalid configurations never reach an analyser.

## SpectrumFrame (struct, Sendable, Equatable) — frame metadata

| Field | Meaning |
|---|---|
| `index` | first input sample of the window, counted since the stream's creation or last reset (ANL-001-R7) |
| `size` | `FFTSize` used |
| `sampleRate` | Hz |
| `timestampNanoseconds` | injected clock reading when the frame was computed (default `MonotonicClock.nowNanoseconds()`) |

The magnitudes themselves are a view (`UnsafeBufferPointer<Float>`, `size.binCount` values) owned
by the stream or analyser and valid until its next computation; `copyMagnitudes(into:)` copies them.

## Magnitude values

Linear amplitude, `m[k] ≥ 0`, finite. Bin-centred sine of amplitude A → A at its bin; constant A → A
at bin 0. Relation to the raw DFT: `m[k] = |X[k]|·4/N` (0 < k < N/2), `|X[k]|·2/N` (k = 0, N/2).
`SpectrumMath.decibels(m) = max(−120, 20·log10 m)`, −120 for m = 0.

## Bin helpers (`FFTSize` and `SpectrumConfiguration`)

- `binCount = N/2 + 1`
- `binWidth(sampleRate:) = R/N`
- `frequency(ofBin: k, sampleRate:) = k·R/N`
- `nearestBin(toFrequency: f, sampleRate:) = clamp(round(f·N/R), 0, N/2)` (ties away from zero, like
  the catalog's `nearestBin`)

## Analysis tap (AudioCore, `NormalizedPCMRing`)

| Field | Meaning |
|---|---|
| `analysisTapCapacityFrames` | 0 = no tap (default); otherwise the tap's capacity in stereo frames (`analysisTapDefaultCapacityFrames` = 22,050, 0.5 s) |
| `analysisTap` | `NormalizedPCMReader?`: reads the tap (no freshness rule), nil when disabled |
| `analysisTapAvailableFrames` | frames buffered in the tap |
| `analysisTapDroppedFrames` | frames dropped from the tap by drop-oldest overflow since the last `reset()` |

Lifecycle: `write` → both rings; `discardBuffered()` → both emptied, counters kept; `reset()` → both
emptied, counters restart.

## SpectrumStream state

FIFO of 16,384 mono floats, `buffered` count, `nextIndex` (Int64, index of the next frame's first
sample), configuration. `reset()` empties the FIFO and sets `nextIndex = 0`. `setConfiguration(_:)`
keeps the FIFO and `nextIndex` (ANL-001-R17).
