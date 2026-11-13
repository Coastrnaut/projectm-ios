# Feature Specification: ANL-001 Windowed FFT

**Feature Branch**: `feature/anl-001` (spec directory `014-anl-001-windowed-fft`)

**Created**: 2026-11-12

**Status**: Draft

**Input**: User description: "Implement ANL-001 (Windowed FFT) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Compute magnitude spectra with
selectable FFT size and Hann window." Acceptance, verbatim: "Single-tone fixture peaks within one
frequency bin and has finite values." Dependencies: AUD-016 (integrated; its hand-off requires
identical FFT outputs on repeated runs against its fixtures). Honor the repository constitution,
especially VIII and ADR-0008 decision 5."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-001-R1…`, success criteria `ANL-001-S1…`, tasks `ANL-001-T01…`. AUD-016's
requirements (`specs/011-aud-016-reference-tone-suite/spec.md`, in particular AUD-016-R22 and its
Hand-off section) and feature 001's real-time rules stay in force; this feature cites them and adds
to them.

## Baseline: what exists today (audit of 2026-11-12, commit `83c7a35`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Analysis code | `AudioCore` measures peak and RMS levels (`LevelMeter`) and classifies the audio state. No spectrum, band, onset or beat analysis exists anywhere in `Packages/`. | No magnitude spectrum for the later analysis rows (ANL-002 bands, ANL-004 onsets, ANL-010 to 012 spectral shape) or the native generators. |
| Normalized audio | The Normalizer writes Float32 interleaved stereo at 44.1 kHz into one ring (`NormalizedPCMRing`) whose only consumer is the projectM renderer; a read removes the audio. | A second consumer reading that ring would take audio away from projectM. |
| Engine | projectM receives normalized PCM through its documented `projectm_pcm_add_float` and does its own internal analysis. Its public API exposes no spectrum or beat output (research ANL-001-D1). | Other consumers (native generators, the modulation graph) have no spectrum to read. This is the measured need that Constitution VIII asks for (ADR-0008 decision 5). |
| Fixtures | AUD-016 delivers deterministic sine, sweep, pulse and silence fixtures at 44.1 and 48 kHz, the catalog's documented FFT bin per sine and size, and a test-only reference DFT. | Nothing checks a production FFT against them yet (AUD-016 Hand-off: "ANL-001 MUST run its FFT over every sine and sweep fixture twice and assert identical outputs"). |

## Clarifications

### Session 2026-11-12

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the conservative, local-first option using public APIs only,
recommended option first.

- Q: Which FFT sizes are selectable? → A: The five powers of two 512, 1,024, 2,048, 4,096 and 8,192, exactly the sizes AUD-016's catalog documents bins for. Any other size is rejected at configuration time, never silently rounded (ANL-001-R2).
- Q: What does one magnitude value mean? → A: Linear amplitude, scaled so that a sine of amplitude A centred on a bin reads A at that bin (a full-scale sine reads 1.0, the catalog's 0.25 sines read 0.25). The DC and Nyquist bins use the same scale for a constant or a Nyquist-rate signal. A decibel conversion relative to full scale with a −120 dB floor (the level meter's floor) is offered as a helper; spectra are linear by default. Power spectra and other scalings are left to the consuming rows (ANL-001-R4).
- Q: Which window, and periodic or symmetric? → A: The periodic Hann window `w[n] = 0.5 − 0.5·cos(2πn/N)`, the same window the AUD-016 reference DFT uses, so the catalog's bins and the `A·N/4` peak apply unchanged (ANL-001-R3).
- Q: How far apart are consecutive analysis frames (hop), and is overlap configurable? → A: Configurable hop from 1 sample to the FFT size; the default is half the FFT size (50 % overlap), which a periodic Hann window sums to a constant at. A frame is produced only when a whole window of new-enough audio exists; nothing is zero-padded at the start (ANL-001-R6).
- Q: Which channel is analysed? → A: Mid, `(L + R)/2`, by default. Left only and right only are also offered so a stereo fixture with different tones per channel can be checked; letting the user choose a channel is AUD-009's job and is not part of this row (ANL-001-R5).
- Q: Where does the analysis get its audio without taking it from projectM? → A: From a separate, optional copy of the normalized stream (an analysis tap) that the normalized ring fills in the same write when enabled. It has its own bounded capacity and drop-oldest policy, so a slow or absent analysis consumer never affects projectM's reads. It is off unless the code that creates the ring asks for it; this row does not turn it on in the app (ANL-016 wires the worker) (ANL-001-R9).
- Q: When is a frame "at" a time? → A: Every frame carries the index of its first sample counted from the start (or last reset) of the stream: a deterministic sample clock that repeats exactly between runs. It also carries the monotonic-clock reading taken when it was computed, for alignment with other timestamped data; tests inject that clock (ANL-001-R7).
- Q: What happens with invalid input (NaN, infinity, huge values, denormals)? → A: Every input sample is sanitized before windowing: NaN and ±infinity become 0, values below the smallest normal float become 0, and finite values are clamped to ±64 (+36 dBFS). Output values are therefore always finite and never negative (ANL-001-R8).
- Q: Does the analysis go into projectM or onto the screen in this row? → A: No. Nothing it computes is passed to projectM (ADR-0008 decision 5) and no UI or diagnostics readout is added; consumers arrive with ANL-002 and the VIS rows (ANL-001-R12).
- Q: Must the platform-accelerated path and the portable path give the same numbers? → A: Each path is bit-identical with itself on repeated runs. Across paths, every bin agrees within 1e-5 of the frame's largest magnitude (plus 1e-6 absolute), and the peak bin is the same (ANL-001-R10, R11).
- Q: When the FFT size or hop changes while audio is buffered, where does the next frame start? → A: At the stream's next frame position, using the audio already buffered: the change takes effect from the next frame, no buffered audio is thrown away, and frame indices keep counting (the next frame starts at the previous frame's start plus the old hop). If fewer samples than the new size are buffered, the frame waits for more (ANL-001-R6, R17).
- Q: Do frame indices count audio the analysis tap dropped while nobody read it? → A: No. The index counts the samples the analyser actually received since its last reset; tap overflow is reported separately by the tap's dropped-frame counter, and the consumer resets the analyser after an overflow or a discard if it needs indices aligned with the source (ANL-001-R7, R9).
- Q: What do the tests require of the sweep fixtures beyond identical repeated runs? → A: Finite values in every frame, and at the default size 2,048 the peak of a frame centred at each of the catalog's sweep check times (1.25, 2.5, 5 and 7.5 s) lies within two bins of the catalog's instantaneous frequency at that time (the sweep moves during a window, so one bin is too strict) (ANL-001-R16).

