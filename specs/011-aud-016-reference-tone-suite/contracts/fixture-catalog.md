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

### Today's level meter and classifier (AUD-016-R21; `ToneAnalyzerDeterminismTests`)

The 48 kHz stereo loop in 1,024-frame blocks on a clock of frames / 48,000 (469 blocks), twice:
levels and states are identical on both runs. Final states: every sine and sweep `active`
("Active audio"); every pulse train and silence `silent` ("Audio received — silent"). A pulse train
is mostly silence: its 2 ms pulses never hold −50 dBFS for 250 ms, which feature 001's FR-011 needs
for "Active audio", so the status truthfully reads "Audio received — silent" although the clicks are
audible; the pulse rows' summaries say so. `sine-1k`: peak −12.04 dBFS, RMS −15.05 dBFS per block.

### Independent reproduction

`python3 scripts/check_reference_tone_goldens.py` ports the same formulas to CPython (same IEEE
operations) and reproduces the 18 mono golden hashes of every fixture except `sine-split` bit for
bit; `scripts/test_scripts.py` runs it.

## Golden SHA-256 (version 1)

Recorded by AUD-016-T09 from the generator's output on the Mac host (2026-11-12); `ReferenceToneCatalogTests.testGoldenHashesOnRepeatedRuns44100` and `…48000` assert each value on every host (split by rate 2026-11-13, owner rule 7). — = layout not published.

| Fixture | 44.1 kHz mono | 44.1 kHz stereo | 48 kHz mono | 48 kHz stereo |
|---|---|---|---|---|
| `sine-1k` | `ec6f232d35067a7623c03115c22d994723405477b3d4c152e891dd4aa7b3bdf2` | `a12d3d8c78a50595b99818f931879a0cc969e9cb9142a3aba4cbeec41453502e` | `e3ae450e8d1e94bb6efcfc4af0d89cc00e9a4cb3fc76d9a42b3ec55ce83ea8fd` | `b130d3f298b73f17b2ca56598f2a37ca0012789f42b527ddc187156ef7f4cc57` |
| `sine-100` | `7a783f028fd6bd701bfb4f53ab21c38e4dbc62adadad58089e4e9042f2dde7e5` | `c14d421beba274e2717a34eeb2b1c7ceb4ca6ac2c3e5eff280c9e690512907ef` | `8713580aa23eafdf1fe3fbfdcb4d6e3350107290919cbbd3873ac209ef6e4987` | `5244ab55cf6321c5750f5c3bb602a1477bc21f79d980447638d4be72961b0517` |
| `sine-1500` | `03647fcd2c1c361a401f5e415fbb0956621753ada10582b5cec243f2ccf1af2f` | `f453584fb20ccf8720ad99e8658876828ee5f9cb6e77439bb861b54032913427` | `7e21fbe4ee2418bfac37125e3d61d38069ba8a03ec6c9c510947628dfa067e13` | `7434d3ca5f235855e9d158f130a74b4a920e560ba36483b6b9e7d1e62336a6b9` |
| `sine-split` | — | `7003ea65fa73cd1d46ba331020eeebe69f3d8444b00dc1b96f49b7b957f8fe90` | — | `41aa73526e6a53076d7a2840fa7154c75b4a04fd71a22ddee840d59bd6c47f2a` |
| `sweep-log` | `42e8113fed498703fb14bed525da016b6a67729cf0848d5a1363e3be0a56be45` | `40f7e528dc3b0e0a65b956e249c1fbf9ec91f3a410a5a4d839532d1ff1ed43dc` | `e0399c2b5fda8611f63c2a94cca390456a0b76fabc022ca0054545bc45770dcd` | `75f981861d9980861f927800d357d92a5007e54ff006e7737e0013c2baa09685` |
| `sweep-linear` | `032af5ce5fa086383cba7a1ee273690d22fb5a79a79ae3e84cfa0a79f9260c2a` | `aa047413f72bccfa4755f0f276a8f517f0705a87862bb9b8f8614f43edcd75c3` | `338762b662c3a7c862ce8fd2fdbf15a623f7e461f549a7864ccbe6b355065daa` | `5c3b89e84ef376dfdcb35510d4c03101a9434aaca5e41e6f7407cc3f7c05c144` |
| `pulse-120` | `693a5c53843e7035485c7563ef46663166f309500eea95fb6194e3b79fa5882c` | `dc1c28718756e5ca40d197063cb93627b1fb3571f5fd89035f2225af8bc63d80` | `246506d85d7ff031affadeae816b12567eab39448d549b60a30dc49c0591eb4e` | `83e409263246d3b3a7d282b796224e9e96f733f13070e856ca969b384db99329` |
| `pulse-120-accent` | `37e275e3bb90bd9e358fa323f5f74308dea7fb3c0d38300245488bfc583c6f2c` | `7f0cc535ecdc42658d0aaea6651f35bbf667642e37f631c80a050f5c687d6716` | `bc8147321bb2ba4975b18a4989b4376d82824cb4829bb801d78316d894b69c9c` | `9b3e351e473688e31f99bf0d554b5f4f2fcc61c102f277c0e53d07af47909666` |
| `pulse-132` | `142dac944b046fd70dea397c87462b3179fcea106aebd2a9c5788dd0db9aae28` | `f4e1435570a782804d6c89f59ce7ef46523b01397db788fc4c28a6015e80d635` | `774ddfbd8f57e8c0e275ff8842998b77e07fa0c7abd91aa305ff177e54d4b01f` | `6c3e269ac1e0aac92c89204af643d38d611bb5ee095b595f3324b7c53660179d` |
| `silence` | `2b1f63df409bdeac3c7d15e9a3d30a8ed77d35d1a8397848bb14cadac59affdf` | `2a30c57a4d9493dee87b67431a6df0c02af11468bf0ef3e0f952dff48c24df53` | `124617c1f65e92d3bc895fbd869e4bb16a30754b198f59e6e973949b9aaa1b01` | `81beb57ba94e8afbf61c796a8a2438ff11c5e05c6fc156e7425b391c81369516` |

## Playback tolerance (AUD-016-R20)

- Output at 48 kHz: every delivered frame equals the 48 kHz stereo variant exactly.
- Output at another rate (measured by AUD-016-T16 at 44.1 kHz, offline engine on the Mac host,
  2026-11-12): `sine-1k` frequency by zero crossings within 1 Hz (0.1%) of 1,000 Hz and RMS within
  0.1 dB of −15.05 dBFS; every `pulse-120` interval within ±1 frame of 22,050; two runs bit-identical.
  Onsets shift by the converter's constant delay, so analyses compare intervals, not absolute frames,
  after a conversion.
