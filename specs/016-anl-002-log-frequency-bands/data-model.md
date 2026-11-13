# Data model: ANL-002 Log-frequency Bands

Nothing is persisted. All types live in memory on the analysis worker (ANL-001-R14).

## BandCount (enum, `AnalysisFeatures`)

| Case | Raw value | Ratio per band (20 Hz–20 kHz) | Octaves per band |
|---|---|---|---|
| `b16` | 16 | 1.5399 | 0.623 |
| `b32` | 32 | 1.2409 | 0.311 |
| `b64` | 64 | 1.1140 | 0.156 |
| `b128` | 128 | 1.0555 | 0.078 |

`BandCount(rawValue:)` returns nil for any other count (ANL-002-R1).

## BandLayout (struct, Sendable, Equatable) — one precomputed table

| Field | Type | Rule |
|---|---|---|
| `bandCount` | `BandCount` | |
| `size` | `FFTSize` | ANL-001 size |
| `sampleRate` | `Double` | finite, ≥ 8,000 (research ANL-002-D8) |
| `lowerEdge` | `Double` | 20 Hz (`BandLayout.lowerEdgeHz`) |
| `upperEdge` | `Double` | min(20,000, sampleRate / 2) |
| `edges` | `[Double]` | B + 1 values, `edges[i] = 20 · (upperEdge/20)^(i/B)`; `edges[B] == upperEdge` exactly |
| internal `firstBin`, `binCount`, `offset` | `[Int]` (B each) | bins with weight > 0 are `firstBin ..< firstBin + binCount` |
| internal `weights` | `[Float]` | concatenated per band; each in (0, 1] |
| internal `scale` | `[Float]` (B) | `1 / (1.5 · min(1, W_b))` |

Derived queries: `centerFrequency(ofBand:)` (geometric mean of its edges), `widthInBins(ofBand:)`
(W_b, Double), `binRange(ofBand:)`, `weights(ofBand:)` (array copy, off the real-time path),
`band(containingFrequency:)` (nil outside [lowerEdge, upperEdge)), `ownerBand(ofBin:)` (largest
weight, lower band on a tie; nil for bin 0 and bins no band touches).

Invariants (tested): every band has `binCount ≥ 1` and W_b > 0; for every bin, Σ_b w_bk ≤ 1 + 1e-6;
edges strictly increasing.

Error: `BandLayoutError.invalidSampleRate(Double)`.

## BandReducer (final class, not Sendable)

| Field | Meaning |
|---|---|
| `sampleRate` | the rate all its layouts were built for |
| `resolvedBackend` | `.accelerated` or `.portable` (ANL-001's `SpectrumBackend`) |
| layouts | 20 `BandLayout`s, indexed by (count, size) |
| power scratch | 4,097 Floats, preallocated |

Lifecycle: created once per sample rate (off the real-time path); `reduce` is called per frame with
any (size, count); no state carries between calls, so there is nothing to reset.

## BandScale (enum, Sendable, Hashable) and BandMath

`BandScale.linear(reference: Float)` (default reference 1.0) and
`BandScale.decibels(floorDecibels: Float)` (default −80). `BandMath.normalizedLinear`,
`BandMath.normalizedDecibels`, `BandMath.normalize(_:count:scale:)` (in place, allocation-free).
Output always in [0, 1]; 0 in → 0 out.

## Band value

Linear sine-equivalent amplitude: finite, ≥ 0; a steady sine of amplitude A whose energy lies in one
wide band reads A; an all-zero spectrum reads +0.0 in every band.