## User Scenarios & Testing *(mandatory)*

The "users" of this row are the later analysis and visual features and the developers and CI that
check them. Nothing in the app changes visibly.

### User Story 1 - A known tone shows up in the right place (Priority: P1)

A developer building a band display or an onset detector feeds a steady test tone into the spectrum
analysis, at any supported FFT size and at either catalog sample rate, and finds the tone's energy
at the documented frequency bin, with every value a finite number.

**Why this priority**: It is the roadmap row's acceptance. Every later spectral feature depends on
the peak being where the catalog says.

**Independent Test**: For every sine fixture in the AUD-016 catalog, every FFT size and both rates,
compute a spectrum of the fixture's first window and compare the largest bin with the catalog's
documented bin.

**Acceptance Scenarios**:

1. **Given** a catalog sine fixture, a supported FFT size and a catalog rate, **When** the first window from frame 0 is analysed, **Then** the largest magnitude is at the catalog's documented nearest bin, and all values are finite.
2. **Given** the same fixture, **When** every frame of a whole loop is analysed at the default hop, **Then** each frame's largest magnitude is within one bin of the catalog's documented (nearest) bin, and all values are finite.
3. **Given** a tone centred on a bin (`sine-1500` at 48 kHz), **When** it is analysed at any size, **Then** the peak reads its amplitude, 0.25, within 1e-4, and a full-scale bin-centred sine reads 1.0 within 1e-4.
4. **Given** the `sine-split` stereo fixture, **When** the left channel only and the right channel only are analysed, **Then** the peaks are at the 1 kHz and the 440 Hz documented bins respectively.

---

### User Story 2 - Identical spectra on every run (Priority: P1)

A developer or CI run analyses the same fixtures again and gets exactly the same numbers, so later
rows can compare their results with stored expectations and a change in output always means a
change in code.

**Why this priority**: It is AUD-016's hand-off requirement (AUD-016-R22) and the basis of every
golden test after this row.

**Independent Test**: Run the analysis twice over every sine and sweep fixture (whole loops, every
size, both rates), once with a fresh analyser and once with a reused one, and compare all values
bit for bit.

**Acceptance Scenarios**:

1. **Given** any sine or sweep fixture, **When** it is analysed twice, **Then** every frame's values and frame indices are bit-identical.
2. **Given** an analyser that has already processed other audio, **When** it is reset and fed the fixture again, **Then** its output equals a fresh analyser's output bit for bit.

---

### User Story 3 - Choose the resolution without glitches (Priority: P2)

A later feature (a fine bass display, a fast onset detector) picks the FFT size and hop it needs.
Changing them takes effect cleanly at the next frame, and the analysis never stalls or disturbs the
audio path while it runs.

