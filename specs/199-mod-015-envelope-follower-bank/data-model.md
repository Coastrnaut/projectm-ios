# Data Model: MOD-015 Envelope Follower Bank

## BandEnvelopeProfile (enum, `String` raw value, CaseIterable)

| Case | Raw | Index | Attack τ | Release τ |
|---|---|---|---|---|
| fast | `fast` | 0 | 0.010 s | 0.080 s |
| medium | `medium` | 1 | 0.080 s | 0.350 s |
| slow | `slow` | 2 | 0.400 s | 1.600 s |

`envelope: AudioFeatureEnvelope` gives the pair; `title` is "fast"/"medium"/"slow".

## BandEnvelopeBank (class, one owner)

| Field | Meaning |
|---|---|
| `maximumBands` = 128 | capacity |
| `profiles` | the three `AudioFeatureEnvelope`s (injectable for independence tests; default the table above) |
| state | 384 Doubles, band-major `band·3 + profileIndex`, start 0 |
| `bandCount` | bands of the last advance; a change resets every state to 0 |
| `lastTime: UInt64?` | Δt rules (contract B2) |
| `values` | `UnsafeBufferPointer<Double>` over `bandCount·3` states (borrowed) |

Transitions: `advance(bands:timeNanoseconds:)` updates; `reset()` zeroes and forgets time.

## AudioFeatureSource.bandEnvelope(Int, BandEnvelopeProfile)

ID `audio.bandEnvelope.<raw>.<band>` (band 0…127, no sign, no leading zeros). Value: `frame.bandEnvelopes[band·3 +
index]`, finite and clamped 0…1; 0 when out of range.
