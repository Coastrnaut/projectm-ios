# Fixture catalog: reference tones, version 1

Source of truth in code: `Packages/AudioCore/Sources/AudioCore/ReferenceTones/ReferenceToneCatalog.swift`.
Golden hashes in code: `Packages/AudioCore/Tests/AudioCoreTests/ReferenceToneGoldens.swift`.
This file and the code must agree; `ReferenceToneCatalogTests` checks the code, and this table is
copied from the test's output.

## Rules

- A fixture is one loop of `loopSeconds` (10 s) starting at frame 0. Samples are 32-bit float;
  the hash is SHA-256 over the little-endian bytes of the interleaved samples (frame 0 left,
  frame 0 right, frame 1 left, …).
- Variants: 44,100 Hz and 48,000 Hz; mono and stereo where `layouts` allows. A mono variant of a
  fixture with equal channels is its left channel; the stereo variant has two equal channels.
- In-app playback always uses the 48,000 Hz stereo variant (AUD-016-R23).
- Generation is deterministic by construction (research AUD-016-D1, D2). Changing any sample of any
  fixture requires a new catalog version and new hashes; existing IDs never change meaning.
- Peak amplitude never exceeds 0.5 (−6.02 dBFS).

## Fixtures

| ID | Name | Signal | Layouts |
|---|---|---|---|
| `sine-1k` | Test tone 1 kHz | sine 1,000 Hz both channels, amplitude 0.25 | 1, 2 |
| `sine-100` | Test tone 100 Hz | sine 100 Hz both channels, 0.25 | 1, 2 |
| `sine-1500` | Test tone 1.5 kHz | sine 1,500 Hz both channels, 0.25 (bin-centered at 48 kHz for every FFT size 512–8192) | 1, 2 |
| `sine-split` | Test tone L 1 kHz, R 440 Hz | sine left 1,000 Hz, right 440 Hz, 0.25 | 2 |
| `sweep-log` | Test sweep 20 Hz–20 kHz, logarithmic | logarithmic sweep 20 → 20,000 Hz over 10 s, 0.25, repeats | 1, 2 |
| `sweep-linear` | Test sweep 20 Hz–20 kHz, linear | linear sweep 20 → 20,000 Hz over 10 s, 0.25, repeats | 1, 2 |
| `pulse-120` | Test pulses 120 BPM | 2 ms rectangular pulses, 120 BPM, amplitude 0.5 | 1, 2 |
| `pulse-120-accent` | Test pulses 120 BPM, accented | as `pulse-120`, accents 1, 0.5, 0.5, 0.5 (beat 1 of 4 at 0.5, others 0.25) | 1, 2 |
| `pulse-132` | Test pulses 132 BPM | 2 ms pulses, 132 BPM (beat period not a whole number of samples), 0.5 | 1, 2 |
| `silence` | Test silence | digital silence (every sample +0.0) | 1, 2 |

Pulse width in frames is `round(0.002 × rate)`: 88 at 44.1 kHz, 96 at 48 kHz. A pulse is
`amplitude × accent` for its width, then 0 until the next onset.

## Expected analysis values

### Sine: FFT bin of the tone (exact bin `f·N/R` → nearest bin; ✓ = centered on a bin)

With a Hann window the largest magnitude of a single tone is at the nearest bin. Verified by the
reference DFT in `ReferenceToneOracleTests` for N = 512, 1024, 2048, 4096 and 8192.

