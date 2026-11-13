# Research: AUD-016 Reference tone suite

Decisions are numbered `AUD-016-D1…` (the three-digit `R-nn` space belongs to features 001/002).

## AUD-016-D1 — Bit-identical samples without the platform math library

- **Decision**: The generator computes every sample from the frame index with correctly rounded IEEE
  754 double arithmetic only (`+ − × ÷`, `truncatingRemainder` (exact by definition), rounding to an
  integer, exact scaling by a power of two through `Double(sign:exponent:significand:)`) plus its own
  fixed approximations in `ToneMath`:
  - `sin2π(cycles)`: quadrant reduction by an exact multiply by 4 and an exact subtraction of the
    integer part, then a degree-17 Taylor polynomial for sine or degree-16 for cosine on
    `|x| ≤ π/4` (truncation error below 1e-18).
  - `exp(x)`: Cody–Waite reduction `x = k·ln2 + r` with a split `ln2` (`k·ln2Hi` is exact), a
    degree-13 Taylor polynomial on `|r| ≤ 0.35`, then exact scaling by `2^k`.
  - `log(x)` (once per sweep): exact split into exponent and significand, `s = (m−1)/(m+1)` with
    `m ∈ [√½, √2)`, and the odd series `2(s + s³/3 + … + s²⁷/27)`.
  The final `Double → Float` conversion rounds to nearest even, which IEEE defines exactly.
- **Rationale**: `sin`, `exp`, `log` and `pow` come from each platform's libm (Apple's libm on
  macOS and iOS, glibc on Linux), which are not required to be correctly rounded and can differ in
  the last bit between platforms and releases. Basic operations are correctly rounded everywhere.
  Swift does not contract `a*b+c` into a fused multiply-add unless asked (no fast-math), so the same
  source yields the same operations on arm64 and x86_64.
- **Verification**: golden SHA-256 hashes per fixture and variant, checked by the same test on the
  macOS host (`swift test`), with `-Xswiftc -DAUDIOCORE_NO_AVFAUDIO`, and on the iOS 27.2 Simulator
  (`xcodebuild test`). Accuracy against Foundation's functions is checked separately (≤ 2e-15
  absolute for sine on [0, 1) cycles, ≤ 4 ulp relative for exp and log on their tested ranges); the
  accuracy check is a tolerance test, never an equality test.
- **Alternatives considered**: Foundation `sin` (rejected: not guaranteed identical across hosts);
  a quantized lookup table (rejected: needs interpolation for arbitrary frequencies and still a table
  built with some sine); integer-only fixed-point oscillators (rejected: harder to give exact
  frequency and amplitude, no gain in determinism over correctly rounded doubles).

## AUD-016-D2 — Phase from the frame index, never accumulated

- **Decision**: Sine phase in cycles is `frac((n·f) / R)` computed as
  `(Double(n) * f).truncatingRemainder(dividingBy: R) / R`; sweeps compute phase in closed form from
  `m = n mod D` (D = sweep frames); pulses compute the onset of beat `k` as
  `round(k·60·R / BPM)` (ties away from zero). No phase accumulator.
- **Rationale**: Any range of frames can be generated alone and equals the same range in a longer
  run (AUD-016-R2); seeks and loop wraps need no state; integer frequencies at integer rates are
  exactly periodic in one second, so a 10 s loop of a sine is seamless bit for bit. `n·f` is exact
  for `n < 2^33` and frequencies with up to 20 significant bits, which covers every catalog fixture.

## AUD-016-D3 — A 10 second loop as an in-memory buffer in the existing graph

- **Decision**: A test signal is one 10 s loop of its fixture at 48 kHz stereo (3.84 MB of 32-bit
  float), generated on the main actor when the track is loaded, into an `AVAudioPCMBuffer`.
  `InAppPlaybackGraph.Content` gets a second storage kind, a buffer, next to the two file handles.
  Scheduling a buffer from frame 0 schedules it whole; scheduling from another frame (seek, resume
  at a held frame) schedules a copy of the tail, made on the main actor. Everything else in the
  graph (positions, cuts, the tap gate, loop passes, AUD-014 recovery) is unchanged.
