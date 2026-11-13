# Feature Specification: ANL-002 Log-frequency Bands

**Feature Branch**: `feature/anl-002` (spec directory `016-anl-002-log-frequency-bands`)

**Created**: 2026-11-13

**Status**: Draft

**Input**: User description: "Implement ANL-002 (Log-frequency bands) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Provide 16, 32, 64 and 128
perceptual bands." Acceptance, verbatim: "Known multi-tone fixture populates expected bands and zero
input stays zero." Dependencies: ANL-001 (integrated). Honor the repository constitution, VIII and
ADR-0008 decision 5."

Identifiers in this feature carry the roadmap ID so they never collide with other features:
requirements are `ANL-002-R1…`, success criteria `ANL-002-S1…`, tasks `ANL-002-T01…`. ANL-001's
requirements (`specs/014-anl-001-windowed-fft/spec.md`, in particular ANL-001-R4, R10 to R13) and
AUD-016's hand-off (AUD-016-R22: identical outputs on repeated runs) stay in force; this feature
cites them and adds to them.

## Baseline: what exists today (audit of 2026-11-13, commit `1911b6d`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap.

| Area | Today | Gap for this row |
|---|---|---|
| Spectrum | `Packages/AnalysisFeatures` (ANL-001) produces linear-amplitude magnitude spectra of 257 to 4,097 bins (FFT sizes 512 to 8,192) at any sample rate, with a vDSP path and a portable path. | Bins are linearly spaced: at 2,048 points, 1,024 bins cover 20 Hz to 20 kHz, half of them above 11 kHz. Nothing groups them the way people hear pitch. |
| Bands | No band, octave or mel grouping exists anywhere in `Packages/`. projectM computes its own bass/mid/treble internally and exposes none of it (ANL-001 research D1). | ANL-003 (smoothing), ANL-007 (kick), ANL-009 (high transients), MOD-015 (envelope followers) and VIS-001/VIS-002 (spectrum visuals) all depend on a fixed set of perceptual bands. |
| Fixtures | AUD-016 has single sines (100, 440, 1,000, 1,500 Hz), a stereo split, sweeps, pulses and silence at 44.1 and 48 kHz, generated deterministically. | No multi-tone fixture; nothing checks a band mapping. |

## User Scenarios & Testing *(mandatory)*

The "users" of this row are the later analysis, modulation and visual features and the developers
and CI that check them. Nothing in the app changes visibly.

### User Story 1 - Several known tones light the expected bands (Priority: P1)

A developer building a spectrum display feeds a known mixture of steady tones into the analysis and
reduces each spectrum to 16, 32, 64 or 128 bands. Each tone shows up in the band that the published
band edges predict, bands far from every tone stay near zero, and every value is a finite number.

**Why this priority**: It is the roadmap row's acceptance ("Known multi-tone fixture populates
expected bands").

**Independent Test**: Build a multi-tone signal from the AUD-016 tone generator, analyse its first
window at every FFT size and both catalog rates, reduce it to each band count, and compare with the
band each tone is predicted to fall in, computed in the test from the documented edge formula.

**Acceptance Scenarios**:

1. **Given** the multi-tone fixture, any band count, any FFT size and either catalog rate, **When** the first window is reduced to bands, **Then** the band predicted for each tone reads at least 0.35 of that tone's amplitude.
2. **Given** the same, **When** a tone's main lobe (two bins either side of it) lies wholly inside one band that no other tone reaches, **Then** that band reads the tone's amplitude within 2 % and is the largest band near the tone.
3. **Given** the same, **When** a band lies more than four bins away from every tone, **Then** it reads at most 2 % of the quietest tone's amplitude.

---

### User Story 2 - Zero stays zero (Priority: P1)

Silence must look like silence: a visual driven by the bands never flickers on digital silence.

**Why this priority**: The second half of the roadmap acceptance ("zero input stays zero").

**Independent Test**: Reduce the spectra of the AUD-016 silence fixture (every frame of the loop)
and an all-zero spectrum, for every band count, size and rate, and check that every band value is
exactly zero.

**Acceptance Scenarios**:

1. **Given** an all-zero spectrum, **When** it is reduced, **Then** every band is exactly 0, and so is every normalized value.
2. **Given** the silence fixture through the spectrum stream, **When** every frame is reduced, **Then** every band of every frame is exactly 0.

---

### User Story 3 - Choose a band count and FFT size freely (Priority: P1)