**Why this priority**: Selectable size is part of the row's observable behavior; real-time safety
is a constitution rule (VII).

**Independent Test**: Switch sizes and hops between frames and check the bin count, bin
frequencies and frame indices; check that analysing a frame performs no memory allocation.

**Acceptance Scenarios**:

1. **Given** a running analysis at 2,048, **When** the size is changed to 512, **Then** the next frame has 257 bins of 86.13 Hz each at 44.1 kHz, starts where the next 2,048 frame would have started, and no buffered audio is discarded.
2. **Given** an unsupported size (for example 1,000 or 16,384), **When** it is requested, **Then** the request is rejected with a clear error and the analysis keeps its previous size.
3. **Given** a configured analyser, **When** frames are analysed, **Then** no memory is allocated, no lock is taken and nothing is written to disk during the analysis of a frame.

---

### User Story 4 - Same results everywhere CI runs (Priority: P2)

CI runs the package tests on macOS, the iOS Simulator and Linux (where the platform's accelerated
math library is not available). The analysis gives the same peaks everywhere and matches an
independent reference within a stated tolerance.

**Why this priority**: CI has broken on Linux before; the portable path keeps the package testable
there.

**Independent Test**: Force the portable path on macOS and compare it with the accelerated path on
the same fixtures; compare both with the test-only reference DFT for small sizes.

**Acceptance Scenarios**:

1. **Given** the same input, **When** analysed by the accelerated and the portable path, **Then** every bin agrees within the stated tolerance and the peak bins match.
2. **Given** a 512- or 1,024-point window of a fixture, **When** compared with the reference DFT (scaled to the same normalization), **Then** every bin agrees within 1e-5 of the peak.

### Edge Cases