| Fixture | Hz | Rate | 512 | 1024 | 2048 | 4096 | 8192 |
|---|---|---|---|---|---|---|---|
| `sine-100` | 100 | 44100 | 1.1610 → 1 | 2.3220 → 2 | 4.6440 → 5 | 9.2880 → 9 | 18.5760 → 19 |
| `sine-100` | 100 | 48000 | 1.0667 → 1 | 2.1333 → 2 | 4.2667 → 4 | 8.5333 → 9 | 17.0667 → 17 |
| `sine-1k` | 1000 | 44100 | 11.6100 → 12 | 23.2200 → 23 | 46.4399 → 46 | 92.8798 → 93 | 185.7596 → 186 |
| `sine-1k` | 1000 | 48000 | 10.6667 → 11 | 21.3333 → 21 | 42.6667 → 43 | 85.3333 → 85 | 170.6667 → 171 |
| `sine-1500` | 1500 | 44100 | 17.4150 → 17 | 34.8299 → 35 | 69.6599 → 70 | 139.3197 → 139 | 278.6395 → 279 |
| `sine-1500` | 1500 | 48000 | 16 ✓ | 32 ✓ | 64 ✓ | 128 ✓ | 256 ✓ |
| `sine-split` L | 1000 | 44100 | as `sine-1k` | | | | |
| `sine-split` L | 1000 | 48000 | as `sine-1k` | | | | |
| `sine-split` R | 440 | 44100 | 5.1084 → 5 | 10.2168 → 10 | 20.4336 → 20 | 40.8671 → 41 | 81.7342 → 82 |
| `sine-split` R | 440 | 48000 | 4.6933 → 5 | 9.3867 → 9 | 18.7733 → 19 | 37.5467 → 38 | 75.0933 → 75 |

For a bin-centered tone of amplitude A with a Hann window over N samples, the one-sided magnitude
`|X[k]|` at the tone's bin is `A·N/4` (0.25·N/4 = N/16 for the catalog's sines).

### Pulses: onset frames of one loop (onset k at `round(k·60·R/BPM)`, ties away from zero)

| Fixture | Rate | Beats per loop | Period (frames) | Onset frames |
|---|---|---|---|---|
| `pulse-120`, `pulse-120-accent` | 44100 | 20 | 22050 | 0, 22050, 44100, …, 418950 (k·22050) |
| `pulse-120`, `pulse-120-accent` | 48000 | 20 | 24000 | 0, 24000, 48000, …, 456000 (k·24000) |
| `pulse-132` | 44100 | 22 | 20045.4545… | 0, 20045, 40091, 60136, 80182, 100227, 120273, 140318, 160364, 180409, 200455, 220500, 240545, 260591, 280636, 300682, 320727, 340773, 360818, 380864, 400909, 420955 |
| `pulse-132` | 48000 | 22 | 21818.1818… | 0, 21818, 43636, 65455, 87273, 109091, 130909, 152727, 174545, 196364, 218182, 240000, 261818, 283636, 305455, 327273, 349091, 370909, 392727, 414545, 436364, 458182 |

Tempo: 120 BPM (0.5 s between onsets) and 132 BPM (0.4545… s). Accents of `pulse-120-accent`:
onset k has amplitude 0.5 when `k mod 4 = 0`, else 0.25. Every loop starts with an onset at frame
0, and the loop length is a whole number of beats, so the pattern continues across the loop wrap
without a gap or a shift.

### Sweeps: instantaneous frequency (Hz) at time t within a loop

Logarithmic: `f(t) = 20 · 1000^(t/10)`. Linear: `f(t) = 20 + 1998·t`. Phase is 0 at t = 0.

| t (s) | `sweep-log` | `sweep-linear` |
|---|---|---|
| 0 | 20 | 20 |
| 1.25 | 47.427 | 2,517.5 |
| 2.5 | 112.468 | 5,015 |
| 5 | 632.456 | 10,010 |
| 7.5 | 3,556.559 | 15,005 |

`ReferenceToneOracleTests` measures the local frequency from zero crossings around each t > 0 and
requires it within 1% (AUD-016-S4).

### Silence

Every sample is +0.0; the level meter reports −120 dBFS (its floor) and the classifier reaches
"Audio received — silent".

## Golden SHA-256 (version 1)

Filled in by AUD-016-T09 from the generator's output; the test asserts each value.

| Fixture | 44.1 kHz mono | 44.1 kHz stereo | 48 kHz mono | 48 kHz stereo |
|---|---|---|---|---|
| (pending AUD-016-T09) | | | | |

## Playback tolerance (AUD-016-R20)

- Output at 48 kHz: every delivered frame equals the 48 kHz stereo variant exactly.
- Output at another rate: recorded by AUD-016-T16 from measurement (pending).