A visual chooses 16 bars on a phone and 128 on an iPad; a kick detector reads only the lowest bands.
Every band count works with every FFT size and sample rate, no band is ever empty, and switching
between them costs nothing at frame time.

**Why this priority**: It is the row's observable behavior ("Provide 16, 32, 64 and 128 perceptual
bands").

**Independent Test**: For all 4 band counts × 5 sizes × 2 rates, inspect the band table: edges,
coverage of every band, the bin each band reads; reduce frames while switching count and size.

**Acceptance Scenarios**:

1. **Given** any band count and size, **When** the band table is inspected, **Then** it has exactly that many bands, edges rise by the same ratio from 20 Hz to 20 kHz (or the Nyquist frequency if lower), and every band reads at least part of one bin.
2. **Given** a reducer, **When** the band count or FFT size changes between frames, **Then** the next frame uses the new table with no allocation and no lost state.
3. **Given** an unusable sample rate (below 8 kHz, zero, negative or not finite), **When** a band table is requested, **Then** it is rejected with a clear error.

---

### User Story 4 - Same bands on every run and every CI path (Priority: P2)

CI runs on macOS, the iOS Simulator and Linux. Band values repeat bit for bit on each path, and the
accelerated and portable paths agree within a stated tolerance.

**Why this priority**: AUD-016's hand-off (AUD-016-R22) and the CI history of this repository.

**Independent Test**: Reduce whole loops twice and compare bit for bit; reduce the same spectra
with both paths and compare within tolerance.

**Acceptance Scenarios**:

1. **Given** the multi-tone fixture and the catalog sweeps, **When** analysed and reduced twice, **Then** every band of every frame is bit-identical.
2. **Given** the same spectrum, **When** reduced by the accelerated and the portable path, **Then** every band agrees within 1e-5 of the frame's largest band plus 1e-7 absolute.

### Edge Cases

- A band narrower than one FFT bin (low bands at small sizes, for example 128 bands at 512 points): the band is not empty; it reads the spectrum's level at that frequency (the bins it overlaps, weighted by overlap), so neighbouring narrow bands inside one bin read the same value.
- The DC bin: ignored (a DC offset is not audio); the first bin's coverage is extended down to 0 Hz so the lowest bands still read something at small sizes.
- Sample rates below 40 kHz: the top edge becomes the Nyquist frequency.
- Non-finite or negative magnitudes passed in: treated as 0; output is always finite and ≥ 0.
- Spectrum length different from the FFT size the table was made for: a programming error, caught by the API shape (the size selects the table).
- Very loud input: band values above the reference are clamped only by the normalized helpers; the linear values are not clamped.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-002-R1**: The system MUST reduce one ANL-001 magnitude spectrum (N/2 + 1 linear bins) to exactly 16, 32, 64 or 128 bands; no other count is offered.
- **ANL-002-R2**: Band edges MUST be logarithmically spaced (equal frequency ratio per band) from a lower edge of 20 Hz to an upper edge of min(20 kHz, sample rate / 2): edge i of B bands is `20 · (upper / 20)^(i/B)` Hz, i = 0…B. Band b covers [edge b, edge b + 1).
- **ANL-002-R3**: Each bin k ≥ 1 MUST be treated as covering a frequency interval of one bin width centred on its frequency, except that bin 1's interval starts at 0 Hz and the Nyquist bin's interval ends at the Nyquist frequency; the DC bin MUST NOT contribute. A bin contributes to a band in proportion to the fraction of its interval that lies inside the band.
- **ANL-002-R4**: A band's value MUST be the amplitude of the sine that carries the band's power: the overlap-weighted sum of bin powers (magnitude squared), divided by the Hann window's equivalent noise bandwidth (1.5 bins), square-rooted. A steady sine of amplitude A whose spectrum lies inside one band reads A.
- **ANL-002-R5**: A band whose total coverage is less than one bin MUST be scaled up to one bin (its value is the overlap-weighted mean of the bins it touches), so no band is empty or reads low only because it is narrow.
- **ANL-002-R6**: Every band MUST cover part of at least one bin for every band count, FFT size and sample rate ≥ 8 kHz; band tables for sample rates below 8 kHz or not finite MUST be rejected with an error.
- **ANL-002-R7**: An all-zero spectrum MUST give exactly 0 in every band; non-finite or negative input magnitudes MUST be treated as 0; every output value MUST be finite and ≥ 0.
- **ANL-002-R8**: Normalized helpers MUST map band values to 0…1: linear (value / reference, reference default 1.0 = a full-scale sine, clamped) and decibel (`(dBFS − floor) / −floor`, floor default −80 dB, clamped); 0 maps to 0 in both.
- **ANL-002-R9**: Band tables MUST be precomputed per (band count, FFT size, sample rate) when the reducer is created, for all four counts and all five sizes at its sample rate; reducing a frame and switching count or size MUST NOT allocate, lock, log or do I/O (Constitution VII).
- **ANL-002-R10**: The band table MUST be inspectable: edges, centre frequency (geometric), width in bins, the bins and weights a band reads, the band containing a frequency, and the band that owns a bin (the band with the largest share of it, lower band on a tie).
- **ANL-002-R11**: Reducing the same spectrum with the same table and path MUST give bit-identical output on repeated runs (AUD-016-R22).
- **ANL-002-R12**: The reduction MUST work without the platform's accelerated math library (Linux CI) through a portable path with the same interface; the two paths MUST agree within 1e-5 of the frame's largest band plus 1e-7 absolute, and tests MUST be able to force the portable path.
- **ANL-002-R13**: Nothing computed here MAY be passed to projectM (Constitution VIII, ADR-0008 decision 5); no UI is added by this row.
- **ANL-002-R14**: The acceptance tests MUST use a multi-tone fixture built in the test target from the AUD-016 tone generator (no catalog change), check every band count × FFT size × catalog rate on every available path, and print the acceptance matrix (tone, band count, size, rate: expected band, measured band, value).

