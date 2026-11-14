# Feature Specification: ANL-012 Spectral Flatness

**Feature Branch**: `feature/anl-012` (spec directory `188-anl-012-spectral-flatness`)

**Created**: 2026-11-14

**Status**: Implemented 2026-11-14

**Input**: Roadmap row ANL-012 (docs/FEATURE_ROADMAP_AUTONOMOUS.md), verbatim: "Distinguish tonal and
noise-like frames with bounded values." Acceptance, verbatim: "Sine input reports lower flatness than
white-noise fixture." P2, size S, depends on ANL-001. Verification: "Accelerate/vDSP, deterministic
sample clocks; unit with synthetic PCM + simulator". The brief adds: flatness is the geometric mean
of the bin power over its arithmetic mean, over ANL-010's bin range, in 0…1, with the geometric mean
taken as exp(mean(log(p + ε))) for a tiny ε relative to a floor; silence reads 0 with no NaN; no
extra FFT and no allocation; mirror ANL-011 (spectral rolloff); a binding source with the inspector
name "Flatness".

Identifiers carry the roadmap ID: requirements `ANL-012-R1…`, success criteria `ANL-012-S1…`,
tasks `ANL-012-T01…`. Other features are cited by their own IDs: ANL-001 (windowed magnitude
spectra), ANL-008 (mid transient, whose breadth term uses a band-limited flatness), ANL-010
(spectral centroid and the shared bin-range rule), ANL-011 (spectral rolloff, the pattern followed
here), ANL-016 (analysis event bus), MOD-002 (audio feature sources and bindings), SHD-009
(expressions that read audio sources), UIX-003 (parameter inspector names).

## Baseline: what exists today (audit of 2026-11-14, commit `2a895211`, ANL-011 integrated)

This is a gap row ("Gap candidate; re-audit at implementation"). The audit confirms the gap: no
public flatness exists in `Packages/` or `Apps/`.

| Area | Today | Gap for this row |
|---|---|---|
| Spectra | ANL-001 periodic-Hann linear magnitudes; the bus runs 2,048 points, hop 512, 44.1 kHz. | — |
| Shared range rule | ANL-010 `SpectralBinRange` (whole bins from ≥ 20 Hz, DC excluded, through Nyquist), written for ANL-011 and ANL-012. | Reused as is. |
| ANL-008 helper | `BandTransientDetector.bandBreadth` (private): Float geometric/arithmetic mean over a 1–4 kHz or 6–16 kHz band, absolute 1e-20 log floor, divided by 0.5 and clamped. | Not reused: private, band-limited, Float accumulation over a few hundred bins, and an absolute (scale-dependent) floor. Left unchanged (no behaviour change in ANL-008/009). |
| Spectral shape | ANL-010 centroid, ANL-011 rolloff (`SpectralRolloffEstimator`: −70 dB floor, 0 at silence, vDSP total + portable scan). | No tonal/noise measure. |
| Bus | `AnalysisFrame` carries bands, onset, beat, kick, centroid, loudness, mid and high transients, rolloff. | No flatness field. |
| Modulation | MOD-002 `AudioFeatureSource` (…, `highTransient`, `rolloff`, `lfo(i)`); SHD-009 opcodes 1–32 are all taken (19 = rolloff, 20 = `min`); no worktree claims 33. | No flatness source; the brief's "opcode 20" is taken, so 33 is used. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: decisions delegated, no
human interaction); each answer is the recommended, conservative option.

