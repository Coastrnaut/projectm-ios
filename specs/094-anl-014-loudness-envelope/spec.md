# Feature Specification: ANL-014 Loudness Envelope

**Feature Branch**: `feature/anl-014` (spec directory `094-anl-014-loudness-envelope`)

**Created**: 2026-11-14

**Status**: In progress (implementation)

**Input**: User description: "Implement ANL-014 (Loudness envelope) from
docs/FEATURE_ROADMAP_AUTONOMOUS.md. Observable behavior, verbatim: "Expose normalized short-term
perceived level for automation." Acceptance, verbatim: "Envelope remains bounded and follows step
amplitude with documented lag." Dependencies: ANL-001 (integrated). Marked "Extension (existing
level meter)". Verification: unit tests with synthetic PCM, plus the simulator. Follow ANL-007 and
ANL-010's pattern for a per-frame feature on the analysis bus and a MOD-002 modulation source.
Honor the repository constitution and owner rules 4, 7 and 8."

Identifiers carry the roadmap ID so they never collide with other features: requirements are
`ANL-014-R1…`, success criteria `ANL-014-S1…`, tasks `ANL-014-T01…`. Other features are cited by
their own IDs: ANL-001 (windowed magnitude spectra), ANL-003 (band smoothing and its attack/release
rule), ANL-007 (kick), ANL-010 (centroid, the pattern followed here), ANL-015 (section energy
change, a later row that depends on this one), ANL-016 (analysis event bus), AUD-008 (input trim),
AUD-009 (channel selection), AUD-011 (noise gate), AUD-012 (source switching), MOD-002 (audio
feature sources and bindings), SHD-009 (expressions that read audio sources).

## Baseline: what exists today (audit of 2026-11-14, commit `ab68d80`)

The row is marked "Extension (existing level meter)". The audit finds that the existing meter is
not reachable by automation and measures something different:

| Area | Today | Gap for this row |
|---|---|---|
| Level meter | AudioCore `LevelMeter.measure` gives peak and RMS in dBFS (floor −120) of each raw sink block. `AudioAnalyzer` feeds it to the audio-state classifier (silent / active), the capture manager's `levels`, the session peak/mean, the CaptureLab diagnostics and export, and the performance overlay's audio state. | Unweighted (a 50 Hz rumble counts as much as a 2 kHz voice), unsmoothed, per capture block, on the raw sink *before* channel selection, trim and gate, and on the capture side: nothing reaches the analysis bus or a binding. |
| Analysis copy | The analysis tap carries the normalized audio after AUD-009 channel selection, AUD-008 trim and AUD-011 gate (non-finite samples sanitized since AUD-012). ANL-016's `AnalysisPipeline` turns it into 2,048-point spectra at hop 512 (44.1 kHz) and publishes per frame `AnalysisFrame` (bands, onset flux, beat, `kickEnvelope`, `centroidHz`, `centroid`). | No level value on the bus. |
| Modulation | MOD-002 `AudioFeatureSource` = `band(i)`, `bandMean`, `onset`, `beatConfidence`, `kick`, `centroid` (SHD-009 opcodes 3-6, 9, 15). `bandMean` is the mean of the decibel-normalized bands: a spectral-shape average, not a level (a pure tone lights one band, so its mean is low however loud it is). The app's native visual feeds bands, kick and centroid to its bindings. | No perceived-level source. |

## Clarifications

### Session 2026-11-14

Answered by Claude under the owner's standing approval (owner rule 4: routine decisions delegated,
no human interaction); each answer is the recommended, conservative option.

