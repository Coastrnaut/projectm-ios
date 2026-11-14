# Feature Specification: ANL-011 Spectral Rolloff

**Feature Branch**: `feature/anl-011` (spec directory `182-anl-011-spectral-rolloff`)

**Created**: 2026-11-14

**Status**: Draft

**Input**: Roadmap row ANL-011 (docs/FEATURE_ROADMAP_AUTONOMOUS.md), verbatim: "Compute configurable
energy percentile frequency." Acceptance, verbatim: "Rolloff matches a deterministic reference
spectrum within tolerance." P2, size S, depends on ANL-001. Verification: "Accelerate/vDSP,
deterministic sample clocks; unit with synthetic PCM + simulator". The brief adds: the rolloff is
the lowest frequency below which a fraction p (0.85 by default, configurable 0.5…0.99) of the
spectrum's energy lies, interpolated within the bin; silence reads 0 with no NaN; no extra FFT; a
binding source with the next free SHD-009 opcode (19) and the inspector name "Rolloff".

Identifiers carry the roadmap ID: requirements `ANL-011-R1…`, success criteria `ANL-011-S1…`,
tasks `ANL-011-T01…`. Other features are cited by their own IDs: ANL-001 (windowed magnitude
spectra), ANL-010 (spectral centroid, the pattern followed here, and the shared bin-range rule),
ANL-014 (loudness), ANL-016 (analysis event bus), MOD-002 (audio feature sources and bindings),
SHD-009 (expressions that read audio sources), UIX-003 (parameter inspector names).

## Baseline: what exists today (audit of 2026-11-14, commit `6b32708e`)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap: no
source in `Packages/` or `Apps/` computes a rolloff.

| Area | Today | Gap for this row |
|---|---|---|
| Spectra | ANL-001 periodic-Hann linear magnitudes (a bin-centred full-scale sine reads 1); the bus runs 2,048 points, hop 512, 44.1 kHz. | — |
| Shared range rule | ANL-010 `SpectralBinRange` (whole bins from ≥ 20 Hz, DC excluded, through Nyquist) was written for ANL-011 and ANL-012 to reuse. | Reused as is. |
| Spectral shape | ANL-010 `SpectralCentroidEstimator` (power-weighted, log-normalized 50 Hz–10 kHz, −70 dB floor). | No energy-percentile frequency. |
| Bus | `AnalysisFrame` carries bands, onset, beat, kick, centroid, loudness, mid and high transients. | No rolloff field. |
| Modulation | MOD-002 `AudioFeatureSource` (…, `centroid`, `loudness`, `midTransient`, `highTransient`, `lfo(i)`); SHD-009 opcodes 1-18 and 20-32 are taken, 19 is free (checked in every worktree). Inspector names in `ParameterInspectorModel.inspectorName` (centroid reads "Brightness"). | No rolloff source. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: decisions delegated, no
human interaction); each answer is the recommended, conservative option.