### Key Entities

- **Band count**: 16, 32, 64 or 128.
- **Band layout (table)**: band count, FFT size, sample rate, edges, per-band bin range, weights and scale.
- **Band reducer**: the 20 tables of one sample rate, a power scratch buffer, the chosen path; turns a magnitude spectrum into band values.
- **Band value**: linear sine-equivalent amplitude, finite, ≥ 0; normalized forms in 0…1.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-002-S1**: For 100 % of the acceptance combinations (each tone of the multi-tone fixture × 4 band counts × 5 sizes × 2 rates), the predicted band reads at least 0.35 of the tone's amplitude; for every combination whose main lobe lies inside one band reached by no other tone, that band reads the amplitude within 2 % and is the largest band near the tone.
- **ANL-002-S2**: 0 bands far from every tone (more than four bins away) read above 2 % of the tone amplitude, in every combination.
- **ANL-002-S3**: Silence reads exactly 0 in 100 % of bands of 100 % of frames, for every band count, size and rate.
- **ANL-002-S4**: 0 empty bands in all 40 tables (4 counts × 5 sizes × 2 rates), and 0 non-finite outputs, including for non-finite input.
- **ANL-002-S5**: Repeated runs are bit-identical (0 differing values); the two paths agree within the stated tolerance on every compared frame.
- **ANL-002-S6**: 0 heap allocations while reducing frames after setup, checked by reading the per-frame code and by the host benchmark under an allocation trace; the per-frame cost is reported for the host and is far below the spectrum's own cost (reported, never asserted).
- **ANL-002-S7**: Existing behavior unchanged: every existing AnalysisFeatures and AudioCore test passes unchanged.

## Hand-off to ANL-003, ANL-007, ANL-009, MOD-015, VIS-001 and VIS-002

- ANL-003 (smoothing) smooths the linear band values (or their normalized forms) per band; the band count fixes its state size.
- ANL-007 (kick) and ANL-009 (high transients) choose bands by frequency through `band(containingFrequency:)` and the edges, so their choice does not depend on the band count.
- MOD-015 (envelope followers) reads normalized band values in 0…1.
- VIS-001/VIS-002 draw one bar per band from the normalized values; the decibel mapping is the default for display.
- Every later row keeps ANL-002-R13: nothing goes into projectM.

## Assumptions

- Input spectra come from ANL-001 (`SpectrumAnalyzer`/`SpectrumStream`) with its normalization and periodic Hann window; the ENBW of 1.5 bins in ANL-002-R4 is that window's.
- The normalized stream is 44.1 kHz; fixtures are also checked at 48 kHz. One reducer serves one sample rate.
- The reducer is confined to one worker, like the analyser (ANL-001-R14).
- No new third-party dependencies, no stored data, no network use, no entitlement: the privacy policy and manifest do not change.
- Device measurements are not needed for this row's acceptance.