- Digital silence: every magnitude is exactly 0 (and −120 dB in the decibel helper).
- NaN, ±infinity, huge or denormal samples: sanitized; output finite and non-negative.
- Less than one window of audio: no frame is produced; nothing is padded.
- Hop larger than the size or smaller than 1: rejected at configuration.
- The analysis consumer stops reading: the analysis tap drops its oldest audio and counts it; projectM's ring is unaffected.
- A source restart or a seek (discard): the tap is emptied with the main ring; the analyser's reset restarts frame indices at 0.
- Sample rate other than 44.1 kHz (fixtures at 48 kHz): the analyser takes the rate as configuration; bin frequencies follow it.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-001-R1**: The system MUST compute one-sided magnitude spectra (bins 0 through N/2, that is DC through Nyquist, N/2 + 1 values) of a window of mono audio.
- **ANL-001-R2**: The FFT size MUST be selectable among 512, 1,024, 2,048, 4,096 and 8,192 samples; other sizes MUST be rejected with an error, leaving the current configuration unchanged.
- **ANL-001-R3**: Each window MUST be weighted by the periodic Hann window `w[n] = 0.5 − 0.5·cos(2πn/N)` before the transform.
- **ANL-001-R4**: Magnitudes MUST be linear amplitude scaled so a sine of amplitude A centred on bin k (0 < k < N/2) reads A at bin k, and a constant of value A reads A at bin 0; the scale relative to the raw transform (`|X[k]|·4/N` for interior bins, `|X[k]|·2/N` for DC and Nyquist) MUST be documented. A decibel helper relative to full scale with a −120 dB floor MUST be provided.
- **ANL-001-R5**: Mono input MUST be formed from interleaved stereo as mid `(L + R)/2` by default; left-only and right-only MUST also be available. Mono input MUST be accepted directly.
- **ANL-001-R6**: The hop MUST be configurable from 1 to N samples, default N/2. A frame MUST be produced only when N samples of input are available for it; no zero padding at the start.
- **ANL-001-R7**: Each frame MUST carry the index of its first input sample since the stream started or was last reset (deterministic sample clock), the FFT size, the sample rate and a monotonic-clock timestamp taken when it was computed (the clock is injectable for tests).
- **ANL-001-R8**: Input samples MUST be sanitized (NaN/±infinity → 0, below the smallest normal float → 0, clamp to ±64) so every output value is finite and non-negative, for any input.
- **ANL-001-R9**: Audio for the analysis MUST come from an optional analysis tap on the normalized stream that has its own bounded capacity (0.5 s by default, any positive capacity the creator chooses) with drop-oldest overflow and counters, so that projectM's reads of the normalized ring are unchanged whether the tap is enabled, read or never read. With the tap disabled (the default), the ring MUST behave exactly as before.
- **ANL-001-R10**: Analysing the same input with the same configuration MUST give bit-identical output on repeated runs on the same platform path, including after a reset.
- **ANL-001-R11**: The system MUST work where the platform's accelerated math library is unavailable (Linux CI) through a portable implementation with the same interface. The two paths MUST agree within 1e-5 of the frame's largest magnitude plus 1e-6 absolute, with the same peak bin, and tests MUST be able to force the portable path on Apple platforms.
- **ANL-001-R12**: Nothing the analysis computes MAY be passed to projectM (Constitution VIII, ADR-0008 decision 5); projectM keeps receiving normalized PCM through its documented API. No UI is added by this row.
- **ANL-001-R13**: Analysing a frame MUST NOT allocate memory, take locks, perform I/O or log (Constitution VII). All buffers, windows and transform setups MUST be created when the analyser is created, for every supported size, so changing the size later allocates nothing.
- **ANL-001-R14**: The analysis MUST run off the real-time audio callback and off the main thread; the analyser is confined to the one worker that owns it (the worker itself is ANL-016's).
- **ANL-001-R15**: Bin helpers MUST give the centre frequency of a bin (`k·R/N`), the bin width (`R/N`), the nearest bin of a frequency and the bin count.
- **ANL-001-R16**: The acceptance tests MUST run over every sine and sweep fixture of the AUD-016 catalog at both catalog rates and every supported size: peaks at the catalog's documented bins for sines (first window), within one bin of the documented bin for every frame of a loop, finite values everywhere, bit-identical repeated runs (AUD-016-R22). For sweeps at size 2,048, the peak of the frame centred at each catalog check time is within two bins of the documented instantaneous frequency.
- **ANL-001-R17**: Changing the FFT size or hop of a running stream MUST take effect at the next frame without discarding buffered audio and without allocating; frame indices keep counting from the last frame.

### Key Entities

- **Spectrum configuration**: FFT size (one of five), hop (1…N), sample rate, channel mode (mid, left, right).
- **Spectrum frame**: first-sample index, FFT size, sample rate, monotonic timestamp, and N/2 + 1 linear magnitudes.
- **Analysis tap**: an optional bounded copy of the normalized stereo stream for analysis consumers, with dropped-frame counters.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-001-S1**: For 100 % of the catalog's sine checks (4 sine fixtures, both channels of `sine-split`, 2 rates, 5 sizes: 50 combinations) the first window peaks at the documented bin, and every frame of each whole loop peaks within one bin of the documented bin.
- **ANL-001-S2**: 0 non-finite values across all fixtures, all sizes and both rates, and across the invalid-input cases (NaN, ±infinity, ±3.4e38, denormals).
- **ANL-001-S3**: Repeated runs over every sine and sweep fixture are bit-identical (0 differing values) on each platform path.
- **ANL-001-S4**: A bin-centred tone reads its amplitude within 1e-4 (0.25 for the catalog tone, 1.0 at full scale); silence reads exactly 0 in every bin.
- **ANL-001-S5**: Accelerated and portable paths agree within 1e-5 of the frame's peak (+1e-6) on every compared frame; both agree with the reference DFT within 1e-5 of the peak for N = 512 and 1,024.
- **ANL-001-S6**: 0 heap allocations while analysing frames after setup, at every size: checked by reading the per-frame code and by an allocation trace of the host benchmark (in-process heap statistics cannot see allocations freed within a frame, research ANL-001-D9).
- **ANL-001-S7**: The per-frame analysis cost at each size is measured on the Mac host (and the simulator) and reported; at 8,192 it uses less than 1 % of one core at the default hop and 44.1 kHz on the host (accelerated path). Reported, not asserted in tests (tests never depend on timing).
- **ANL-001-S8**: Existing behavior unchanged: every existing AudioCore, CaptureKit, CaptureUI and Diagnostics test passes unchanged with the analysis tap code in place.

## Hand-off to ANL-002, ANL-004, ANL-010 to ANL-012, ANL-014 and ANL-016

- ANL-002 (bands), ANL-004 (spectral flux), ANL-010 to ANL-012 (centroid, rolloff, flatness) and ANL-014 (loudness) read the linear magnitudes of each frame together with the bin helpers; they square for power where they need it.
- ANL-016 (event bus) creates the worker, enables the analysis tap on the normalized ring the app uses, and timestamps frames by their first-sample index; it decides the publication policy.
- Every later row keeps ANL-001-R12: nothing goes into projectM.

## Assumptions

- The normalized stream stays Float32 interleaved stereo at 44.1 kHz (research R-05 of feature 001); fixtures at 48 kHz are analysed directly, not through the Normalizer.
- The analysis runs on one worker at a time; the analyser is not shared between threads.
- No new third-party dependencies; Apple's Accelerate framework is a system framework available on every supported Apple platform.
- No new stored data, no network use and no new entitlement, so the privacy policy and the privacy manifest do not change.
- Device measurements are not needed for this row's acceptance; the CPU cost on a device is checked in the roadmap's final device phase if a later row needs it.