- Q: Is the percentile taken over power (m²) or magnitude (m)? → A: Power, P_k = m_k². Why: "energy percentile" names energy, which is power; it matches ANL-010's power-weighted centroid (the two read the same notion of where the energy is); and a noise floor or the window's sidelobes, which add up in magnitude, barely move a power percentile. Rejected: magnitude (librosa's default input; noise-floor sensitive) (ANL-011-R1).
- Q: How is the value interpolated within a bin? → A: Each analysed bin's power is treated as spread evenly over the bin's own width, [(k − ½)·Δf, (k + ½)·Δf] with Δf = R/N. The cumulative power is then piecewise linear, and the rolloff is the lowest frequency where it reaches p × total: with k the first bin whose inclusive cumulative sum S_k ≥ p·T, rolloff = (k − ½ + (p·T − S_{k−1}) / P_k)·Δf, clamped to [0, Nyquist]. Why: it is continuous in p and in the spectrum (no bin-sized steps for a bound visual), it is exact for a flat spectrum, and it keeps every analytic reference within half a bin: a single tone at bin k reads (k − ½ + p)·Δf (k itself at p = 0.5, k + 0.35 at 0.85, k + 0.49 at 0.99). Rejected: the bin-centre step (jumps a whole bin), and linear interpolation between bin centres (reads a lone tone at k − 1 + p, up to a bin low, and two tones up to ¾ bin off) (ANL-011-R2).
- Q: Which bins are analysed? → A: ANL-010's `SpectralBinRange`: whole bins from the first at or above 20 Hz (DC excluded) through the Nyquist bin, at the frame's own FFT size and rate. The cumulative sum starts at 0 at the first bin's lower edge (below it no power is counted, which is "from 0 Hz" with DC and sub-20 Hz excluded) (ANL-011-R1).
- Q: How is the percentile configured? → A: A configuration value, the fraction p, default 0.85, accepted in [0.5, 0.99]; anything else (or non-finite) is refused when the configuration is made. It is a code/configuration choice on the analysis pipeline, like every other ANL-0xx parameter: no Settings row and no UserDefaults key (P2, size S; no stored data). Why: 0.85 is the conventional rolloff point; below 0.5 the value stops describing the top of the spectrum and above 0.99 a single noise bin decides it (ANL-011-R3).
- Q: How is the value normalized for bindings? → A: Log frequency, like the centroid: n = clamp(log2(f / 50 Hz) / log2(20 kHz / 50 Hz), 0, 1), each octave the same 1/8.64 ≈ 0.116 step; fixed endpoints, so the same sound reads the same n at 44.1 and 48 kHz. The upper end is 20 kHz rather than the centroid's 10 kHz because a rolloff sits well above the centroid (white noise rolls off near 18.7 kHz at 44.1 kHz, which reads 0.99 and stays below the clamp). Rejected: linear rolloff / Nyquist (everything musical squeezed into the bottom third), and a rate-dependent Nyquist endpoint (ANL-011-R4).
- Q: What happens at silence? → A: When the analysed range's power relative to a full-scale sine (Σ m² / 1.5, ANL-010's rule) is at or below −70 dB, the reading is 0 Hz and 0 normalized and reports no signal (the brief's "output 0"); also before any signal and after each session start. Non-finite magnitudes count as 0; every published value is finite. This differs on purpose from the centroid, which holds its last value: the brief asks for 0, and MOD-002 bindings carry their own release envelope, so a bound parameter eases down rather than jumping (ANL-011-R5).
- Q: Smoothing, cost and backends? → A: No temporal smoothing (MOD-002 envelopes do that). No extra FFT: the estimator reads the magnitudes ANL-001 already computed for the frame. The total power uses vDSP (`vDSP_svesq`) when Accelerate is compiled in and the backend allows it, and a portable loop otherwise (`-DANALYSIS_NO_ACCELERATE`, Linux); the cumulative scan is portable in both. No buffers, no allocation, no lock, no clock (ANL-011-R6, R10, R11).
- Q: What is the source called? → A: MOD-002 source `audio.rolloff`, reading the normalized value; SHD-009 opcode 19 (permanent); inspector name "Rolloff". The analysis frame carries `rolloffHz` and the normalized `rolloff`; the app's native visual feeds the normalized value to its bindings like the centroid. No new UI (ANL-011-R7 to R9).
- Q (speckit-clarify pass): Should the rolloff also appear in a readout, the diagnostics export or a scene's stored data beyond a binding's source ID? → A: No. Readouts and exports belong to later rows; a binding stores only `audio.rolloff`, which older builds orphan like any unknown source (MOD-013), so no scene version bump and no new stored key (ANL-011-R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The rolloff matches a known spectrum (Priority: P1)

A visual author binding a parameter to "Rolloff" needs the number to mean what it says: the
frequency below which 85 % (or the chosen fraction) of the sound's energy lies.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed deterministic reference spectra with analytically known
rolloff straight to the estimator.

**Acceptance Scenarios**:

1. **Given** a single tone at bin k, **When** measured, **Then** the rolloff is within half a bin of bin k's frequency.
2. **Given** two tones with a known power ratio, **When** measured, **Then** the 85 % point falls on the lower tone when it holds at least 85 % of the power and on the higher tone otherwise, each within half a bin.
3. **Given** flat power up to a cutoff C, **When** measured, **Then** the rolloff is 0.85·C within half a bin.
4. **Given** power rising linearly with frequency up to C, **When** measured, **Then** the rolloff is C·√0.85 within half a bin.
5. **Given** p = 0.5 and p = 0.99, **When** the same spectra are measured, **Then** they match the references for those fractions.

### User Story 2 - Silence and bad input are calm (Priority: P1)

**Why this priority**: A NaN or a jump on a pause would make bound visuals flash.

**Acceptance Scenarios**:

1. **Given** digital silence or dither-level noise, **When** measured, **Then** both values are 0 and no signal is reported.
2. **Given** non-finite magnitudes, **When** measured, **Then** every value is finite.
3. **Given** a tone then silence, **When** measured, **Then** the silent frames read 0.

### User Story 3 - The same input reads the same on every build (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the same spectrum, **When** measured twice or with the vDSP and the portable backend, **Then** the results agree (bit-equal when repeated; within 0.001 bin across backends).

### User Story 4 - Rolloff is a modulation source (Priority: P2)

**Acceptance Scenarios**:

1. **Given** the real analysis pipeline fed a low tone then a bright noise, **When** frames are read, **Then** they carry both rolloff values and the noise reads higher.
2. **Given** the native visual with a Rolloff binding on the glow, **When** frames carry a rolloff, **Then** the glow follows it, and the inspector names the source "Rolloff".

### Edge Cases

- The crossing falls in the Nyquist bin: the result is clamped to Nyquist.
- The first analysed bin is above bin 1 (large FFT sizes): the cumulative starts at that bin's lower edge.
- Frames at another sample rate or with a wrong magnitude count: ignored (the reading is unchanged).
- A fraction outside 0.5…0.99 is refused when the configuration is made.
- A session restart: the reading restarts at 0.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-011-R1**: The system MUST compute, for each spectrum frame, the rolloff over ANL-010's analysed range (whole bins from ≥ 20 Hz, DC excluded, through Nyquist) using bin power m², at the frame's own FFT size and rate, with no temporal smoothing.
- **ANL-011-R2**: The rolloff MUST be the lowest frequency at which the cumulative power, with each bin's power spread evenly over its width, reaches p × the range's total, clamped to [0, Nyquist].
- **ANL-011-R3**: The fraction p MUST default to 0.85 and be configurable in [0.5, 0.99]; other values MUST be refused.
- **ANL-011-R4**: The rolloff MUST be reported in Hz and as n = clamp(log2(f / 50 Hz) / log2(20 kHz / 50 Hz), 0, 1).
- **ANL-011-R5**: At or below the −70 dB silence floor (ANL-010's rule), and before any signal, both values MUST be 0 with no signal reported; non-finite magnitudes count as 0; every value MUST be finite.
- **ANL-011-R6**: The rolloff MUST reuse the frame's existing spectrum (no extra transform); with Accelerate compiled in, the vDSP total MUST agree with the portable path within 0.001 bin.
- **ANL-011-R7**: The ANL-016 pipeline MUST compute the rolloff on every spectrum frame and carry `rolloffHz` and the normalized `rolloff` in every feature frame; session starts MUST reset it.
- **ANL-011-R8**: MOD-002 MUST offer the source `audio.rolloff` reading the normalized value (missing or non-finite reads 0), usable in bindings and SHD-009 expressions through permanent opcode 19; the inspector MUST name it "Rolloff".
- **ANL-011-R9**: The app's native visual MUST feed the normalized rolloff to its bindings.
- **ANL-011-R10**: Processing a frame MUST NOT allocate, lock, log, do I/O or read a clock (Constitution VII).
- **ANL-011-R11**: The feature MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-011-R12**: Nothing computed here reaches projectM (Constitution VIII); no new setting, stored key, network or UI.

### Key Entities

- **Rolloff configuration**: sample rate, analysed range, fraction p, silence floor, normalization range.
- **Rolloff reading**: value in Hz, normalized value, whether the frame was above the floor.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-011-S1**: The four reference spectra (single tone, two tones on each side of the 85 % split, flat to a cutoff, linear ramp) match their analytic rolloff within half a bin (the roadmap acceptance).
- **ANL-011-S2**: The same references at p = 0.5 and p = 0.99 match their analytic values within half a bin.
- **ANL-011-S3**: Silence, dither and non-finite input read 0 / finite with no signal.
- **ANL-011-S4**: Repeated runs are bit-equal; vDSP and portable agree within 0.001 bin.
- **ANL-011-S5**: Through the real pipeline, a bright noise's frames read a higher rolloff than a low tone's.
- **ANL-011-S6**: `audio.rolloff` round-trips, binds, compiles to opcode 19 and drives the glow in the app; the inspector reads "Rolloff".
- **ANL-011-S7**: The new package tests add well under a second to the AnalysisFeatures suite; every existing test passes.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; the rolloff is valid at every ANL-001 size and rate.
- Acceptance is analytic reference spectra (unit tests); simulator results are not device evidence.