- Q: Where is the envelope computed: by extending AudioCore's level meter, or in the analysis pipeline on the analysis copy? → A: In the ANL-016 analysis pipeline, from the spectra it already computes, on the analysis copy. Why: (1) "for automation" means MOD-002 bindings, which are fed from the analysis bus, not from the capture manager; (2) the analysis copy is the audio after AUD-009 channel selection, AUD-008 trim and AUD-011 gate, the same audio every other bound feature sees, while the meter sits on the raw sink before them; (3) the meter's job (silent/active classification, diagnostics, export, overlay) has fixed thresholds and recorded evidence behind it, so it stays unchanged (R12). The "extension" is conceptual: the row extends level measurement to a weighted, smoothed, normalized value; no meter code is shared (ANL-014-R1, R7, R12).
- Q: Which frequency weighting approximates perceived level? → A: ITU-R BS.1770 K-weighting (its two filter stages: the +4 dB high shelf near 1.7 kHz and the high-pass near 38 Hz), applied to each analysis frame's spectrum as the stages' exact power response at each bin's frequency, designed for the configured sample rate from the standard's analog parameters (the formulas libebur128 uses, so at 48 kHz they reproduce the standard's published coefficients). The frame's mean-square is Σ w_k·m_k² / 3 over bins 1…N/2 (ANL-001's Hann magnitudes: Σ m² = 3 × the mean square, for a sine or for noise), and its level is −0.691 + 10·log10 of that, in LKFS-like decibels, so a full-scale 997 Hz sine reads −3.01. Why: K-weighting is the broadcast loudness standard and is what "perceived level" means in practice; applying it to the spectrum reuses the FFT the bus already runs (no per-sample filtering, no extra state, identical on every backend and on Linux), and for audio that is steady over a 46 ms window the result equals the time-domain filter's. Rejected: time-domain biquads (they would need the time-domain analysis copy, which the pipeline does not keep, and per-sample work for no visual gain); A-weighting (designed for quiet sounds; it cuts bass far harder than loudness perception at music levels, so a kick drum would barely register); unweighted RMS (the existing meter's measure; a 50 Hz rumble would read as loud as a voice) (ANL-014-R1, R6).
- Q: Which window or time constants give "short-term"? → A: Each frame's level comes from the bus's 2,048-sample (46 ms) Hann window every 512 samples (11.6 ms); the normalized value is then smoothed with ANL-003's one-pole attack/release rule (y ← y + a·(x − y), a = 1 − exp(ln 0.1·Δt/τ), Δt = the frame's hop / sample rate, so τ is the 90 % time of the smoother alone): attack 100 ms, release 400 ms. The documented lag is the measured 90 % step time of the whole chain (window plus smoother) for the R4 step, recorded in Implementation results and tested within one frame. Smoothing happens on the normalized (decibel) value, so the lag of a step does not depend on its size. The first frame after creation or a session start takes its value directly (ANL-003's snap rule). Why: BS.1770's "momentary" 400 ms rectangular window lags visibly on rises, and its 3 s "short-term" is far too slow for visuals; a fast attack keeps hits visible, while a release equal to the momentary window keeps the value calm between beats and matches loudness perception (sounds feel loud quickly and fade slowly). Rejected: a symmetric 400 ms window (sluggish rises), no smoothing (the per-frame level flickers with every waveform cycle of a bass note, and a binding's own envelope would then be the only control) (ANL-014-R3, R4).
- Q: How is the level mapped to 0…1, and what does silence read? → A: n = clamp((L + 60) / 60, 0, 1) with L the frame's level in LKFS-like dB: −60 → 0, −30 → 0.5, 0 → 1, linear in decibels (perceived loudness is roughly logarithmic, and music masters sit around −14 to −8, at 0.77-0.87, leaving headroom; very quiet content near −60 reads near 0). A frame whose weighted mean-square is 0, non-finite, or below 10⁻¹² reports a level of −120 dB (finite; the existing meter's floor) and a target of 0. The smoothed envelope then releases toward 0 and is set to exactly 0 once it falls below 0.001 (the snap is below a visible change); it is clamped to 0…1 after every step. Non-finite magnitudes count as 0. Every published value is finite. Why: a fixed range keeps bindings predictable across sources (no auto-gain that would make quiet music look loud); exact 0 at silence means bound parameters return to their rest values (ANL-014-R2, R5).
- Q: What is the modulation source called, and what does the bus carry? → A: MOD-002 source "Loudness", stable ID `audio.loudness`, reading the smoothed normalized envelope; SHD-009 opcode 16 (the next free permanent opcode: 1-15 and 20-32 are taken). The bus's feature frame carries `loudness` (the envelope, 0…1) and `loudnessDecibels` (the frame's unsmoothed level, −120 or above, for readouts and for ANL-015's later section-change detector). The app's native visual feeds the envelope to its bindings, like the kick and the centroid. No UI and no setting: the times and range are configuration constants. "Loudness" rather than "Level" because the value is weighted and smoothed, unlike the meter's level (ANL-014-R7 to R9, R12).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A parameter follows how loud the music sounds (Priority: P1)

A visual author binds a parameter (glow, scale) to the music's loudness: quiet passages read low,
loud passages read high, and the value moves smoothly enough to look good but fast enough to follow
the music.

**Why this priority**: It is the roadmap acceptance.

**Independent Test**: Package tests feed synthetic tones and steps (deterministic sample clock) and
read the envelope frame by frame.

**Acceptance Scenarios**:

1. **Given** a tone that steps from −40 dBFS to −10 dBFS and back, **When** analysed, **Then** the envelope rises to the loud level and falls back to the quiet level, reaching 90 % of each step within the documented rise and fall times (to within one analysis frame).
2. **Given** the same tone at rising levels, **When** analysed, **Then** the settled envelope rises strictly with the level.
3. **Given** equal-amplitude tones at 100 Hz and 2 kHz, **When** analysed, **Then** the 2 kHz tone reads louder, as human hearing (and the chosen weighting) rates it.

---

### User Story 2 - The value never breaks (Priority: P1)

Whatever arrives, the value bound to a visual stays in range and calm.

**Why this priority**: A value outside 0…1, or not a number, would make bound visuals flash or
freeze.

**Independent Test**: Full-scale noise, clipping square waves, injected non-finite samples, and
silence.

**Acceptance Scenarios**:

1. **Given** full-scale noise, a clipping square wave, or input containing non-finite samples, **When** analysed, **Then** every value is finite and within 0…1.
2. **Given** silence (from the start, or after loud audio), **When** analysed, **Then** the value is 0 from the start, or decays to exactly 0 after loud audio, and is never non-finite.

---

### User Story 3 - Loudness is a modulation source (Priority: P2)

A visual author can bind any modulatable parameter to "Loudness" and use it in an expression.

**Why this priority**: The value is useful to visuals only through MOD-002.

**Independent Test**: A pipeline test, ParameterGraph tests (ID round trip, binding, expression)
and an app unit test that a Loudness binding on the native visual drives its target.

**Acceptance Scenarios**:

1. **Given** the real analysis pipeline fed a quiet tone then a loud tone, **When** frames are read, **Then** they carry the envelope and the loud tone's frames read higher.
2. **Given** the native visual with a binding from Loudness, **When** frames carry an envelope, **Then** the bound parameter follows it.

### Edge Cases

- Content below about 40 Hz is attenuated by the weighting (as in loudness standards); a 20 Hz tone reads quieter than a 1 kHz tone of the same amplitude.
- A level above the normalization ceiling (very loud, bright content) reads 1 (clamped); below the floor reads 0.
- Non-finite spectrum values: treated as 0 for that bin; never a non-finite result.
- Frames at another sample rate or FFT size than configured: ignored (the value is kept).
- A session restart (source switch, restart): the envelope restarts from 0 as at creation.

## Requirements *(mandatory)*

### Functional Requirements

- **ANL-014-R1**: The system MUST compute, for each analysis frame, the K-weighted level of the analysis copy: L = −0.691 + 10·log10(Σ w_k·m_k² / 3) over bins 1…N/2, w_k the BS.1770 K-weighting power response at bin k's frequency for the configured rate (Clarifications), −120 dB when the mean-square is 0, non-finite or below 10⁻¹².
- **ANL-014-R2**: The level MUST be mapped to n = clamp((L + 60) / 60, 0, 1).
- **ANL-014-R3**: The normalized value MUST be smoothed with ANL-003's attack/release rule (attack 100 ms, release 400 ms as the smoother's 90 % times; Δt = hop / rate from the sample count), the first frame after creation or a session start taken directly, the result clamped to 0…1 and set to exactly 0 below 0.001 when the target is 0.
- **ANL-014-R4**: For a 1 kHz tone stepping from −40 dBFS to −10 dBFS and back, the whole chain's 90 % rise and 90 % fall times (measured on the sample clock from the step to the end of the first frame at or past 90 % of the change) MUST match the documented values within one analysis frame (11.6 ms at hop 512).
- **ANL-014-R5**: Every published value MUST be finite and within 0…1 for any input, including full-scale noise, clipping, non-finite samples and silence; silence MUST read 0 from the start and decay to exactly 0 after sound.
- **ANL-014-R6**: The settled value MUST increase with input level, and equal-amplitude tones MUST read in the order of the chosen weighting (2 kHz above 100 Hz).
- **ANL-014-R7**: The ANL-016 pipeline MUST compute the envelope on every spectrum frame and carry it in every feature frame, together with the frame's unsmoothed level in decibels; session starts MUST reset it.
- **ANL-014-R8**: MOD-002 MUST offer a "Loudness" source with the stable ID `audio.loudness` that reads the normalized envelope (missing or non-finite reads 0), usable in bindings, the modulation graph, scenes and SHD-009 expressions (the next free permanent opcode).
- **ANL-014-R9**: The app's native visual MUST feed the envelope to its bindings, so a Loudness binding is live.
- **ANL-014-R10**: Processing a frame MUST NOT allocate, lock, log or do I/O (Constitution VII).
- **ANL-014-R11**: The feature MUST build and pass its tests in the package's Linux shape (`-DANALYSIS_NO_ACCELERATE`) and read no clock; time comes from the sample count.
- **ANL-014-R12**: Nothing computed here reaches projectM (Constitution VIII, ADR-0008 decision 5); the existing level meter, its consumers and the audio-state classifier are unchanged; no new setting, no stored data beyond a scene binding's source ID, no network, no UI.

### Key Entities

- **Loudness configuration**: sample rate, FFT size, decibel normalization range, attack and release times.
- **Loudness reading**: the frame's unsmoothed weighted level in decibels, and the smoothed normalized envelope.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **ANL-014-S1**: For the −40 → −10 → −40 dBFS step, the 90 % rise and fall times match the documented lag within one frame (the roadmap acceptance), and the envelope never leaves 0…1.
- **ANL-014-S2**: Full-scale noise, a clipping square wave, input with non-finite samples, and silence all keep every value finite and within 0…1; silence after sound reaches exactly 0.
- **ANL-014-S3**: Settled values rise strictly over at least four input levels; 2 kHz reads above 100 Hz at equal amplitude; a full-scale 997 Hz sine reads the loudness standard's reference level within 0.2 dB.
- **ANL-014-S4**: Through the real pipeline, a loud tone's frames read higher than a quiet tone's.
- **ANL-014-S5**: `audio.loudness` round-trips, binds, compiles in an expression and drives a bound parameter in the app.
- **ANL-014-S6**: The new package tests add at most a few hundred milliseconds to the AnalysisFeatures suite in the Linux shape, and every existing test (and every dependent package's) passes.

## Implementation results (2026-11-14)

### Documented lag

Whole chain (2,048-point Hann window every 512 samples, then the attack/release smoother), for a
1 kHz tone stepping −40 → −10 → −40 dBFS at 44.1 kHz, measured on the sample clock from the step to
the end of the first frame at or past 90 % of the change (`LoudnessEnvelopeTests.
testStepIsFollowedWithTheDocumentedLag`; identical with the vDSP and the portable backend):

| Step | Envelope before → after | 90 % time | Smoother alone (τ) | Window part |
|---|---|---|---|---|
| Rise −40 → −10 dBFS | 0.283 → 0.783 | **115.3 ms** (5,086 samples) | 100 ms | +15.3 ms |
| Fall −10 → −40 dBFS | 0.783 → 0.283 | **433.4 ms** (19,115 samples) | 400 ms | +33.4 ms |

The test holds each within one frame (512 samples, 11.6 ms) and within [τ − one frame, τ + one
window]. Because smoothing works on the decibel-normalized value, the lag does not depend on the
step's size. From −10 dBFS to digital silence the envelope reaches exactly 0 after 1.19 s.

### Levels and weighting

Single 2,048-point windows (fresh envelope, so the envelope is the frame's normalized level):

| Input | Level (dB, LKFS-like) | Envelope |
|---|---|---|
| 997 Hz sine, 0 dBFS | −3.007 (BS.1770 reference −3.01) | 0.950 |
| 1 kHz sine, −10 dBFS | −13.0 | 0.783 |
| 1 kHz sine, −20 dBFS | −23.0 | 0.617 |
| 1 kHz sine, −30 dBFS | −33.0 | 0.450 |
| 1 kHz sine, −40 dBFS | −43.0 | 0.283 |
| 1 kHz sine, −50 dBFS | −53.0 | 0.117 |
| White noise ±1 (seeded) | −1.63 | 0.973 |
| Square wave ±1, 1 kHz | +0.83 | 1 (clamped) |
| Digital silence | −120 | 0 |

Equal amplitude (−20 dBFS), K-weighted: 20 Hz −34.61 dB < 100 Hz −24.87 dB < 1 kHz −23.00 dB <
2 kHz −20.63 dB (2 kHz reads 4.2 dB above 100 Hz, as the standard's curve predicts).

## Assumptions

- The bus keeps 2,048-point spectra at hop 512 and 44.1 kHz; the envelope is valid at every ANL-001 size and rate it is configured for.
- "Short-term perceived level" means a weighted, smoothed level for visuals, not a certified loudness meter: no gating, no integrated or long-term loudness, no true-peak.
- The envelope sees the analysis copy after AUD-009 channel selection, AUD-008 trim and AUD-011 gate, so it moves with those controls, as every other bus feature does.
- Simulator results are not device evidence; acceptance is synthetic PCM (unit tests).