- Q: What is flatness? → A: Wiener entropy over bin power P_k = m_k² on ANL-010's `SpectralBinRange` (whole bins from 20 Hz, DC excluded, through Nyquist): F = G / A with A = (1/K)·Σ P_k and G = exp((1/K)·Σ ln(P_k + ε)), K the bin count. Power, not magnitude, matching ANL-010/011 and the textbook definition (a white-noise frame then reads e^−γ ≈ 0.56) (ANL-012-R1, R2).
- Q: What is ε? → A: ε = 10⁻¹² · A (−120 dB below the frame's mean bin power), so the measure stays scale-invariant: the same sound at any level above the floor reads the same flatness. A lone non-zero bin then reads about 10⁻¹² (effectively 0) instead of −∞ in the log; a flat spectrum reads (P + ε)/P = 1 + 10⁻¹², clamped to 1. Rejected: an absolute ε like ANL-008's 1e-20 (scale-dependent near the floor), and dropping zero bins (a pure tone would then read 1) (ANL-012-R2).
- Q: Which value is exposed: linear or dB? → A: Linear F, clamped to [0, 1], is the frame field and the binding value. It is already bounded; a dB scale needs an arbitrary lower endpoint (−60 dB? −120 dB?) and would make the acceptance thresholds depend on that choice. Authors who want more spread in the tonal range reshape it with the binding's output range or an SHD-009 formula (`sqrt(audio.flatness)`) (ANL-012-R3).
- Q: What happens at silence? → A: ANL-011's rule: when Σ P_k / 1.5 (power relative to a full-scale sine) is at or below −70 dB, the reading is 0 and reports no signal; also before any signal and after each session start. Silence must not read as "noise-like" (which a near-zero dither would otherwise read). Non-finite magnitudes count as power 0 (they stay in K); every value is finite (ANL-012-R4).
- Q: Cost and backends? → A: No extra FFT: the frame's ANL-001 magnitudes are read. The arithmetic total uses vDSP (`vDSP_svesq`) when Accelerate is compiled in and the backend allows it (a non-finite total falls back to the portable loop); the log sum is a portable Double loop on both (a vector log would need a scratch buffer, and the Double sum keeps both paths within 10⁻⁶). No buffers, no allocation, no lock, no clock, no temporal smoothing (MOD-002 envelopes smooth) (ANL-012-R5, R9, R10).
- Q: Configuration? → A: `SpectralFlatnessConfiguration`: sample rate, lower/upper frequency, floor dB (defaults 44.1 kHz, 20 Hz, Nyquist, −70 dB). A code/pipeline value like every ANL-0xx parameter: no Settings row and no UserDefaults key (ANL-012-R1, R11).
- Q: What is the source called, and which opcode? → A: MOD-002 source `audio.flatness`, SHD-009 opcode 33 (permanent; the brief's 20 is `min`, and 33 is the first free value, checked in every worktree), inspector name "Flatness". The analysis frame carries `flatness`; the app's native visual feeds it to its bindings like the rolloff. No new UI (ANL-012-R6 to R8).
- Q (speckit-clarify pass): Readouts, diagnostics export or stored data beyond a binding's source ID? → A: No. A binding stores only `audio.flatness`, which older builds orphan like any unknown source (MOD-013): no scene version bump, no stored key (ANL-012-R11).
- Q (speckit-clarify): How tight is the white-noise acceptance, given that one frame's flatness varies? → A: Every seeded noise frame (2,048 points, Hann, at least 8 frames) reads > 0.4, and their mean lies in 0.45…0.65 around e^−γ ≈ 0.561; the sine reads < 0.05 and at least 0.3 below the lowest noise frame. Why: the per-frame spread of a ~1,000-bin estimate is a few hundredths, so these bounds are robust yet still separate tonal from noise-like by a wide margin (ANL-012-S1).
- Q (speckit-clarify): What per-frame cost is acceptable? → A: One pass for the total (vDSP or portable) plus one Double log pass over the analysed bins (~1,020 bins at 2,048 points), no allocation; the new package tests together add under 1 s on the host (owner rule 7) (ANL-012-R5, S7).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tones read low, noise reads high (Priority: P1)

A visual author binding a parameter to "Flatness" needs pure tones to read near 0 and noise to read
clearly higher, so a visual can tell a sustained note from a hiss or a cymbal wash.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed a deterministic sine and a seeded white-noise fixture.

**Acceptance Scenarios**:

1. **Given** a single-bin sine spectrum, **When** measured, **Then** flatness < 0.05.
2. **Given** a sine rendered to PCM and windowed by ANL-001, **When** measured, **Then** flatness < 0.05.
3. **Given** seeded white-noise PCM frames, **When** measured, **Then** each frame reads > 0.4 and the mean is near e^−γ ≈ 0.56.
4. **Given** both, **Then** sine < noise by at least 0.3.
5. **Given** a flat spectrum (equal power in every analysed bin), **Then** flatness = 1 within 10⁻⁹.

### User Story 2 - Silence and bad input are calm (Priority: P1)

**Acceptance Scenarios**:

1. **Given** digital silence or dither-level noise, **When** measured, **Then** flatness is 0 and no signal is reported.
2. **Given** NaN or ±∞ magnitudes, **When** measured, **Then** the value is finite and in 0…1.
3. **Given** a tone then silence, **Then** the silent frames read 0.

### User Story 3 - The same input reads the same on every build (Priority: P2)

1. **Given** the same spectrum, **When** measured twice, **Then** the results are bit-equal; the vDSP and portable paths agree within 10⁻⁶.

### User Story 4 - Flatness is a modulation source (Priority: P2)

1. **Given** the analysis pipeline fed a tone then noise, **Then** frames carry flatness and every noise frame reads higher than every tone frame.
2. **Given** the native visual with a Flatness binding on the glow, **Then** the glow follows it, and the inspector names the source "Flatness".

### Edge Cases

- Only one bin in range (tiny FFT at a low rate): F = 1 when that bin is above the floor (G = A).
- Frames at another sample rate or with a wrong magnitude count: ignored (reading unchanged).
- A session restart resets the reading to 0.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-012-R1**: The system MUST compute, per spectrum frame, the flatness over ANL-010's analysed range using bin power m², at the frame's own FFT size and rate, with no temporal smoothing.
- **ANL-012-R2**: Flatness MUST be exp(mean(ln(P_k + ε))) / mean(P_k) with ε = 10⁻¹² × mean(P_k), clamped to [0, 1].
- **ANL-012-R3**: The published value MUST be the linear flatness in 0…1.
- **ANL-012-R4**: At or below the −70 dB floor, and before any signal, flatness MUST be 0 with no signal reported; non-finite magnitudes count as 0; every value MUST be finite.
- **ANL-012-R5**: Flatness MUST reuse the frame's existing spectrum; with Accelerate compiled in, the vDSP path MUST agree with the portable path within 10⁻⁶.
- **ANL-012-R6**: The ANL-016 pipeline MUST compute flatness on every spectrum frame and carry it in every feature frame; session starts MUST reset it.
- **ANL-012-R7**: MOD-002 MUST offer `audio.flatness` (missing or non-finite reads 0), usable in bindings and in SHD-009 expressions through permanent opcode 33; the inspector MUST name it "Flatness".
- **ANL-012-R8**: The app's native visual MUST feed flatness to its bindings.
- **ANL-012-R9**: Processing a frame MUST NOT allocate, lock, log, do I/O or read a clock (Constitution VII).
- **ANL-012-R10**: The feature MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`).
- **ANL-012-R11**: Nothing here reaches projectM (Constitution VIII); no new setting, stored key, network or UI.

### Key Entities

- **Flatness configuration**: sample rate, analysed range, silence floor.
- **Flatness reading**: value 0…1, whether the frame was above the floor.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-012-S1**: A sine reads < 0.05; every seeded white-noise frame reads > 0.4 with a mean in 0.45…0.65; the sine is at least 0.3 below the lowest noise frame (the roadmap acceptance).
- **ANL-012-S2**: A flat spectrum reads 1 within 10⁻⁹.
- **ANL-012-S3**: Silence, dither and non-finite input read 0 or a finite value in 0…1.
- **ANL-012-S4**: Repeats are bit-equal; vDSP and portable agree within 10⁻⁶.
- **ANL-012-S5**: Through the real pipeline, noise frames read higher flatness than tone frames.
- **ANL-012-S6**: `audio.flatness` round-trips, binds, compiles to opcode 33 and drives the glow in the app; the inspector reads "Flatness".
- **ANL-012-S7**: The new package tests add well under a second; every existing test passes.

## Implementation results (2026-11-14)

Acceptance (`SpectralFlatnessTests`, 2,048 points at 44.1 kHz; identical on the host with vDSP and in
the Linux shape):

| Input | Flatness |
|---|---|
| Single-bin sine spectrum (bin 93) | 1.0 × 10⁻¹² |
| PCM sine, bin-centred (bin 93) / 1 kHz, through ANL-001 (Hann) | 1.1 × 10⁻¹² / 6.4 × 10⁻¹² |
| Seeded white noise, 8 frames (seeds 0x5EED…) | min 0.544, mean 0.5619 (e^−γ = 0.5615) |
| Flat spectrum (equal power in every analysed bin), both backends | 1 within 10⁻⁹ |
| One-bin range | 1 |
| Silence, ±1 LSB dither, silence after a tone | 0, no signal |

The sine sits ~0.54 below the lowest noise frame (margin required: 0.3). Windowed sines read near
10⁻¹² because their leakage bins fall below ε (−120 dB re the mean), which is the intended floor.
NaN/±∞ magnitudes keep the value finite and in 0…1 (a poisoned tone stays < 0.05, poisoned noise
> 0.4). Backends agree within 10⁻⁶, repeats are bit-equal, ×10 magnitude reads the same flatness.
Through `AnalysisPipeline`: silent lead frames read 0, 440 Hz frames ≤ 5.8 × 10⁻¹², noise frames
≥ 0.54 (38 frames).

Test cost (owner rule 7): SpectralFlatnessTests (6 tests) take 0.10 s on the host and 0.14 s in the
Linux shape. AnalysisFeatures in the Linux shape: 167 → 173 tests, all pass (83.7 s, dominated by
existing tests). ParameterGraph: 182 tests, 3 new, all pass (12 s). App: `AudioFeatureBindingAppTests`
9/9 on "ANL12 iPhone 17" (iOS 27.2) in 1.4 s. No type-check warning (`-warn-long-function-bodies=300`,
`-warn-long-expression-type-checking=150`). PosterBoard reports: 25 before, 25 after.

Audit (ANL-012-R11): flatness only reaches `AudioFeatureFrame` and MOD-002 bindings; no projectM
call, setting, UserDefaults key, network API or UI was added. ANL-008's band breadth is unchanged.

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; flatness is valid at every ANL-001 size and rate.
- Acceptance is synthetic PCM and reference spectra (unit tests); simulator results are not device evidence.