- **Rationale**: The graph already implements a positioned, looping, cut-safe player for files;
  reusing it gives the transport and the interruption policy for free (AUD-016-R15, R17). Nothing is
  generated on the render thread (Constitution VII). No file is written (AUD-016-R19).
- **Alternatives considered**: an `AVAudioSourceNode` that generates on the render thread
  (rejected: a second playback path with its own position and cut logic, generation on the real-time
  thread); writing a temporary WAV file (rejected: writes generated audio to disk, new stored data).

## AUD-016-D4 — Offline mixer pass-through is bit-exact at a matching rate

- **Finding (measured 2026-11-12 on the Mac Studio, macOS host, `.build/scratch/mix.swift`)**: In
  offline manual rendering at 48 kHz stereo, a player connected to the main mixer delivered every
  frame of a 48 kHz mono or stereo float buffer unchanged, at unity gain, both at the engine output
  and at the main mixer tap (0 of 48,000 frames differed; a mono buffer appears identically on both
  output channels).
- **Consequence**: AUD-016-R20 and S5 can require exact equality at a matching rate. At 44.1 kHz
  output the mixer resamples; the tolerance is set from measurement in AUD-016-T16 and recorded in
  the fixture catalog contract.

## AUD-016-D5 — Where the user finds the signals

- **Decision**: A "Diagnostics" section at the end of the source chooser with one navigation row,
  "Test Signals", that opens a list of the catalog's fixtures. A tap on a fixture starts it as In-App
  Playback, alone in its play order. The list is never shown on launch and nothing is remembered
  (Clarifications).
- **Rationale**: Every source starts from the chooser; keeping the signals one level down keeps the
  chooser unchanged at first sight (AUD-016-R13, US1 scenario 1) and costs two taps (S7).

## AUD-016-D6 — Status line wording

- **Decision**: While the current In-App item is a test signal, the indicator reads
  `In-App Playback · <signal name> · <state>`; otherwise it is unchanged. The state still comes from
  the classifier, so "Active audio" appears only after verified non-silent audio (Constitution IV).
- **Rationale**: The mode label stays the first word (FR-013); the name says what the audio is; every
  name begins with "Test" (AUD-016-R16).

## AUD-016-D7 — Expected values live with the catalog; reference analysis lives in tests

- **Decision**: Expected values (nearest and exact bins, onset frames, tempo, inter-onset interval,
  accents, instantaneous sweep frequency) are pure functions of a fixture's parameters in AudioCore,
  so later rows can call them. The reference DFT (direct sum with a cosine/sine table, Hann window)
  and the onset scan (first non-zero sample after a zero) are written in the AudioCore test target
  only (AUD-016-R12).
- **Rationale**: Later ANL tests need the expected values in code; the oracle must stay independent
  of the generator and must not ship.

## AUD-016-D8 — Hashing in tests without CryptoKit

- **Decision**: A small SHA-256 (FIPS 180-4) in the AudioCore test target, checked against the
  standard test vectors ("", "abc", the 448-bit message). It hashes the little-endian bytes of the
  interleaved Float32 samples of one loop.
- **Rationale**: AudioCore must build and test on Linux, where CryptoKit does not exist; adding
  swift-crypto would be a new dependency.

## AUD-016-D9 — The bundled reference track is not reproduced

- **Finding**: `scripts/generate_reference_audio.py` computes its samples with Python's `math.sin`
  and `math.exp` (the platform libm) and rounds to 16 bits. The Swift generator could match most
  16-bit samples but not guarantee all of them, and nothing depends on it. The script and the
  bundled track stay unchanged; no reproduction test is added.

## AUD-016-D10 — Rollback

- The feature adds code, docs and tests only: no stored data, no migration, no entitlement, no
  setting. Rolling back is reverting the feature's commits; an installed build that is downgraded
  finds nothing to clean up.
